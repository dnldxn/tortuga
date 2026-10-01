extends SceneTree
## Cross-process settings persistence probe: one mode per Godot process, all sharing the
## wrapper's isolated profile. Run only from run_settings_checks.sh, in this order:
## write, read, corrupt, fallback, restore, read-defaults. Exit 0 = every check passed.

const Bindings := preload("res://input_bindings.gd")
const Settings := preload("res://settings.gd")
const Runner := preload("res://tests/run_tests.gd")

const TRUNCATED := "[audio\nmaster="

var checks := 0
var failures := 0


func _initialize() -> void:
	if not Runner.isolated_user_data_ok():
		print(Runner.ISOLATION_MESSAGE)
		quit(1)
		return
	Bindings.install_defaults()
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() == 1 else ""
	match mode:
		"write": _write()
		"read": _read(_custom(), true)
		"corrupt": _corrupt()
		"fallback": _fallback()
		"restore": _check(Settings.new().save_values(Settings.new().defaults()) == OK, "save defaults")
		"read-defaults": _read(Settings.new().defaults(), false)
		_: _check(false, "known mode (got %s)" % [args])
	print("Probe %s: %d checks, %d failures" % [mode, checks, failures])
	quit(1 if failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)


## J for turn_left, 60/25/0, fullscreen; everything else default.
func _custom() -> Dictionary:
	var c: Dictionary = Settings.new().defaults()
	c["bindings"]["turn_left"] = KEY_J
	c["audio"] = {"master": 0.6, "effects": 0.25, "ambient": 0.0}
	c["display_mode"] = "fullscreen"
	return c


func _write() -> void:
	_check(Settings.new().save_values(_custom()) == OK, "save custom values")
	var config := ConfigFile.new()
	_check(config.load(Settings.PATH) == OK, "saved file parses")
	var expected := {
		"meta": ["version"],
		"bindings": Bindings.default_keycodes().keys(),
		"audio": ["master", "effects", "ambient"],
		"display": ["mode"],
	}
	_check(_sorted(config.get_sections()) == _sorted(expected.keys()), "sections exactly meta/bindings/audio/display")
	for section in expected:
		if config.has_section(section):
			_check(_sorted(config.get_section_keys(section)) == _sorted(expected[section]), "keys of [%s] exactly allowlisted" % section)


func _sorted(items: Array) -> Array:
	var copy := items.duplicate()
	copy.sort()
	return copy


## New process: exact values load and apply; native display is skipped only because headless.
func _read(expected: Dictionary, custom: bool) -> void:
	var settings := Settings.new()
	_check(settings.load_settings() == OK, "load returns OK")
	_check(settings.values == expected, "loaded values exactly expected")
	_check(settings.notice == "", "no load notice")
	settings.apply_values(settings.values)
	_check(AudioServer.get_bus_count() == 3, "project bus layout loaded (3 buses)")
	_check(Bindings.snapshot_keycodes() == expected["bindings"], "InputMap gameplay keys applied")
	var events := InputMap.action_get_events("turn_left")
	var event: InputEventKey = events[0] if events.size() == 1 and events[0] is InputEventKey else null
	_check(event != null and event.keycode == (KEY_J if custom else KEY_A) and event.physical_keycode == 0,
		"turn_left has one logical key event")
	for channel in Settings.BUSES:
		var index := AudioServer.get_bus_index(Settings.BUSES[channel])
		var gain: float = expected["audio"][channel]
		if gain == 0.0:
			_check(AudioServer.is_bus_mute(index), "%s muted" % channel)
		else:
			_check(not AudioServer.is_bus_mute(index), "%s not muted" % channel)
			_check(absf(AudioServer.get_bus_volume_db(index) - linear_to_db(gain)) < 0.001, "%s gain %s" % [channel, gain])
	_check(DisplayServer.get_name() == "headless", "native display skipped only because headless")
	_check(settings.values["display_mode"] == expected["display_mode"], "display mode preserved")


func _corrupt() -> void:
	var file := FileAccess.open(Settings.PATH, FileAccess.WRITE)
	_check(file != null, "open settings file for corruption")
	if file:
		file.store_string(TRUNCATED)
		file.close()
	_check(FileAccess.get_file_as_string(Settings.PATH) == TRUNCATED, "truncated text written")


## New process: unreadable file -> all defaults + notice, menus intact, file not rewritten.
func _fallback() -> void:
	var settings := Settings.new()
	_check(settings.load_settings() != OK, "load of truncated file fails")
	_check(settings.values == settings.defaults(), "all defaults active")
	_check(settings.notice == Settings.LOAD_NOTICE, "load notice shown")
	settings.apply_values(settings.values)
	_check(Bindings.snapshot_keycodes() == Bindings.default_keycodes(), "InputMap gameplay keys are defaults")
	var pause := InputMap.action_get_events("pause")
	_check(pause.size() == 1 and pause[0] is InputEventKey and pause[0].keycode == KEY_ESCAPE, "pause still Escape")
	_check(not InputMap.action_get_events("ui_cancel").is_empty(), "ui_cancel intact")
	_check(not InputMap.action_get_events("ui_accept").is_empty(), "ui_accept intact")
	_check(FileAccess.get_file_as_string(Settings.PATH) == TRUNCATED, "file not rewritten")
