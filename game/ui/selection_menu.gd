extends Control
## Mode select (Target practice / Quit) -> vessel select (vessels / Start / Back).

signal start_requested(vessel_id: String)
signal quit_requested

const Definitions := preload("res://sim/definitions.gd")

var sailing_button: Button
var quit_button: Button
var start_button: Button
var back_button: Button
var vessel_buttons := {}  # vessel_id -> toggle Button

var _mode_screen: Control
var _vessel_screen: Control


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var title := Label.new()
	title.text = "Tortuga"
	title.add_theme_font_size_override("font_size", 48)
	sailing_button = _button("Target practice")
	quit_button = _button("Quit")
	_mode_screen = _screen([title, sailing_button, quit_button])

	var heading := Label.new()
	heading.text = "Choose your vessel"
	var group := ButtonGroup.new()
	var column := [heading]
	for id in Definitions.VESSELS:
		var vessel: Dictionary = Definitions.VESSELS[id]
		var button := _button("%s — %s" % [vessel["display_name"], vessel["description"]])
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		vessel_buttons[id] = button
		column.append(button)
	vessel_buttons["sloop"].button_pressed = true
	start_button = _button("Start")
	back_button = _button("Back")
	column.append_array([start_button, back_button])
	_vessel_screen = _screen(column)

	link_focus([sailing_button, quit_button])
	link_focus(vessel_buttons.values() + [start_button, back_button])
	sailing_button.pressed.connect(_show_vessels)
	quit_button.pressed.connect(quit_requested.emit)
	back_button.pressed.connect(show_mode_select)
	start_button.pressed.connect(func(): start_requested.emit(selected_vessel_id()))


func show_mode_select() -> void:
	_vessel_screen.hide()
	_mode_screen.show()
	sailing_button.grab_focus()


func selected_vessel_id() -> String:
	for id in vessel_buttons:
		if vessel_buttons[id].button_pressed:
			return id
	return "sloop"


func _show_vessels() -> void:
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
