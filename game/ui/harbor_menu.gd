extends Control
## Harbor (centered panel): the server's battles with Join / Reclaim / Closed, the connected
## captains, Start and Disconnect; plus a picker (preset + vessel for Start, vessel only for Join).
## It only displays what main feeds it (show_harbor / show_notice) and emits requests; after a
## request every action waits until main calls set_waiting(false) or reopens it.

signal start_requested(preset_id: String, vessel_id: String)
signal join_requested(battle_id: int, vessel_id: String)
signal disconnect_requested

const Definitions := preload("res://sim/definitions.gd")
const SelectionMenu := preload("res://ui/selection_menu.gd")

const WIDTH := 640.0

var battle_rows: Array = []  # [{"battle_id", "label", "button"}] in server order
var captains_label: Label
var notice_label: Label  # hidden when empty
var start_button: Button
var disconnect_button: Button
var preset_buttons := {}  # preset id -> toggle Button, in Definitions.BATTLE_PRESETS order
var vessel_buttons := {}  # vessel id -> toggle Button
var confirm_button: Button
var back_button: Button
var waiting := false  # a start/join request is out and unanswered

var _harbor_screen: Control
var _picker_screen: Control
var _battle_list: VBoxContainer
var _empty_label: Label
var _picker_title: Label
var _preset_section: Array = []  # controls shown only when picking a preset (Start)
var _join_id := 0  # battle the picker joins; 0 = the picker starts a battle
var _can_start := true


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var title := _heading("Harbor")
	captains_label = Label.new()
	_battle_list = VBoxContainer.new()
	_battle_list.add_theme_constant_override("separation", 8)
	_empty_label = Label.new()
	_empty_label.text = "No battles at sea. Start one!"
	notice_label = Label.new()
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.custom_minimum_size = Vector2(WIDTH, 0)
	notice_label.hide()
	start_button = _button("Start a battle", 0)
	disconnect_button = _button("Disconnect", 0)
	for button in [start_button, disconnect_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_harbor_screen = _screen([title, captains_label, _caption("Battles"), _empty_label, _battle_list, notice_label,
			_row([start_button, disconnect_button])])

	_picker_title = _heading("")
	var preset_caption := _caption("Battle")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var presets := ButtonGroup.new()
	for id in Definitions.BATTLE_PRESETS:
		var button := _button(Definitions.PRESETS[id]["label"], (WIDTH - 8) / 2)
		button.toggle_mode = true
		button.button_group = presets
		preset_buttons[id] = button
		grid.add_child(button)
	preset_buttons[Definitions.BATTLE_PRESETS[0]].button_pressed = true
	_preset_section = [preset_caption, grid]
	var vessels := ButtonGroup.new()
	var vessel_column: Array = [_caption("Vessel")]
	for id in Definitions.VESSELS:
		var vessel: Dictionary = Definitions.VESSELS[id]
		var button := _button("%s — %s" % [vessel["display_name"], vessel["description"]])
		button.toggle_mode = true
		button.button_group = vessels
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		vessel_buttons[id] = button
		vessel_column.append(button)
	vessel_buttons["sloop"].button_pressed = true
	confirm_button = _button("Set sail", 0)
	back_button = _button("Back", 0)
	for button in [confirm_button, back_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_screen = _screen([_picker_title, preset_caption, grid] + vessel_column + [_row([confirm_button, back_button])])
	_picker_screen.hide()

	start_button.pressed.connect(_open_picker.bind(0))
	disconnect_button.pressed.connect(disconnect_requested.emit)
	confirm_button.pressed.connect(_on_confirm)
	back_button.pressed.connect(show_harbor_screen)
	_link_harbor_focus()


## Back to the harbor list with every action enabled (entering the harbor mode).
func open() -> void:
	waiting = false
	show_notice("")
	show_harbor_screen()


func show_harbor_screen() -> void:
	_picker_screen.hide()
	_harbor_screen.show()
	_apply_enabled()
	_focus_first()


## Rebuilds the battle rows and the captain list from a server "harbor" message.
func show_harbor(harbor: Dictionary) -> void:
	var focused_index := -1
	for i in battle_rows.size():
		if battle_rows[i]["button"].has_focus():
			focused_index = i
	for row in battle_rows:
		var line: Control = row["button"].get_parent()
		_battle_list.remove_child(line)
		line.queue_free()
	battle_rows = []
	var labels := {}
	for b in harbor.get("battles", []):
		labels[b["battle_id"]] = b["label"]
		var label := Label.new()
		label.text = battle_line(b)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(WIDTH - 148, 0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button := _button("Join", 140)
		if b["lingering_here"]:
			button.text = "Reclaim"
			button.pressed.connect(_request_join.bind(b["battle_id"], ""))
		elif b["can_join"]:
			button.pressed.connect(_open_picker.bind(b["battle_id"]))
		else:
			button.text = "Closed"
		button.set_meta("open", b["lingering_here"] or b["can_join"])
		_battle_list.add_child(_row([label, button]))
		battle_rows.append({"battle_id": b["battle_id"], "label": label, "button": button})
	_empty_label.visible = battle_rows.is_empty()
	var lines := []
	for c in harbor.get("captains", []):
		lines.append("●%d %s (%s)" % [c["slot"] + 1, c["name"], labels.get(c["battle_id"], "harbor")])
	captains_label.text = "\n".join(lines)
	_can_start = harbor.get("can_start", true)
	_apply_enabled()
	_link_harbor_focus()
	if focused_index >= 0 and _harbor_screen.visible:
		_focus_first(focused_index)


func show_notice(text: String) -> void:
	notice_label.text = text
	notice_label.visible = text != ""


func set_waiting(value: bool) -> void:
	waiting = value
	_apply_enabled()


## "Brig duel · Anne, Bob · 1 AI left · 3:05"
static func battle_line(b: Dictionary) -> String:
	var names: Array = b.get("captains", [])
	var seconds := int(b.get("elapsed", 0.0))
	return "%s · %s · %d AI left · %d:%02d" % [b["label"], ", ".join(PackedStringArray(names)) if not names.is_empty()
		else "no captains", b.get("ai_left", 0), seconds / 60, seconds % 60]


static func refused_text(reason: String) -> String:
	match reason:
		"battle_cap":
			return "The harbor is busy: %d battles are already at sea." % Definitions.MAX_BATTLES
		"no_reentry":
			return "Your ship is out of that battle and cannot rejoin it."
		"unknown_battle":
			return "That battle has already ended."
		"already_in_battle":
			return "Your ship is already sailing in that battle."
	return "Request refused (%s)." % reason


## Harbor notice for an own outcome that returns the captain to (or reaches them in) the harbor.
static func outcome_notice(outcome: String) -> String:
	match outcome:
		"escaped":
			return "Escaped — you broke pursuit."
		"abandoned":
			return "Your ship was abandoned."
	return ""


func _open_picker(battle_id: int) -> void:
	if waiting:
		return
	_join_id = battle_id
	_picker_title.text = "Choose your battle and vessel" if battle_id == 0 else "Choose your vessel"
	for control in _preset_section:
		control.visible = battle_id == 0
	_harbor_screen.hide()
	_picker_screen.show()
	confirm_button.disabled = false
	var first: Button = preset_buttons.values().filter(func(b): return b.button_pressed)[0] if battle_id == 0 \
		else vessel_buttons[_selected(vessel_buttons, "sloop")]
	first.grab_focus()
	var chain: Array = (preset_buttons.values() if battle_id == 0 else []) + vessel_buttons.values() + [confirm_button, back_button]
	SelectionMenu.link_focus(chain)


func _on_confirm() -> void:
	if waiting:
		return
	var vessel := _selected(vessel_buttons, "sloop")
	if _join_id == 0:
		set_waiting(true)
		start_requested.emit(_selected(preset_buttons, Definitions.BATTLE_PRESETS[0]), vessel)
	else:
		_request_join(_join_id, vessel)
	show_harbor_screen()


func _request_join(battle_id: int, vessel_id: String) -> void:
	if waiting:
		return
	set_waiting(true)
	join_requested.emit(battle_id, vessel_id)


func _apply_enabled() -> void:
	for row in battle_rows:
		row["button"].disabled = waiting or not row["button"].get_meta("open")
	start_button.disabled = waiting or not _can_start
	confirm_button.disabled = waiting


func _link_harbor_focus() -> void:
	SelectionMenu.link_focus(battle_rows.map(func(r): return r["button"]) + [start_button, disconnect_button])


## Focuses the given row's button, else the first enabled battle button, Start or Disconnect.
func _focus_first(index := -1) -> void:
	var buttons: Array = battle_rows.map(func(r): return r["button"])
	if index >= 0 and index < buttons.size():
		buttons[index].grab_focus()
		return
	for button in buttons + [start_button]:
		if not button.disabled:
			button.grab_focus()
			return
	disconnect_button.grab_focus()


static func _selected(buttons: Dictionary, fallback: String) -> String:
	for id in buttons:
		if buttons[id].button_pressed:
			return id
	return fallback


func _heading(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = "NauticalHeading"
	label.text = text
	return label


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(.98, .87, .59))
	return label


func _button(text: String, min_width := WIDTH) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 48)
	return button


func _row(children: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for child in children:
		row.add_child(child)
	return row


## Centered dark panel holding a vertical column.
func _screen(children: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	for child in children:
		box.add_child(child)
	var panel := PanelContainer.new()
	panel.add_child(box)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.add_child(panel)
	add_child(center)
	return center
