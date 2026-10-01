extends RefCounted
## Settings model, ConfigFile persistence/fallback, key remapping and audio buses.
## Runs only under the runner's isolated user:// (see run_settings_checks.sh). Restores the
## InputMap and bus layout it found, so later suites see the defaults.

const Bindings := preload("res://input_bindings.gd")
const Settings := preload("res://settings.gd")

const NOTICE := "Settings could not be loaded; defaults are active."
const GAMEPLAY := ["turn_left", "turn_right", "toggle_sails", "fire_port", "fire_starboard",
	"cycle_port", "cycle_starboard", "reset_practice"]

var t
var changed_count := 0


func run(runner) -> bool:
	t = runner
	Bindings.install_defaults()
	var saved_events := {}
	for action in GAMEPLAY + ["pause", "ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next"]:
		saved_events[action] = InputMap.action_get_events(action)
	t.check(AudioServer.get_bus_count() == 3, "project default bus layout loaded at startup")
	var saved_layout := AudioServer.generate_bus_layout()

	_test_contract()
	_test_persistence()
	_test_bad_files()
	_test_bindings(saved_events)
	_test_buses()
	_test_apply_values()

	for action in saved_events:
		InputMap.action_erase_events(action)
		for event in saved_events[action]:
			InputMap.action_add_event(action, event)
	AudioServer.set_bus_layout(saved_layout)
	return true


func _check(ok: bool, label: String) -> void:
	t.check(ok, label)


## A valid non-default state, so a fallback visibly replaces it with defaults.
func _custom(settings) -> Dictionary:
	var draft: Dictionary = settings.defaults()
	draft["bindings"]["turn_left"] = KEY_J
	draft["audio"]["master"] = 0.25
	draft["display_mode"] = "fullscreen"
	return draft


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Complete valid file text with one line substituted (key=value, or a whole line).
func _valid_text(replace := {}) -> String:
	var lines := ["[meta]", "version=1", "[bindings]"]
	var codes := Bindings.default_keycodes()
	for action in codes:
		lines.append("%s=%d" % [action, codes[action]])
	lines.append_array(["[audio]", "master=1.0", "effects=0.8", "ambient=0.35", "[display]", 'mode="windowed"'])
	var out := []
	for line in lines:
		var key: String = line.split("=")[0]
		if replace.has(key):
			if replace[key] != null:
				out.append(replace[key])
		else:
			out.append(line)
	return "\n".join(out) + "\n"


# --- Task 1/2: contract and persistence ---

func _test_contract() -> void:
	var settings = Settings.new()
	_check(settings.values == settings.defaults(), "constructor values are defaults (no I/O)")
	_check(settings.load_settings("user://missing.cfg") == ERR_FILE_NOT_FOUND, "normal first launch")
	_check(settings.values == settings.defaults(), "complete first-run defaults")
	_check(settings.notice == "", "missing file is silent")
	_check(not FileAccess.file_exists("user://missing.cfg"), "first launch does not write a file")
	var d: Dictionary = settings.defaults()
	_check(d["version"] == 1 and d["display_mode"] == "windowed", "default version and mode")
	_check(d["audio"] == {"master": 1.0, "effects": 0.8, "ambient": 0.35}, "default volumes")
	_check(d["bindings"] == {"turn_left": KEY_A, "turn_right": KEY_D, "toggle_sails": KEY_W,
		"fire_port": KEY_Q, "fire_starboard": KEY_E, "cycle_port": KEY_Z, "cycle_starboard": KEY_C,
		"reset_practice": KEY_R}, "default bindings exclude pause")
	_check(settings.validate(d), "defaults validate")


func _test_persistence() -> void:
	var settings = Settings.new()
	var draft = settings.defaults()
	draft["audio"]["effects"] = 0.2
	_check(settings.defaults()["audio"]["effects"] == 0.8, "immutable defaults")
	_check(settings.save_values(draft, "user://roundtrip.cfg") == OK, "save")
	_check(settings.values == settings.defaults(), "save does not mutate values")
	_check(settings.load_settings("user://roundtrip.cfg") == OK, "load")
	_check(settings.values == draft, "round trip")
	_check(settings.notice == "", "clean load has no notice")

	# Saved file holds exactly the schema sections/keys.
	var config := ConfigFile.new()
	config.load("user://roundtrip.cfg")
	_check(Array(config.get_sections()) == ["meta", "bindings", "audio", "display"], "saved sections")
	_check(Array(config.get_section_keys("meta")) == ["version"], "saved meta keys")
	_check(Array(config.get_section_keys("bindings")) == GAMEPLAY, "saved binding keys")
	_check(Array(config.get_section_keys("audio")) == ["master", "effects", "ambient"], "saved audio keys")
	_check(Array(config.get_section_keys("display")) == ["mode"], "saved display keys")

	# Integer volumes are accepted and normalised to float.
	_write("user://intvol.cfg", _valid_text({"master": "master=1", "ambient": "ambient=0"}))
	_check(settings.load_settings("user://intvol.cfg") == OK, "integer volumes load")
	_check(typeof(settings.values["audio"]["master"]) == TYPE_FLOAT and settings.values["audio"]["ambient"] == 0.0,
		"integer volumes stored as floats")

	# Extra data is ignored on read and omitted on save.
	_write("user://extra.cfg", _valid_text() + "[encounter]\nhull=12\n[audio]\nmusic=0.3\n")
	_check(settings.load_settings("user://extra.cfg") == OK, "extra keys ignored on load")
	_check(settings.values == settings.defaults(), "extra keys do not change values")
	var with_extra: Dictionary = settings.values.duplicate(true)
	with_extra["encounter"] = {"hull": 12}
	_check(settings.save_values(with_extra, "user://extra.cfg") == ERR_INVALID_PARAMETER, "extra candidate key rejected")
	_check(settings.save_values(settings.values, "user://extra.cfg") == OK, "re-save")
	var text := FileAccess.get_file_as_string("user://extra.cfg")
	_check("encounter" not in text and "music" not in text, "extra data omitted on save")

	# Invalid candidate / unwritable path: no write, no value change.
	var custom := _custom(settings)
	settings.values = custom.duplicate(true)
	var bad: Dictionary = settings.defaults()
	bad["audio"]["master"] = 2.0
	_check(settings.save_values(bad, "user://bad.cfg") == ERR_INVALID_PARAMETER, "invalid candidate not saved")
	_check(not FileAccess.file_exists("user://bad.cfg"), "invalid candidate writes nothing")
	_check(settings.save_values(settings.defaults(), "user://missing-parent/settings.cfg") != OK, "missing parent fails save")
	_check(settings.values == custom, "failed saves leave values unchanged")


func _test_bad_files() -> void:
	var settings = Settings.new()
	var custom := _custom(settings)
	var cases := {
		"truncated": "[audio\nmaster=",
		"missing version": _valid_text({"version": null}),
		"version 99": _valid_text({"version": "version=99"}),
		"version float": _valid_text({"version": "version=1.0"}),
		"missing action": _valid_text({"cycle_port": null}),
		"volume true": _valid_text({"master": "master=true"}),
		"volume string": _valid_text({"master": 'master="0.5"'}),
		"volume negative": _valid_text({"effects": "effects=-0.1"}),
		"volume above 1": _valid_text({"effects": "effects=1.1"}),
		# ConfigFile parses bare nan/inf as float NaN/INF (verified on 4.7.2).
		"volume nan": _valid_text({"ambient": "ambient=nan"}),
		"volume inf": _valid_text({"ambient": "ambient=inf"}),
		"missing volume": _valid_text({"ambient": null}),
		"bad mode": _valid_text({"mode": 'mode="exclusive_fullscreen"'}),
		"mode not string": _valid_text({"mode": "mode=1"}),
		"code 0": _valid_text({"turn_left": "turn_left=0"}),
		"code -1": _valid_text({"turn_left": "turn_left=-1"}),
		"code huge": _valid_text({"turn_left": "turn_left=99999999"}),
		"code Escape": _valid_text({"turn_left": "turn_left=%d" % KEY_ESCAPE}),
		"code float": _valid_text({"turn_left": "turn_left=%d.0" % KEY_J}),
		"code string": _valid_text({"turn_left": 'turn_left="J"'}),
		"duplicate key": _valid_text({"turn_left": "turn_left=%d" % KEY_D}),
	}
	for label in cases:
		settings.values = custom.duplicate(true)
		settings.notice = ""
		var path := "user://bad_%s.cfg" % label.replace(" ", "_")
		_write(path, cases[label])
		var before := FileAccess.get_file_as_string(path)
		var err: Error = settings.load_settings(path)
		var expected: Error = ERR_PARSE_ERROR if label == "truncated" else ERR_INVALID_DATA
		_check(err == expected, "%s: load error %d (got %d)" % [label, expected, err])
		_check(settings.values == settings.defaults(), "%s: all defaults active" % label)
		_check(settings.notice == NOTICE, "%s: notice shown" % label)
		_check(FileAccess.get_file_as_string(path) == before, "%s: file not rewritten" % label)
	# A good load after a bad one clears the notice.
	settings.save_values(settings.defaults(), "user://good.cfg")
	settings.load_settings("user://good.cfg")
	_check(settings.notice == "", "notice cleared by a good load")


# --- Task 3: remapping ---

func _test_bindings(saved_events: Dictionary) -> void:
	var settings = Settings.new()
	var draft = settings.defaults()
	var codes: Dictionary = draft["bindings"]
	_check(Bindings.binding_problem("turn_left", KEY_Q, codes) == "Already used by Fire port. Choose another key.",
		"cannot steal Fire port")
	_check(Bindings.binding_problem("turn_left", KEY_A, codes) == "", "same key is a no-op")
	_check(Bindings.binding_problem("turn_left", KEY_R, codes) == "Already used by Reset practice. Choose another key.",
		"reset practice conflicts globally")
	_check(codes == settings.defaults()["bindings"], "conflict does not swap or unbind")
	for code in [KEY_ESCAPE, KEY_TAB, KEY_BACKTAB, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_LEFT, KEY_RIGHT,
			KEY_UP, KEY_DOWN, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN, KEY_SHIFT, KEY_CTRL, KEY_ALT,
			KEY_META, KEY_CAPSLOCK]:
		_check(Bindings.binding_problem("turn_left", code, codes) == Bindings.RESERVED_MESSAGE,
			"reserved: %s" % OS.get_keycode_string(code))
	for code in [0, -1, KEY_INSERT, KEY_KP_5, KEY_F13, KEY_PRINT]:
		_check(Bindings.binding_problem("turn_left", code, codes) == Bindings.UNSUPPORTED_MESSAGE,
			"unsupported: %d" % code)
	_check(Bindings.binding_problem("turn_left", KEY_A | KEY_MASK_CTRL, codes) == Bindings.SINGLE_KEY_MESSAGE,
		"chord rejected")
	for code in [KEY_J, KEY_0, KEY_9, KEY_F1, KEY_F12, KEY_MINUS, KEY_EQUAL, KEY_BRACKETLEFT, KEY_BRACKETRIGHT,
			KEY_BACKSLASH, KEY_SEMICOLON, KEY_APOSTROPHE, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_QUOTELEFT]:
		_check(Bindings.binding_problem("turn_left", code, codes) == "", "allowed: %s" % OS.get_keycode_string(code))
	for bad in [true, float(KEY_J), "J", null]:
		var c: Dictionary = settings.defaults()
		c["bindings"]["turn_left"] = bad
		_check(not settings.validate(c), "non-int code rejected: %s" % str(bad))
	var short: Dictionary = settings.defaults()
	short["bindings"].erase("reset_practice")
	_check(not settings.validate(short), "incomplete binding map rejected")
	var extra: Dictionary = settings.defaults()
	extra["bindings"]["pause"] = KEY_P
	_check(not settings.validate(extra), "pause not remappable")

	# A -> J, logical identity only.
	_check(Bindings.binding_problem("turn_left", KEY_Q, draft["bindings"]) != "", "cannot steal Fire port")
	draft["bindings"]["turn_left"] = KEY_J
	Bindings.apply_keycodes(draft["bindings"])
	var events = InputMap.action_get_events("turn_left")
	_check(events.size() == 1 and events[0].keycode == KEY_J, "logical J replaces A")
	_check(events[0].physical_keycode == 0 and events[0].unicode == 0, "stored mapping has logical key identity only")
	_check(Bindings.binding_label("turn_left") == OS.get_keycode_string(KEY_J), "prompt displays logical J")
	_check(Bindings.key_label(KEY_F5) == OS.get_keycode_string(KEY_F5), "draft label helper")
	_check(Bindings.snapshot_keycodes() == draft["bindings"], "snapshot reads live logical codes")
	Bindings.apply_keycodes(draft["bindings"])
	for action in GAMEPLAY:
		_check(InputMap.action_get_events(action).size() == 1, "%s: one event after repeated apply" % action)
	for action in saved_events:
		if action not in GAMEPLAY:
			_check(InputMap.action_get_events(action) == saved_events[action], "%s untouched by apply" % action)

	# Invalid candidates change nothing.
	var dup: Dictionary = draft["bindings"].duplicate()
	dup["turn_right"] = KEY_J
	Bindings.apply_keycodes(dup)
	_check(Bindings.snapshot_keycodes() == draft["bindings"], "duplicate candidate not applied")

	# Restore defaults.
	Bindings.apply_keycodes(Bindings.default_keycodes())
	_check(Bindings.snapshot_keycodes() == Bindings.default_keycodes(), "restore defaults")
	_check(Bindings.binding_label("turn_left") == "A", "default prompt restored")
	_check(Bindings.default_keycodes()["turn_left"] == KEY_A, "default catalog independent of InputMap")


# --- Task 4: buses and apply_values ---

func _test_buses() -> void:
	AudioServer.set_bus_layout(load("res://default_bus_layout.tres"))
	_check(AudioServer.get_bus_count() == 3, "three buses")
	_check(AudioServer.get_bus_name(0) == "Master", "Master is bus 0")
	for pair in [["Effects", -1.9382], ["Ambient", -9.1186]]:
		var i := AudioServer.get_bus_index(pair[0])
		_check(i > 0 and AudioServer.get_bus_send(i) == &"Master", "%s sends to Master" % pair[0])
		t.near(AudioServer.get_bus_volume_db(i), pair[1], 0.001, "%s layout dB" % pair[0])
		_check(AudioServer.get_bus_effect_count(i) == 0 and not AudioServer.is_bus_mute(i)
			and not AudioServer.is_bus_solo(i), "%s has no effects/mute/solo" % pair[0])
	t.near(AudioServer.get_bus_volume_db(0), 0.0, 0.001, "Master layout dB")
	var settings = Settings.new()
	t.near(AudioServer.get_bus_volume_db(1), linear_to_db(settings.defaults()["audio"]["effects"]), 0.001,
		"layout matches linear effects default")
	t.near(AudioServer.get_bus_volume_db(2), linear_to_db(settings.defaults()["audio"]["ambient"]), 0.001,
		"layout matches linear ambient default")

	var draft: Dictionary = settings.defaults()
	draft["audio"]["effects"] = 0.0
	settings.apply_values(draft)
	var fx := AudioServer.get_bus_index("Effects")
	var amb := AudioServer.get_bus_index("Ambient")
	_check(AudioServer.is_bus_mute(fx), "zero mutes Effects")
	_check(not AudioServer.is_bus_mute(amb), "Ambient independent of Effects")
	t.near(AudioServer.get_bus_volume_db(amb), linear_to_db(0.35), 0.001, "Ambient keeps its gain")
	draft["audio"]["effects"] = 0.5
	settings.apply_values(draft)
	_check(not AudioServer.is_bus_mute(fx), "positive gain unmutes")
	t.near(AudioServer.get_bus_volume_db(fx), linear_to_db(0.5), 0.001, "Effects at 0.5")
	draft["audio"]["ambient"] = 0.0
	draft["audio"]["effects"] = 1.0
	settings.apply_values(draft)
	_check(AudioServer.is_bus_mute(amb) and not AudioServer.is_bus_mute(fx), "Ambient mutes alone")
	t.near(AudioServer.get_bus_volume_db(fx), 0.0, 0.001, "Effects at 1.0")
	var bad: Dictionary = settings.defaults()
	bad["display_mode"] = "exclusive_fullscreen"
	_check(not settings.validate(bad), "bad mode rejected")
	settings.apply_values(settings.defaults())


func _on_changed() -> void:
	changed_count += 1


func _test_apply_values() -> void:
	var settings = Settings.new()
	settings.changed.connect(_on_changed)
	var candidate := _custom(settings)
	candidate["audio"]["effects"] = 0.5
	changed_count = 0
	settings.apply_values(candidate)
	_check(changed_count == 1, "changed emitted once")
	_check(settings.values == candidate, "values equal applied candidate")
	_check(Bindings.snapshot_keycodes() == candidate["bindings"], "apply_values updates InputMap")
	t.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), linear_to_db(0.25), 0.001,
		"apply_values sets Master gain")
	t.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects")), linear_to_db(0.5), 0.001,
		"apply_values sets Effects gain")
	_check(settings.values["display_mode"] == "fullscreen", "headless retains display preference")
	candidate["audio"]["master"] = 0.9
	candidate["bindings"]["turn_left"] = KEY_K
	_check(settings.values["audio"]["master"] == 0.25 and settings.values["bindings"]["turn_left"] == KEY_J,
		"values is a deep copy")

	var invalid: Dictionary = settings.defaults()
	invalid["bindings"]["turn_left"] = KEY_ESCAPE
	var before: Dictionary = settings.values.duplicate(true)
	changed_count = 0
	settings.apply_values(invalid)
	_check(changed_count == 0 and settings.values == before, "invalid candidate not applied")
	_check(Bindings.snapshot_keycodes()["turn_left"] == KEY_J, "invalid candidate leaves InputMap")

	settings.apply_values(settings.defaults())
	_check(Bindings.snapshot_keycodes() == Bindings.default_keycodes(), "defaults restored via apply_values")
