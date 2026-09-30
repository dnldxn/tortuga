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
const SelectionMenu := preload("res://ui/selection_menu.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
const Hud := preload("res://ui/hud.gd")

const DT := 1.0 / 60.0
const PRESET := "practice"
const TURN_ACTIONS := ["turn_left", "turn_right"]

var sim = NavalSimulation.new()
var mode := "selection"

@onready var arena_view: Node2D = $ArenaView
var selection: Control
var hud: Control
var pause_menu: Control

var _held := {}  # turn actions freshly pressed while sailing and not yet released
var _toggle_queued := false  # parity of non-echo toggle presses since the last tick


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
	if mode != "sailing":
		return
	var turn := float(_held.has("turn_right")) - float(_held.has("turn_left"))
	var commands := {NavalSimulation.PLAYER_ID: {"turn": turn, "toggle_sails": _toggle_queued}}
	_toggle_queued = false
	sim.step(DT, commands)
	hud.refresh(sim)


func start_practice(vessel_id: String) -> void:
	if not Definitions.VESSELS.has(vessel_id):
		push_error("start_practice: unknown vessel '%s'" % vessel_id)
		return
	sim.reset(PRESET, vessel_id)
	_enter_mode("sailing")
	practice_started.emit()


func restart_practice() -> void:
	if mode != "selection":
		start_practice(sim.selected_vessel_id)


func return_to_selection() -> void:
	sim = NavalSimulation.new()
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
	if mode == "sailing" and event.is_action_pressed("toggle_sails"):
		_toggle_queued = not _toggle_queued
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
