extends Control
## Mode select (practice / duels / two sloops / Multiplayer / Settings + Quit, plus the version and update
## controls) -> vessel select. start_requested carries the chosen preset id and vessel id.
## The update controls only display what main feeds them (show_version / show_update_state).

signal start_requested(preset_id: String, vessel_id: String)
signal multiplayer_requested
signal quit_requested
signal settings_requested
signal check_updates_requested
signal update_requested
signal full_download_requested

const Definitions := preload("res://sim/definitions.gd")

const MODES := [
	["practice", "Target practice"],
	["duel_sloop", "Sloop duel"],
	["duel_brig", "Brig duel"],
	["duel_frigate", "Frigate duel"],
	["two_sloops", "Two-ship encounter — two sloops"],
]
const GUIDANCE := "Sink the enemy, or exhaust its sails or crew. Turn a broadside toward it to fire. Good hunting!"

var sailing_button: Button
var duel_buttons := {}  # preset id -> Button
var multiplayer_button: Button
var settings_button: Button
var quit_button: Button
var notice_label: Label
var version_label: Label
var update_status_label: Label  # hidden when empty
var check_updates_button: Button
var update_button: Button
var full_download_button: Button
var start_button: Button
var back_button: Button
var vessel_buttons := {}  # vessel_id -> toggle Button

var _mode_screen: Control
var _vessel_screen: Control
var _chosen_preset := "practice"


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var title := Label.new()
	title.theme_type_variation = "NauticalHeading"
	title.text = "Tortuga"
	title.add_theme_font_size_override("font_size", 48)
	var column := [title]
	sailing_button = _button("Target practice")
	column.append(sailing_button)
	duel_buttons["duel_sloop"] = _button("Sloop duel")
	duel_buttons["duel_brig"] = _button("Brig duel")
	duel_buttons["duel_frigate"] = _button("Frigate duel")
	duel_buttons["two_sloops"] = _button("Two-ship encounter — two sloops")
	column.append_array([duel_buttons["duel_sloop"], duel_buttons["duel_brig"], duel_buttons["duel_frigate"], duel_buttons["two_sloops"]])
	multiplayer_button = _button("Multiplayer")
	column.append(multiplayer_button)
	var guidance := Label.new()
	guidance.text = GUIDANCE
	guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guidance.custom_minimum_size = Vector2(420, 0)
	column.append(guidance)
	notice_label = Label.new()  # settings load-fallback notice; hidden when empty
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.custom_minimum_size = Vector2(420, 0)
	notice_label.hide()
	column.append(notice_label)
	# Settings and Quit share a row so the Multiplayer button keeps the panel within 720 px.
	settings_button = _button("Settings", 0)
	quit_button = _button("Quit", 0)
	for button in [settings_button, quit_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.append(_row([settings_button, quit_button]))
	# Two compact rows so the update block never pushes a button off a 720 px screen.
	version_label = Label.new()
	update_status_label = Label.new()
	update_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	update_status_label.custom_minimum_size = Vector2(276, 0)  # widest status text; with "Tortuga 0.123" fills 420
	update_status_label.hide()
	check_updates_button = _button("Check for updates", 0)
	update_button = _button("Update and Restart", 0)
	update_button.hide()
	full_download_button = _button("Download full update", 0)
	full_download_button.hide()
	for button in [check_updates_button, update_button, full_download_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.append_array([_row([version_label, update_status_label]),
			_row([check_updates_button, update_button, full_download_button])])
	_mode_screen = _screen(column)

	var heading := Label.new()
	heading.theme_type_variation = "NauticalHeading"
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

	link_focus([sailing_button] + duel_buttons.values() + [multiplayer_button, settings_button, quit_button,
			check_updates_button, update_button, full_download_button])
	link_focus(vessel_buttons.values() + [start_button, back_button])
	sailing_button.pressed.connect(_show_vessels.bind("practice"))
	for preset_id in duel_buttons:
		duel_buttons[preset_id].pressed.connect(_show_vessels.bind(preset_id))
	multiplayer_button.pressed.connect(multiplayer_requested.emit)
	settings_button.pressed.connect(settings_requested.emit)
	quit_button.pressed.connect(quit_requested.emit)
	check_updates_button.pressed.connect(check_updates_requested.emit)
	update_button.pressed.connect(update_requested.emit)
	full_download_button.pressed.connect(full_download_requested.emit)
	back_button.pressed.connect(show_mode_select)
	start_button.pressed.connect(func(): start_requested.emit(_chosen_preset, selected_vessel_id()))


func show_mode_select() -> void:
	_vessel_screen.hide()
	_mode_screen.show()
	sailing_button.grab_focus()


func show_notice(text: String) -> void:
	notice_label.text = text
	notice_label.visible = text != ""


func show_version(version: String) -> void:
	version_label.text = "Development build" if version == "dev" else "Tortuga %s" % version


## Mirrors an update_service state: status text, which update buttons show, and what is locked.
## A download locks every way into a battle (and Settings); Quit stays available.
func show_update_state(state: String, detail: String) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var text := ""
	match state:
		"checking":
			text = "Checking for updates…"
		"downloading":
			text = "Downloading update… %s%%" % detail
		"available", "full_download":
			text = "Version %s is available." % detail
		"up_to_date":
			text = "You're up to date."
		"error":
			text = detail
	update_status_label.text = text
	update_status_label.visible = text != ""
	var downloading := state == "downloading"
	check_updates_button.disabled = state in ["disabled", "checking", "downloading"]
	update_button.visible = state in ["available", "downloading"]
	update_button.disabled = downloading
	full_download_button.visible = state == "full_download"
	for button in [sailing_button, multiplayer_button, settings_button] + duel_buttons.values():
		button.disabled = downloading
	if focused in [update_button, full_download_button] and not focused.visible:
		check_updates_button.grab_focus()  # don't strand keyboard focus on a hidden button


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


func _button(text: String, min_width := 420.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 48)
	return button


func _row(children: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for child in children:
		row.add_child(child)
	return row


## Centered dark panel holding a vertical column.
func _screen(children: Array) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(680, 640)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	for child in children:
		box.add_child(child)
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(box)
	panel.add_child(scroll)
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
