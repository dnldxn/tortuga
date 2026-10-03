extends RefCounted
## The remembered multiplayer settings (captain id, name, server address, password) in
## user://multiplayer.cfg. A field that fails its check falls back to its default; load never crashes.

const Protocol := preload("res://net/protocol.gd")
const PATH := "user://multiplayer.cfg"
const NAME_MAX := 16
const HOST_MAX := 253
const PASSWORD_MAX := 64
static var _ID_PATTERN := RegEx.create_from_string("^[0-9a-f]{32}$")
const MISSING := -1  # get_value default (null counts as none); fails every field check

var path: String
var values: Dictionary


func _init(config_path := PATH) -> void:
	path = config_path
	values = defaults()


static func defaults() -> Dictionary:
	return {"captain_id": "", "name": "Captain", "host": "", "port": Protocol.DEFAULT_PORT, "password": ""}


static func new_captain_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## Loads the file. False when anything was missing or replaced (the repaired file is then saved).
func load_config() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		cfg.clear()
	var loaded := defaults()
	var clean := true
	for field in [["captain_id", "captain", "id"], ["name", "captain", "name"], ["host", "server", "host"],
			["port", "server", "port"], ["password", "server", "password"]]:
		var value = cfg.get_value(field[1], field[2], MISSING)
		if field[0] == "name" and value is String:
			value = value.strip_edges()
		if _valid(field[0], value):
			loaded[field[0]] = value
		else:
			clean = false
			if field[0] == "captain_id":
				loaded[field[0]] = new_captain_id()
	values = loaded
	if not clean:
		save()
	return clean


func save() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("captain", "id", values["captain_id"])
	cfg.set_value("captain", "name", values["name"])
	cfg.set_value("server", "host", values["host"])
	cfg.set_value("server", "port", values["port"])
	cfg.set_value("server", "password", values["password"])
	return cfg.save(path)


## Updates host, port, name and password and saves; a failed check changes nothing.
func remember(host: String, port: int, name: String, password: String) -> Error:
	name = name.strip_edges()
	if not (_valid("host", host) and _valid("port", port) and _valid("name", name) and _valid("password", password)):
		return ERR_INVALID_PARAMETER
	values["host"] = host
	values["port"] = port
	values["name"] = name
	values["password"] = password
	return save()


static func _valid(field: String, value) -> bool:
	match field:
		"captain_id":
			return value is String and _ID_PATTERN.search(value) != null
		"name":
			return value is String and value.length() >= 1 and value.length() <= NAME_MAX
		"host":
			return value is String and value.length() <= HOST_MAX
		"port":
			return typeof(value) == TYPE_INT and value >= 1 and value <= 65535
		"password":
			return value is String and value.length() <= PASSWORD_MAX
	return false
