extends Node
## Mode controller: selection / sailing / paused / result. Owns the simulation and gates
## it; the SceneTree itself is never paused so menus keep running.
## Presentation (HUD and $ArenaView) reads `sim` without mutating it.

## Emitted after sim.reset() (start or restart): views must resync from `sim`.
signal practice_started
## Emitted on every mode change; "selection" means `sim` holds no encounter.
signal mode_changed(new_mode: String)

const NavalSimulation := preload("res://sim/naval_simulation.gd")
const Definitions := preload("res://sim/definitions.gd")
const Bindings := preload("res://input_bindings.gd")
const AIController := preload("res://sim/ai_controller.gd")
const SelectionMenu := preload("res://ui/selection_menu.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
const ResultMenu := preload("res://ui/result_menu.gd")
const Hud := preload("res://ui/hud.gd")
const Settings := preload("res://settings.gd")
const SettingsMenu := preload("res://ui/settings_menu.gd")
const Presentation := preload("res://view/combat_presentation.gd")
const CombatAudio := preload("res://audio/combat_audio.gd")
const UpdateService := preload("res://update/update_service.gd")

const DT := 1.0 / 60.0
const PRESET := "practice"
const TURN_ACTIONS := ["turn_left", "turn_right"]
## One-shot actions: a non-echo press while sailing queues one command for the next tick.
const EDGE_ACTIONS := ["fire_port", "fire_starboard", "cycle_port", "cycle_starboard"]

var sim = NavalSimulation.new()
var ai = AIController.new()
var mode := "selection"
var settings = Settings.new()

@onready var arena_view: Node2D = $ArenaView
var selection: Control
var hud: Control
var pause_menu: Control
var result_menu: Control
var settings_menu: Control
var combat_audio: Node
var update_service: Node

var _held := {}  # turn actions freshly pressed while sailing and not yet released
var _toggle_queued := false  # parity of non-echo toggle presses since the last tick
var _edges := {}  # EDGE_ACTIONS pressed since the last tick (held keys never repeat)
var _reset_queued := false  # reset_practice pressed since the last tick


func _ready() -> void:
	# Dedicated server / headless bot: leave before settings, input, audio or UI exist.
	var args := OS.get_cmdline_user_args()
	for role in ["server", "bot"]:
		if "--" + role in args:
			get_tree().change_scene_to_file.call_deferred("res://net/%s_main.tscn" % role)
			return
	get_window().min_size = Vector2i(1280, 720)
	$UI.layer = 2
	Bindings.install_defaults()
	settings.load_settings()
	settings.apply_values(settings.values)
	combat_audio = CombatAudio.new()
	combat_audio.name = "CombatAudio"
	add_child(combat_audio)
	var theme := _make_theme()
	hud = Hud.new()
	pause_menu = PauseMenu.new()
	result_menu = ResultMenu.new()
	selection = SelectionMenu.new()
	settings_menu = SettingsMenu.new()
	for control in [hud, pause_menu, result_menu, selection, settings_menu]:
		control.theme = theme
		$UI.add_child(control)
		_ornament_panels(control)
	get_viewport().size_changed.connect(_fit_ui)
	_fit_ui()
	selection.start_requested.connect(start_encounter)
	selection.quit_requested.connect(get_tree().quit)
	pause_menu.resume_requested.connect(set_paused.bind(false))
	pause_menu.restart_requested.connect(restart_practice)
	pause_menu.return_requested.connect(return_to_selection)
	result_menu.replay_requested.connect(restart_practice)
	result_menu.return_requested.connect(return_to_selection)
	selection.settings_requested.connect(open_settings)
	pause_menu.settings_requested.connect(open_settings)
	settings_menu.closed.connect(close_settings)
	settings.changed.connect(_on_settings_changed)
	selection.show_notice(settings.notice)
	update_service = UpdateService.new()
	update_service.name = "UpdateService"
	add_child(update_service)
	update_service.state_changed.connect(selection.show_update_state)
	selection.check_updates_requested.connect(update_service.check)
	selection.update_requested.connect(update_service.update_and_restart)
	selection.full_download_requested.connect(func() -> void: OS.shell_open(UpdateService.RELEASES_URL))
	# The service picked its first state (disabled in dev builds) before the menu listened.
	selection.show_version(update_service.version)
	selection.show_update_state(update_service.state, update_service.detail)
	_enter_mode("selection")


func _physics_process(_delta: float) -> void:
	advance_tick()


## Exactly one fixed step per call, and only while sailing. No accumulator/catch-up.
func advance_tick() -> void:
	if mode != "sailing" or not sim.result.is_empty():
		return
	if _reset_queued:
		# This tick is the reset: fire/cycle/toggle queued alongside it are discarded, not
		# deferred (restart clears all held/queued input), and views resync via practice_started.
		restart_practice()
		return
	var turn := float(_held.has("turn_right")) - float(_held.has("turn_left"))
	var command := {"turn": turn, "toggle_sails": _toggle_queued}
	for action in EDGE_ACTIONS:
		command[action] = _edges.has(action)
	_toggle_queued = false
	_edges.clear()
	var commands := {NavalSimulation.PLAYER_ID: command}
	if _is_duel():
		# AI sees only a copy; its commands join the player's under the opposition IDs.
		var ai_commands := ai.commands_for_tick(sim.ai_observation(), DT)
		for id in ai_commands:
			if id != NavalSimulation.PLAYER_ID:
				commands[id] = ai_commands[id]
	sim.step(DT, commands)
	var presentation_events: Array = Presentation.normalize_events(sim.events)
	combat_audio.arena_view = arena_view
	combat_audio.consume(presentation_events)
	arena_view.advance_effects()
	hud.advance_effects()
	arena_view.consume_events(presentation_events)
	hud.consume_events(presentation_events)
	hud.refresh(sim)
	if not sim.result.is_empty():
		_enter_mode("result")


## A duel is any non-practice encounter (practice has no AI opponent that acts).
func _is_duel() -> bool:
	return mode == "sailing" and sim.preset_id != PRESET and not sim.ships.is_empty()


func start_practice(vessel_id: String) -> void:
	start_encounter(PRESET, vessel_id)


## Unified fresh start for every encounter: one AI reset, one signal, clean latches.
func start_encounter(preset_id: String, vessel_id: String) -> void:
	if not Definitions.PRESETS.has(preset_id) or not Definitions.VESSELS.has(vessel_id):
		push_error("start_encounter: unknown preset '%s' or vessel '%s'" % [preset_id, vessel_id])
		return
	sim.reset(preset_id, vessel_id)
	ai.reset()
	hud.reset_effects()
	arena_view.reset_effects()
	_enter_mode("sailing")
	combat_audio.start_encounter()
	practice_started.emit()


func restart_practice() -> void:
	if mode != "selection":
		start_encounter(sim.preset_id, sim.selected_vessel_id)


func return_to_selection() -> void:
	combat_audio.clear()
	sim = NavalSimulation.new()
	ai = AIController.new()
	hud.reset_effects()
	arena_view.reset_effects()
	_enter_mode("selection")


func set_paused(value: bool) -> void:
	if value and mode == "sailing":
		combat_audio.set_paused(true)
		_enter_mode("paused")
	elif not value and mode == "paused":
		_enter_mode("sailing")
		combat_audio.set_paused(false)


## Overlays the settings menu on the selection or pause menu. No reset, no resume.
func open_settings() -> void:
	if mode not in ["selection", "paused"] or settings_menu.visible:
		return
	_clear_input()
	selection.visible = false
	pause_menu.visible = false
	settings_menu.open(settings)


## Restores the source menu and focuses its Settings button.
func close_settings() -> void:
	_clear_input()
	settings_menu.visible = false
	var source: Control = pause_menu if mode == "paused" else selection
	source.visible = true
	source.settings_button.grab_focus()


## Live prompts follow applied bindings; the load notice clears once a save succeeds.
func _on_settings_changed() -> void:
	selection.show_notice(settings.notice)
	if mode == "paused":
		pause_menu.show_help(sim)


## Settings gets every event first while open (capture, then Escape = Back); gameplay sees none.
## Release events are observed in every mode; presses count only while sailing.
## Keys held across a transition stay inert until released and pressed again.
func _input(event: InputEvent) -> void:
	if settings_menu.visible:
		var consumed: bool = settings_menu.handle_capture(event)
		if not consumed and event is InputEventKey and event.pressed and not event.echo \
				and event.keycode == KEY_ESCAPE:
			settings_menu.back()
			consumed = true
		if consumed:
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey:
		return  # mouse never steers
	for action in TURN_ACTIONS:
		if event.is_action(action):
			if not event.pressed:
				_held.erase(action)
			elif mode == "sailing" and not event.echo:
				_held[action] = true
	if mode == "sailing":
		if event.is_action_pressed("toggle_sails"):  # is_action_pressed excludes echoes
			_toggle_queued = not _toggle_queued
		for action in EDGE_ACTIONS:
			if event.is_action_pressed(action):
				_edges[action] = true
		if event.is_action_pressed("reset_practice"):
			_reset_queued = true
	if event.is_action_pressed("pause") and mode in ["sailing", "paused"]:
		set_paused(mode == "sailing")
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_input()
		settings_menu.release_all()
		if mode == "result":
			combat_audio.set_paused(true)
		set_paused(true)  # focus-in deliberately never resumes


func _enter_mode(new_mode: String) -> void:
	mode = new_mode
	if mode == "result":
		combat_audio.finish_encounter()
	_clear_input()
	selection.visible = mode == "selection"
	hud.visible = mode != "selection"
	pause_menu.visible = mode == "paused"
	result_menu.visible = mode == "result"
	match mode:
		"selection":
			selection.show_mode_select()
		"paused":
			pause_menu.show_help(sim)
			pause_menu.resume_button.grab_focus()
		"sailing":
			get_viewport().gui_release_focus()
		"result":
			result_menu.show_result(sim)
	if mode != "selection":
		hud.refresh(sim)
	mode_changed.emit(mode)


func _clear_input() -> void:
	_held.clear()
	_toggle_queued = false
	_edges.clear()
	_reset_queued = false


## Shared UI look: >= 18 px text, white outlined labels, semi-opaque dark panels.
func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_type_variation("NauticalHeading", "Label")
	theme.set_font("font", "NauticalHeading", preload("res://assets/fonts/DejaVuSerif-headings.ttf"))
	theme.set_font_size("font_size", "NauticalHeading", 24)
	theme.set_color("font_color", "NauticalHeading", Color(.98, .87, .59))
	for type in ["Label", "Button"]:
		theme.set_font_size("font_size", type, 20)
	theme.set_color("font_color", "Label", Color.WHITE)
	theme.set_color("font_outline_color", "Label", Color.BLACK)
	theme.set_constant("outline_size", "Label", 4)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.07, 0.12, 0.82)
	panel.border_color = Color(.72, .57, .28, .9)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(3)
	panel.set_content_margin_all(10)
	theme.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var button := panel.duplicate()
		button.bg_color = Color(.05, .13, .22, .94) if state in ["hover", "focus"] else Color(.03, .09, .16, .88)
		button.border_color = Color(.95, .8, .43) if state == "focus" else panel.border_color
		theme.set_stylebox(state, "Button", button)
		theme.set_stylebox(state, "OptionButton", button)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.6)
	bar_bg.set_corner_radius_all(2)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.95, 0.82, 0.45)
	bar_fill.set_corner_radius_all(2)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)
	return theme


func _ornament_panels(node: Node) -> void:
	if node is PanelContainer:
		var panel: PanelContainer = node
		panel.draw.connect(func():
			var ink := Color(.78, .64, .35, .7)
			for corner in [Vector2(5, 5), Vector2(panel.size.x - 5, 5), Vector2(5, panel.size.y - 5), panel.size - Vector2(5, 5)]:
				var inward: Vector2 = (panel.size * .5 - corner).sign()
				panel.draw_line(corner, corner + Vector2(inward.x * 7, 0), ink, 1)
				panel.draw_line(corner, corner + Vector2(0, inward.y * 7), ink, 1))
	for child in node.get_children():
		_ornament_panels(child)


## CanvasLayer has no Control parent to supply an anchor rectangle.
func _fit_ui() -> void:
	for control in [hud, pause_menu, result_menu, selection, settings_menu]:
		control.set_anchors_preset(Control.PRESET_TOP_LEFT)
		control.position = Vector2.ZERO
		control.size = get_viewport().get_visible_rect().size
