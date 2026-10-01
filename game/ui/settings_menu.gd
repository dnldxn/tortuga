extends Control
## Settings overlay: eight key bindings, three bus volumes and the window mode, edited as a
## draft. Only Apply saves and applies; Back discards. While open, main.gd routes every input
## event through handle_capture() first, so captured keys never reach gameplay or GUI focus.

signal closed

const Bindings := preload("res://input_bindings.gd")
const Settings := preload("res://settings.gd")
const SelectionMenu := preload("res://ui/selection_menu.gd")

const DEFAULTS_READY := "Defaults ready — Apply to save"
const SAVED := "Settings saved"
const SAVE_FAILED := "Could not save settings. Changes were not applied; retry Apply."
const CAPTURE_PROMPT := "Press a key for %s. Escape cancels."
const MODE_NAMES := ["Windowed", "Fullscreen"]  # parallel to Settings.MODES
const MODIFIERS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

var settings  # the model being edited (main.settings)
var draft: Dictionary
var capturing_action := ""
var waiting_for_activation_release := false

var binding_buttons := {}  # action -> Button
var sliders := {}  # channel -> HSlider
var percent_labels := {}  # channel -> Label
var mode_option: OptionButton
var scroll: ScrollContainer
var status_label: Label
var defaults_button: Button
var apply_button: Button
var back_button: Button

var _down := {}  # keycodes seen pressed and not yet released while open
var _activation_keys := {}  # keys held when capture began; capture waits for their release


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)  # blocks clicks to whatever is underneath
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# Fixed height so the footer always fits 720p; focused rows scroll into view.
	scroll = ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(600, 400)
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var order := []
	for action in Bindings.ACTION_NAMES:
		var button := _button(rows)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.pressed.connect(begin_capture.bind(action))
		binding_buttons[action] = button
		order.append(button)
	for channel in Settings.BUSES:
		var row := _row(rows, Settings.BUSES[channel])
		var slider := HSlider.new()
		slider.max_value = 100
		slider.step = 1
		slider.size_flags_horizontal = SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(0, 36)
		slider.value_changed.connect(_on_volume.bind(channel))
		row.add_child(slider)
		var percent := Label.new()
		percent.custom_minimum_size = Vector2(64, 0)
		percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(percent)
		sliders[channel] = slider
		percent_labels[channel] = percent
		order.append(slider)
	mode_option = OptionButton.new()
	for mode_name in MODE_NAMES:
		mode_option.add_item(mode_name)
	mode_option.custom_minimum_size = Vector2(0, 40)
	mode_option.size_flags_horizontal = SIZE_EXPAND_FILL
	mode_option.item_selected.connect(func(index: int): draft["display_mode"] = Settings.MODES[index])
	_row(rows, "Display").add_child(mode_option)
	order.append(mode_option)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(600, 56)
	box.add_child(status_label)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)
	defaults_button = _button(footer, "Defaults", Vector2(180, 48))
	apply_button = _button(footer, "Apply", Vector2(180, 48))
	back_button = _button(footer, "Back", Vector2(180, 48))
	defaults_button.pressed.connect(reset_draft)
	apply_button.pressed.connect(apply_draft)
	back_button.pressed.connect(back)
	SelectionMenu.link_focus(order + [defaults_button, apply_button, back_button])
	hide()


## Window focus loss (called by main): cancel capture without committing or closing.
func release_all() -> void:
	_down.clear()
	cancel_capture()


## Draft = deep copy of the active values; a pending load-fallback notice is shown.
func open(model) -> void:
	settings = model
	draft = model.values.duplicate(true)
	capturing_action = ""
	waiting_for_activation_release = false
	_down.clear()
	_refresh()
	status_label.text = model.notice
	show()
	binding_buttons[Bindings.ACTION_NAMES.keys()[0]].grab_focus()


func begin_capture(action: String) -> void:
	cancel_capture()
	capturing_action = action
	# Opened by Enter/Space: wait for that key's release so it never binds itself.
	_activation_keys = _down.duplicate()
	waiting_for_activation_release = not _activation_keys.is_empty()
	binding_buttons[action].text = "%s — press a key… (click to cancel)" % Bindings.ACTION_NAMES[action]
	status_label.text = CAPTURE_PROMPT % Bindings.ACTION_NAMES[action]


func cancel_capture() -> void:
	if capturing_action == "":
		return
	var action := capturing_action
	capturing_action = ""
	waiting_for_activation_release = false
	_activation_keys.clear()
	_refresh_row(action)
	status_label.text = ""


## Called by main for every event while open. Returns true when the event was consumed.
## Validation/assignment read only the logical `keycode` (physical_keycode is ignored).
func handle_capture(event: InputEvent) -> bool:
	if event is InputEventKey:
		if event.pressed:
			_down[event.keycode] = true
		else:
			_down.erase(event.keycode)
	if capturing_action == "":
		return false
	if event is InputEventMouseButton:
		if not event.pressed:
			return false
		# A click on the capturing row is its Cancel; any other click cancels, then acts.
		var on_row: bool = binding_buttons[capturing_action].get_global_rect().has_point(event.position)
		cancel_capture()
		return on_row
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# Swallowed so a gamepad ui_accept can't re-activate the row; bindings are keyboard-only.
		if event is InputEventJoypadButton and event.pressed:
			status_label.text = Bindings.UNSUPPORTED_MESSAGE
		return true
	if not event is InputEventKey:
		return false
	var code: int = event.keycode
	if event.pressed and not event.echo and code == KEY_ESCAPE:
		cancel_capture()
		return true
	if waiting_for_activation_release:
		if not event.pressed:
			_activation_keys.erase(code)
			waiting_for_activation_release = not _activation_keys.is_empty()
		return true
	if not event.pressed or event.echo or code in MODIFIERS:
		return true  # keep listening
	if event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		status_label.text = Bindings.SINGLE_KEY_MESSAGE
		return true
	var problem := Bindings.binding_problem(capturing_action, code, draft["bindings"])
	if problem != "":
		status_label.text = problem
		return true
	var action := capturing_action
	draft["bindings"][action] = code
	cancel_capture()
	status_label.text = "%s: %s — Apply to save" % [Bindings.ACTION_NAMES[action], Bindings.key_label(code)]
	return true


func reset_draft() -> void:
	cancel_capture()
	draft = settings.defaults()
	_refresh()
	status_label.text = DEFAULTS_READY


## Save first; only a saved draft is applied. Stays open either way.
func apply_draft() -> void:
	cancel_capture()
	if settings.save_values(draft) != OK:
		status_label.text = SAVE_FAILED
		return
	settings.notice = ""  # the file is now good
	settings.apply_values(draft)
	draft = settings.values.duplicate(true)
	_refresh()
	status_label.text = SAVED


## Discards the draft.
func back() -> void:
	cancel_capture()
	hide()
	closed.emit()


func _on_volume(value: float, channel: String) -> void:
	draft["audio"][channel] = value / 100.0
	percent_labels[channel].text = "%d%%" % roundi(value)


func _refresh() -> void:
	for action in binding_buttons:
		_refresh_row(action)
	for channel in sliders:
		var percent := roundi(draft["audio"][channel] * 100.0)
		sliders[channel].set_value_no_signal(percent)
		percent_labels[channel].text = "%d%%" % percent
	mode_option.select(Settings.MODES.find(draft["display_mode"]))


func _refresh_row(action: String) -> void:
	binding_buttons[action].text = "%s — %s" % [Bindings.ACTION_NAMES[action], Bindings.key_label(draft["bindings"][action])]


func _row(parent: Node, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	parent.add_child(row)
	return row


func _button(parent: Node, text := "", size := Vector2(0, 40)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	parent.add_child(button)
	return button
