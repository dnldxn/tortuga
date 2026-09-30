extends Node
## Mode controller: selection / sailing / paused. Owns the simulation and gates it;
## the SceneTree itself is never paused so menus keep running.
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
const Hud := preload("res://ui/hud.gd")

const DT := 1.0 / 60.0
const PRESET := "practice"
const TURN_ACTIONS := ["turn_left", "turn_right"]
## One-shot actions: a non-echo press while sailing queues one command for the next tick.
const EDGE_ACTIONS := ["fire_port", "fire_starboard", "cycle_port", "cycle_starboard"]

var sim = NavalSimulation.new()
var ai = AIController.new()
var mode := "selection"

@onready var arena_view: Node2D = $ArenaView
var selection: Control
var hud: Control
var pause_menu: Control

var _held := {}  # turn actions freshly pressed while sailing and not yet released
var _toggle_queued := false  # parity of non-echo toggle presses since the last tick
var _edges := {}  # EDGE_ACTIONS pressed since the last tick (held keys never repeat)
var _reset_queued := false  # reset_practice pressed since the last tick


func _ready() -> void:
	Bindings.install_defaults()
	var theme := _make_theme()
	hud = Hud.new()
	pause_menu = PauseMenu.new()
	selection = SelectionMenu.new()
	for control in [hud, pause_menu, selection]:
		control.theme = theme
		$UI.add_child(control)
	selection.start_requested.connect(start_practice)
	selection.quit_requested.connect(get_tree().quit)
	pause_menu.resume_requested.connect(set_paused.bind(false))
	pause_menu.restart_requested.connect(restart_practice)
	pause_menu.return_requested.connect(return_to_selection)
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
	arena_view.advance_effects()
	hud.advance_effects()
	arena_view.consume_events(sim.events)
	hud.consume_events(sim.events)
	hud.refresh(sim)


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
	practice_started.emit()


func restart_practice() -> void:
	if mode != "selection":
		start_encounter(sim.preset_id, sim.selected_vessel_id)


func return_to_selection() -> void:
	sim = NavalSimulation.new()
	ai = AIController.new()
	hud.reset_effects()
	arena_view.reset_effects()
	_enter_mode("selection")


func set_paused(value: bool) -> void:
	if value and mode == "sailing":
		_enter_mode("paused")
	elif not value and mode == "paused":
		_enter_mode("sailing")


## Release events are observed in every mode; presses count only while sailing.
## Keys held across a transition stay inert until released and pressed again.
func _input(event: InputEvent) -> void:
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
	if event.is_action_pressed("pause") and mode != "selection":
		set_paused(mode == "sailing")
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_input()
		set_paused(true)  # focus-in deliberately never resumes


func _enter_mode(new_mode: String) -> void:
	mode = new_mode
	_clear_input()
	selection.visible = mode == "selection"
	hud.visible = mode != "selection"
	pause_menu.visible = mode == "paused"
	match mode:
		"selection":
			selection.show_mode_select()
		"paused":
			pause_menu.resume_button.grab_focus()
		"sailing":
			get_viewport().gui_release_focus()
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
	for type in ["Label", "Button"]:
		theme.set_font_size("font_size", type, 20)
	theme.set_color("font_color", "Label", Color.WHITE)
	theme.set_color("font_outline_color", "Label", Color.BLACK)
	theme.set_constant("outline_size", "Label", 4)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.07, 0.12, 0.82)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(12)
	theme.set_stylebox("panel", "PanelContainer", panel)
	return theme
