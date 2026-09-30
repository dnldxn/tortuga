extends Control
## Mode select (practice / three duels / Quit) -> vessel select (vessels / Start / Back).
## start_requested carries the chosen preset id and vessel id.

signal start_requested(preset_id: String, vessel_id: String)
signal quit_requested

const Definitions := preload("res://sim/definitions.gd")

const MODES := [
	["practice", "Target practice"],
	["duel_sloop", "Sloop duel"],
	["duel_brig", "Brig duel"],
	["duel_frigate", "Frigate duel"],
]
const GUIDANCE := "Sink the enemy, or exhaust its sails or crew. Turn a broadside toward it to fire."

var sailing_button: Button
var duel_buttons := {}  # preset id -> Button
var quit_button: Button
var start_button: Button
var back_button: Button
var vessel_buttons := {}  # vessel_id -> toggle Button

var _mode_screen: Control
var _vessel_screen: Control
var _chosen_preset := "practice"


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var title := Label.new()
	title.text = "Tortuga"
	title.add_theme_font_size_override("font_size", 48)
	var column := [title]
	sailing_button = _button("Target practice")
	column.append(sailing_button)
	duel_buttons["duel_sloop"] = _button("Sloop duel")
	duel_buttons["duel_brig"] = _button("Brig duel")
	duel_buttons["duel_frigate"] = _button("Frigate duel")
	column.append_array([duel_buttons["duel_sloop"], duel_buttons["duel_brig"], duel_buttons["duel_frigate"]])
	var guidance := Label.new()
	guidance.text = GUIDANCE
	guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guidance.custom_minimum_size = Vector2(420, 0)
	column.append(guidance)
	quit_button = _button("Quit")
	column.append(quit_button)
	_mode_screen = _screen(column)

	var heading := Label.new()
	heading.text = "Choose your vessel"
	var group := ButtonGroup.new()
	var vessel_column := [heading]
	for id in Definitions.VESSELS:
		var vessel: Dictionary = Definitions.VESSELS[id]
		var button := _button("%s — %s" % [vessel["display_name"], vessel["description"]])
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		vessel_buttons[id] = button
		vessel_column.append(button)
	vessel_buttons["sloop"].button_pressed = true
	start_button = _button("Start")
	back_button = _button("Back")
	vessel_column.append_array([start_button, back_button])
	_vessel_screen = _screen(vessel_column)

	link_focus([sailing_button, quit_button] + duel_buttons.values())
	link_focus(vessel_buttons.values() + [start_button, back_button])
	sailing_button.pressed.connect(_show_vessels.bind("practice"))
	for preset_id in duel_buttons:
		duel_buttons[preset_id].pressed.connect(_show_vessels.bind(preset_id))
	quit_button.pressed.connect(quit_requested.emit)
	back_button.pressed.connect(show_mode_select)
	start_button.pressed.connect(func(): start_requested.emit(_chosen_preset, selected_vessel_id()))


func show_mode_select() -> void:
	_vessel_screen.hide()
	_mode_screen.show()
	sailing_button.grab_focus()


func selected_vessel_id() -> String:
	for id in vessel_buttons:
		if vessel_buttons[id].button_pressed:
			return id
	return "sloop"


func _show_vessels(preset_id: String) -> void:
	_chosen_preset = preset_id
	_mode_screen.hide()
	_vessel_screen.show()
	vessel_buttons[selected_vessel_id()].grab_focus()


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 48)
	return button


## Centered dark panel holding a vertical column.
func _screen(children: Array) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	for child in children:
		box.add_child(child)
	panel.add_child(box)
	center.add_child(panel)
	add_child(center)
	return center


## Explicit, wrapping Up/Down and Tab/Shift+Tab order for a vertical button list.
static func link_focus(buttons: Array) -> void:
	for i in buttons.size():
		var button: Control = buttons[i]
		var next: NodePath = button.get_path_to(buttons[(i + 1) % buttons.size()])
		var prev: NodePath = button.get_path_to(buttons[i - 1])
		button.focus_neighbor_bottom = next
		button.focus_next = next
		button.focus_neighbor_top = prev
		button.focus_previous = prev
		button.focus_neighbor_left = NodePath(".")
		button.focus_neighbor_right = NodePath(".")
