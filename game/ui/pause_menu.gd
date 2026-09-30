extends Control
## Pause overlay: Resume / Restart practice / Return to selection.

signal resume_requested
signal restart_requested
signal return_requested

const SelectionMenu := preload("res://ui/selection_menu.gd")

var resume_button: Button
var restart_button: Button
var return_button: Button


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
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	resume_button = _button(box, "Resume", resume_requested)
	restart_button = _button(box, "Restart practice", restart_requested)
	return_button = _button(box, "Return to selection", return_requested)
	panel.add_child(box)
	center.add_child(panel)
	add_child(center)
	SelectionMenu.link_focus([resume_button, restart_button, return_button])


func _button(parent: Node, text: String, request: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 48)
	button.pressed.connect(request.emit)
	parent.add_child(button)
	return button
