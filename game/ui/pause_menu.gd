extends Control
## Pause overlay: Resume / Restart practice / Settings / Return to selection, plus the sailing help
## (guidance, ammo tracks, live key bindings) kept off the in-play HUD.

signal resume_requested
signal restart_requested
signal return_requested
signal settings_requested

const SelectionMenu := preload("res://ui/selection_menu.gd")
const Bindings := preload("res://input_bindings.gd")

const GUIDANCE := "Full sails: faster · Reefed: tighter turns · Into the wind is slow, but you can still turn."
const DUEL_GUIDANCE := "Sink the enemy, or exhaust its sails or crew. Turn a broadside toward it to fire."
const ESCAPE_HINT := "Or escape: chain shot slows pursuers. Leave sails above zero, then use wind and open sea to break away.\n%s/%s cycle to Chain · %s/%s fire · %s toggle sails (keep full) · %s/%s steer downwind"
const AMMO_HELP := "Round: hull / Chain: sails / Grape: crew · Changing ammo restarts that side's reload."

var resume_button: Button
var restart_button: Button
var settings_button: Button
var return_button: Button
var guidance_label: Label
var bindings_label: Label


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)  # also blocks clicks from reaching the HUD
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.theme_type_variation = "NauticalHeading"
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	resume_button = _button(box, "Resume", resume_requested)
	restart_button = _button(box, "Restart practice", restart_requested)
	settings_button = _button(box, "Settings", settings_requested)
	return_button = _button(box, "Return to selection", return_requested)
	panel.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	var menu_row := CenterContainer.new()
	menu_row.add_child(panel)
	column.add_child(menu_row)
	var help := VBoxContainer.new()
	guidance_label = _help_label(help)
	_help_label(help).text = AMMO_HELP
	bindings_label = _help_label(help)
	var help_panel := PanelContainer.new()
	help_panel.add_child(help)
	column.add_child(help_panel)
	center.add_child(column)
	add_child(center)
	SelectionMenu.link_focus([resume_button, restart_button, settings_button, return_button])


## Refreshed on every pause so guidance matches the encounter and bindings are live.
func show_help(sim) -> void:
	guidance_label.text = guidance_text(sim.preset_id)
	bindings_label.text = bindings_text()


static func guidance_text(preset_id: String) -> String:
	if preset_id == "practice":
		return GUIDANCE
	return DUEL_GUIDANCE + "\n" + ESCAPE_HINT % [
		Bindings.binding_label("cycle_port"), Bindings.binding_label("cycle_starboard"),
		Bindings.binding_label("fire_port"), Bindings.binding_label("fire_starboard"),
		Bindings.binding_label("toggle_sails"),
		Bindings.binding_label("turn_left"), Bindings.binding_label("turn_right")]


## Live key bindings; shared battles have no reset, and their Esc opens a menu that never pauses.
static func bindings_text(include_reset := true) -> String:
	var reset := " · %s reset" % Bindings.binding_label("reset_practice") if include_reset else ""
	return "%s/%s steer · %s sails · %s %s%s\n%s fire Port · %s fire Starboard · %s cycle Port · %s cycle Starboard" % [
		Bindings.binding_label("turn_left"), Bindings.binding_label("turn_right"),
		Bindings.binding_label("toggle_sails"), Bindings.binding_label("pause"), "pause" if include_reset else "menu", reset,
		Bindings.binding_label("fire_port"), Bindings.binding_label("fire_starboard"),
		Bindings.binding_label("cycle_port"), Bindings.binding_label("cycle_starboard")]


func _help_label(parent: Node) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 900
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, request: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 48)
	button.pressed.connect(request.emit)
	parent.add_child(button)
	return button
