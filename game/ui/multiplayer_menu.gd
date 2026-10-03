extends Control
## Connect form (centered panel): server address, captain name and password. It only checks the
## fields and emits connect_requested; main owns the session and feeds back show_connecting/show_status.

signal connect_requested(host: String, port: int, name: String, password: String)
signal back_requested

const Protocol := preload("res://net/protocol.gd")
const Definitions := preload("res://sim/definitions.gd")
const MultiplayerConfig := preload("res://net/multiplayer_config.gd")
const UpdateService := preload("res://update/update_service.gd")
const SelectionMenu := preload("res://ui/selection_menu.gd")

const ENDED_TEXT := {"server_stopped": "Server stopped.", "connection_lost": "Connection lost.",
	"replaced": "Replaced by a newer connection."}
const ADDRESS_HINT := "Enter the server address as host or host:port (port 1–65535)."
const NAME_HINT := "Enter a captain name."

var address_edit: LineEdit
var name_edit: LineEdit
var password_edit: LineEdit
var status_label: Label
var connect_button: Button
var back_button: Button


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var title := Label.new()
	title.theme_type_variation = "NauticalHeading"
	title.text = "Multiplayer"
	address_edit = _edit("host or host:port")
	name_edit = _edit("Captain")
	name_edit.max_length = MultiplayerConfig.NAME_MAX
	password_edit = _edit("")
	password_edit.secret = true
	password_edit.max_length = MultiplayerConfig.PASSWORD_MAX
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(480, 0)
	connect_button = _button("Connect")
	back_button = _button("Back")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	for child in [title, _caption("Server address"), address_edit, _caption("Captain name"), name_edit,
			_caption("Password"), password_edit, status_label, connect_button, back_button]:
		box.add_child(child)
	var panel := PanelContainer.new()
	panel.add_child(box)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.add_child(panel)
	add_child(center)
	SelectionMenu.link_focus([address_edit, name_edit, password_edit, connect_button, back_button])
	for edit in [address_edit, name_edit, password_edit]:
		edit.text_submitted.connect(func(_text): _on_connect())
	connect_button.pressed.connect(_on_connect)
	back_button.pressed.connect(back_requested.emit)


## Fills and enables the form from MultiplayerConfig values; clears the status.
func show_form(values: Dictionary) -> void:
	var host: String = values.get("host", "")
	var port: int = values.get("port", Protocol.DEFAULT_PORT)
	address_edit.text = "" if host == "" else ("%s:%d" % [host, port] if port != Protocol.DEFAULT_PORT else host)
	name_edit.text = values.get("name", "")
	password_edit.text = values.get("password", "")
	show_status("")
	(address_edit if host == "" else connect_button).grab_focus()


## The form is disabled while connecting; Back stays available to cancel.
func show_connecting(host: String, port: int) -> void:
	_set_form_enabled(false)
	status_label.text = "Connecting to %s:%d…" % [host, port]
	back_button.grab_focus()


## Re-enables the form with a status line (empty clears it).
func show_status(text: String) -> void:
	_set_form_enabled(true)
	status_label.text = text
	connect_button.grab_focus()


## Stripped "host" or "host:port" (one ':', port 1..65535) -> {host, port}; anything else -> {}.
static func parse_address(text: String, default_port: int) -> Dictionary:
	var parts := text.strip_edges().split(":")
	if parts.size() > 2 or parts[0] == "":
		return {}
	if parts.size() == 1:
		return {"host": parts[0], "port": default_port}
	if not parts[1].is_valid_int() or parts[1].to_int() < 1 or parts[1].to_int() > 65535:
		return {}
	return {"host": parts[0], "port": parts[1].to_int()}


static func refusal_text(reason: String, client_version: String, server_version: String) -> String:
	match reason:
		"version_mismatch":
			var advice := "Both must run the same build."
			if client_version != "dev" and server_version != "dev":
				if UpdateService.is_newer(server_version, client_version):
					advice = "Update your game: Check for updates on the main menu."
				elif UpdateService.is_newer(client_version, server_version):
					advice = "The server host must update the server."
			return "Version mismatch: you have %s, the server has %s. %s" % [
				_version_text(client_version), _version_text(server_version), advice]
		"wrong_password":
			return "Wrong password."
		"server_full":
			return "Server full: %d captains are already connected." % Definitions.MAX_CAPTAINS
	return "Connection refused (%s)." % reason


static func _version_text(version: String) -> String:
	return "a development build" if version == "dev" else "v" + version


func _on_connect() -> void:
	if connect_button.disabled:
		return
	var address := parse_address(address_edit.text, Protocol.DEFAULT_PORT)
	if address.is_empty():
		status_label.text = ADDRESS_HINT
	elif name_edit.text.strip_edges() == "":
		status_label.text = NAME_HINT
	else:
		connect_requested.emit(address["host"], address["port"], name_edit.text, password_edit.text)


func _set_form_enabled(enabled: bool) -> void:
	for edit in [address_edit, name_edit, password_edit]:
		edit.editable = enabled
	connect_button.disabled = not enabled


func _edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(480, 44)
	return edit


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(480, 48)
	return button
