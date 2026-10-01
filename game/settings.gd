extends RefCounted
## Player settings model: key bindings, bus volumes and window mode, persisted to one ConfigFile.
## Owned by main. No I/O in the constructor; `values` always holds a complete valid map.
## load_settings() only replaces `values` (no native side effects); apply_values() is the one
## place that touches InputMap, AudioServer and the window.

signal changed

const Bindings := preload("res://input_bindings.gd")

const PATH := "user://settings.cfg"
const LOAD_NOTICE := "Settings could not be loaded; defaults are active."
const MODES := ["windowed", "fullscreen"]
## Settings channel -> AudioServer bus name (see res://default_bus_layout.tres).
const BUSES := {"master": "Master", "effects": "Effects", "ambient": "Ambient"}
const WINDOW_SIZE := Vector2i(1280, 720)

var values: Dictionary
var notice := ""


func _init() -> void:
	values = defaults()


## Fresh deep copy of the defaults every call.
func defaults() -> Dictionary:
	return {
		"version": 1,
		"bindings": Bindings.default_keycodes(),
		"audio": {"master": 1.0, "effects": 0.8, "ambient": 0.35},
		"display_mode": "windowed",
	}


## Strict schema: exactly these keys, version int 1, a complete unique supported key map,
## three finite volumes in [0, 1] and a known window mode.
func validate(candidate: Dictionary) -> bool:
	if candidate.size() != 4 or not candidate.has_all(["version", "bindings", "audio", "display_mode"]):
		return false
	if typeof(candidate["version"]) != TYPE_INT or candidate["version"] != 1:
		return false
	if not Bindings.valid_keycodes(candidate["bindings"]):
		return false
	var audio = candidate["audio"]
	if typeof(audio) != TYPE_DICTIONARY or audio.size() != BUSES.size():
		return false
	for channel in BUSES:
		if not audio.has(channel) or not valid_volume(audio[channel]):
			return false
	return typeof(candidate["display_mode"]) == TYPE_STRING and candidate["display_mode"] in MODES


func valid_volume(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and value >= 0.0 and value <= 1.0


## Replaces `values` with the complete file, or with all defaults. A missing file is a silent
## first launch (ERR_FILE_NOT_FOUND); anything else that fails sets `notice` and returns the
## ConfigFile error or ERR_INVALID_DATA. Never rewrites the file.
func load_settings(path := PATH) -> Error:
	notice = ""
	var config := ConfigFile.new()
	var err := config.load(path)
	if err == OK:
		var candidate := _read(config)
		if validate(candidate):
			values = candidate
			return OK
		err = ERR_INVALID_DATA
	values = defaults()
	if err != ERR_FILE_NOT_FOUND:
		notice = LOAD_NOTICE
	return err


## Writes only schema fields; extra data is dropped. Does not touch `values` or the runtime.
func save_values(candidate: Dictionary, path := PATH) -> Error:
	if not validate(candidate):
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	for action in Bindings.default_keycodes():
		config.set_value("bindings", action, candidate["bindings"][action])
	for channel in BUSES:
		config.set_value("audio", channel, float(candidate["audio"][channel]))
	config.set_value("display", "mode", candidate["display_mode"])
	return config.save(path)


## Validated deep copy -> InputMap, bus gains, window (not headless) -> `values` -> `changed`.
func apply_values(candidate: Dictionary) -> void:
	if not validate(candidate):
		push_error("Invalid settings; not applied")
		return
	var copy := candidate.duplicate(true)
	Bindings.apply_keycodes(copy["bindings"])
	for channel in BUSES:
		var index := AudioServer.get_bus_index(BUSES[channel])
		if index < 0:
			push_error("Missing audio bus: " + BUSES[channel])
			continue
		var gain := float(copy["audio"][channel])
		AudioServer.set_bus_mute(index, gain == 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(gain, 0.0001)))
	if DisplayServer.get_name() != "headless":
		var fullscreen: bool = copy["display_mode"] == "fullscreen"
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		if not fullscreen:
			DisplayServer.window_set_size(WINDOW_SIZE)
	values = copy
	changed.emit()


## Primitive schema fields only (null when missing); extra sections/keys are ignored.
## Integer volumes become floats so a loaded file compares equal to what was saved.
func _read(config: ConfigFile) -> Dictionary:
	var bindings := {}
	for action in Bindings.default_keycodes():
		bindings[action] = _value(config, "bindings", action)
	var audio := {}
	for channel in BUSES:
		var gain = _value(config, "audio", channel)
		audio[channel] = float(gain) if typeof(gain) == TYPE_INT else gain
	return {
		"version": _value(config, "meta", "version"),
		"bindings": bindings,
		"audio": audio,
		"display_mode": _value(config, "display", "mode"),
	}


## get_value(..., null) still logs an engine error for a missing key; check first.
func _value(config: ConfigFile, section: String, key: String) -> Variant:
	return config.get_value(section, key, null) if config.has_section_key(section, key) else null
