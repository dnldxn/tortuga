extends Control
## Shared-battle menu: Resume / Settings / Help / Leave battle over a light dim. It never pauses:
## the battle keeps running (and stays visible) behind it. After the own ship sinks or is disabled it
## also holds the defeat panel (Watch allies / Return to harbor), shown whenever the menu is closed.

signal resume_requested
signal settings_requested
signal leave_requested
signal watch_requested
signal harbor_requested

const SelectionMenu := preload("res://ui/selection_menu.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")

const LEAVE_HINT := "A ship you leave stays afloat for 30 s: Reclaim it from the harbor before it is abandoned."

var menu_open := false
var defeat_open := false
var resume_button: Button
var settings_button: Button
var help_button: Button
var leave_button: Button
var help_panel: PanelContainer
var help_label: Label
var defeat_panel: PanelContainer
var defeat_title: Label
var watch_button: Button
var harbor_button: Button
var _menu_row: Control


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.2)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)  # also blocks clicks from reaching the HUD
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)
	_menu_row = CenterContainer.new()
	column.add_child(_menu_row)
	var panel := PanelContainer.new()
	_menu_row.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.theme_type_variation = "NauticalHeading"
	title.text = "Battle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	resume_button = _button(box, "Resume")
	resume_button.pressed.connect(resume_requested.emit)
	settings_button = _button(box, "Settings")
	settings_button.pressed.connect(settings_requested.emit)
	help_button = _button(box, "Help")
	help_button.pressed.connect(func() -> void: help_panel.visible = not help_panel.visible)
	leave_button = _button(box, "Leave battle")
	leave_button.pressed.connect(leave_requested.emit)
	help_panel = PanelContainer.new()
	help_panel.visible = false
	column.add_child(help_panel)
	help_label = Label.new()
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.custom_minimum_size.x = 900
	help_panel.add_child(help_label)
	SelectionMenu.link_focus([resume_button, settings_button, help_button, leave_button])
	var defeat_row := CenterContainer.new()
	column.add_child(defeat_row)
	defeat_panel = PanelContainer.new()
	defeat_panel.visible = false
	defeat_row.add_child(defeat_panel)
	var defeat_box := VBoxContainer.new()
	defeat_box.add_theme_constant_override("separation", 12)
	defeat_panel.add_child(defeat_box)
	defeat_title = Label.new()
	defeat_title.theme_type_variation = "NauticalHeading"
	defeat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	defeat_box.add_child(defeat_title)
	watch_button = _button(defeat_box, "Watch allies")
	watch_button.pressed.connect(watch_requested.emit)
	harbor_button = _button(defeat_box, "Return to harbor")
	harbor_button.pressed.connect(harbor_requested.emit)
	SelectionMenu.link_focus([watch_button, harbor_button])


## Opens with Resume focused; help text follows the encounter and the live bindings.
func open_menu(preset_id: String) -> void:
	refresh_help(preset_id)
	help_panel.visible = false
	menu_open = true
	_sync()
	resume_button.grab_focus()


## Closing the menu brings back an open defeat panel (focused).
func close_menu() -> void:
	menu_open = false
	_sync()
	if defeat_open:
		_focus_defeat()


## "Sunk" / "Disabled"; Watch allies needs at least one ally still afloat.
func show_defeat(outcome: String, can_watch: bool) -> void:
	defeat_title.text = outcome.capitalize()
	watch_button.disabled = not can_watch
	defeat_open = true
	_sync()
	if not menu_open:
		_focus_defeat()


func hide_defeat() -> void:
	defeat_open = false
	_sync()


func refresh_help(preset_id: String) -> void:
	help_label.text = "%s\n%s\n%s" % [PauseMenu.guidance_text(preset_id), PauseMenu.bindings_text(false), LEAVE_HINT]


func _sync() -> void:
	visible = menu_open or defeat_open
	_menu_row.visible = menu_open
	if not menu_open:
		help_panel.visible = false
	defeat_panel.visible = defeat_open and not menu_open


func _focus_defeat() -> void:
	(harbor_button if watch_button.disabled else watch_button).grab_focus()


func _button(parent: Node, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 48)
	parent.add_child(button)
	return button
