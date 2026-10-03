extends RefCounted
## Phase 3 plan 03 task 3: the remembered multiplayer settings file (user://multiplayer.cfg model).

const MultiplayerConfig := preload("res://net/multiplayer_config.gd")
const Protocol := preload("res://net/protocol.gd")
const TEST_PATH := "user://test_multiplayer.cfg"


func run(t) -> bool:
	for test in [_test_defaults, _test_first_load, _test_remember, _test_corrupt, _test_field_checks]:
		t.check(test.call(t) == true, "multiplayer config: %s completed" % test.get_method())
	_remove()
	return true


func _remove() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _is_id(id) -> bool:
	return id is String and id.length() == 32 and id == id.to_lower() and id.is_valid_hex_number(false)


func _test_defaults(t) -> bool:
	_remove()
	var config := MultiplayerConfig.new(TEST_PATH)
	t.check(config.path == TEST_PATH, "multiplayer config: custom path kept")
	t.check(MultiplayerConfig.new().path == "user://multiplayer.cfg", "multiplayer config: default path")
	t.check(config.values == MultiplayerConfig.defaults(), "multiplayer config: _init yields defaults")
	t.check(not FileAccess.file_exists(TEST_PATH), "multiplayer config: _init does no I/O")
	var d := MultiplayerConfig.defaults()
	t.check(d["name"] == "Captain" and d["port"] == Protocol.DEFAULT_PORT and d["host"] == "" and d["password"] == "" \
		and d["captain_id"] == "", "multiplayer config: default values")
	var a := MultiplayerConfig.new_captain_id()
	t.check(_is_id(a) and a != MultiplayerConfig.new_captain_id(), "multiplayer config: random 32-hex captain ids")
	return true


func _test_first_load(t) -> bool:
	_remove()
	var first := MultiplayerConfig.new(TEST_PATH)
	t.check(first.load_config() == false, "multiplayer config: missing file reports a replacement")
	var id: String = first.values["captain_id"]
	t.check(_is_id(id), "multiplayer config: missing file generates a captain id")
	t.check(FileAccess.file_exists(TEST_PATH), "multiplayer config: missing file is written")
	var second := MultiplayerConfig.new(TEST_PATH)
	t.check(second.load_config() == true, "multiplayer config: second load is clean")
	t.check(second.values["captain_id"] == id, "multiplayer config: captain id persists")
	t.check(second.values["name"] == "Captain" and second.values["port"] == Protocol.DEFAULT_PORT,
		"multiplayer config: other fields default")
	return true


func _test_remember(t) -> bool:
	_remove()
	var config := MultiplayerConfig.new(TEST_PATH)
	config.load_config()
	var id: String = config.values["captain_id"]
	t.check(config.remember("example.org", 24681, "  Anne ", "pw") == OK, "multiplayer config: remember is OK")
	var other := MultiplayerConfig.new(TEST_PATH)
	t.check(other.load_config() == true, "multiplayer config: remembered file loads clean")
	t.check(other.values == {"captain_id": id, "name": "Anne", "host": "example.org", "port": 24681, "password": "pw"},
		"multiplayer config: remember round-trips with a stripped name")
	var before: Dictionary = config.values.duplicate()
	t.check(config.remember("", 0, "", "") == ERR_INVALID_PARAMETER, "multiplayer config: invalid remember refused")
	t.check(config.values == before, "multiplayer config: refused remember leaves values unchanged")
	t.check(config.remember("h", 70000, "Anne", "") == ERR_INVALID_PARAMETER, "multiplayer config: port above 65535 refused")
	t.check(config.remember("h", 1, "   ", "") == ERR_INVALID_PARAMETER, "multiplayer config: blank name refused")
	t.check(config.remember("h", 1, "x".repeat(17), "") == ERR_INVALID_PARAMETER, "multiplayer config: name over 16 refused")
	t.check(config.remember("h", 1, "x".repeat(16), "p".repeat(65)) == ERR_INVALID_PARAMETER,
		"multiplayer config: password over 64 refused")
	t.check(config.remember("h".repeat(254), 1, "Anne", "") == ERR_INVALID_PARAMETER, "multiplayer config: host over 253 refused")
	t.check(config.remember("", 65535, "x".repeat(16), "") == OK, "multiplayer config: empty host and boundary values accepted")
	t.check(config.values == before.merged({"host": "", "port": 65535, "name": "x".repeat(16), "password": ""}, true),
		"multiplayer config: accepted remember updates values")
	return true


func _test_corrupt(t) -> bool:
	_remove()
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("not a config [")
	file.close()
	var config := MultiplayerConfig.new(TEST_PATH)
	t.check(config.load_config() == false, "multiplayer config: corrupt file reports a replacement")
	var id: String = config.values["captain_id"]
	t.check(_is_id(id), "multiplayer config: corrupt file gets a fresh id")
	var expected := MultiplayerConfig.defaults()
	expected["captain_id"] = id
	t.check(config.values == expected, "multiplayer config: corrupt file yields defaults")
	var again := MultiplayerConfig.new(TEST_PATH)
	t.check(again.load_config() == true and again.values["captain_id"] == id,
		"multiplayer config: rewritten file loads with the fresh id")
	return true


func _write_cfg(id, name, host, port, password) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("captain", "id", id)
	cfg.set_value("captain", "name", name)
	cfg.set_value("server", "host", host)
	cfg.set_value("server", "port", port)
	cfg.set_value("server", "password", password)
	cfg.save(TEST_PATH)


func _test_field_checks(t) -> bool:
	# A valid file loads untouched.
	var good_id := "0123456789abcdef0123456789abcdef"
	_write_cfg(good_id, "Anne", "h.example", 24680, "pw")
	var config := MultiplayerConfig.new(TEST_PATH)
	t.check(config.load_config() == true, "multiplayer config: valid file loads clean")
	t.check(config.values == {"captain_id": good_id, "name": "Anne", "host": "h.example", "port": 24680, "password": "pw"},
		"multiplayer config: valid file values kept")
	# A bad port alone resets only the port (and rewrites the file).
	_write_cfg(good_id, "Anne", "h.example", "24680", "pw")
	config = MultiplayerConfig.new(TEST_PATH)
	t.check(config.load_config() == false, "multiplayer config: string port is replaced")
	t.check(config.values["port"] == Protocol.DEFAULT_PORT and config.values["name"] == "Anne"
		and config.values["captain_id"] == good_id, "multiplayer config: only the bad field resets")
	t.check(MultiplayerConfig.new(TEST_PATH).load_config() == true, "multiplayer config: repaired file loads clean")
	# Other bad values: out-of-range port, long name, blank name, malformed ids.
	for bad in [[good_id, "Anne", "h", 0, ""], [good_id, "Anne", "h", 65536, ""], [good_id, "x".repeat(17), "h", 1, ""],
			[good_id, "   ", "h", 1, ""], ["ABCDEF0123456789ABCDEF0123456789", "Anne", "h", 1, ""],
			["short", "Anne", "h", 1, ""], ["-" + good_id.substr(1), "Anne", "h", 1, ""], ["+" + good_id.substr(1), "Anne", "h", 1, ""],
			[good_id + "0", "Anne", "h", 1, ""], [5, "Anne", "h", 1, ""], [good_id, "Anne", "h".repeat(254), 1, ""],
			[good_id, "Anne", "h", 1, "p".repeat(65)], [good_id, 5, "h", 1, ""]]:
		_write_cfg(bad[0], bad[1], bad[2], bad[3], bad[4])
		var c := MultiplayerConfig.new(TEST_PATH)
		t.check(c.load_config() == false, "multiplayer config: bad field replaced (%s)" % [bad])
		t.check(_is_id(c.values["captain_id"]), "multiplayer config: id stays valid (%s)" % [bad])
	# A malformed id is regenerated while a good name survives.
	_write_cfg("nothex", "Anne", "h", 1, "")
	config = MultiplayerConfig.new(TEST_PATH)
	config.load_config()
	t.check(config.values["captain_id"] != "nothex" and config.values["name"] == "Anne",
		"multiplayer config: malformed id regenerated, name kept")
	# A name is stripped on load too.
	_write_cfg(good_id, "  Bob  ", "h", 1, "")
	config = MultiplayerConfig.new(TEST_PATH)
	t.check(config.load_config() == true and config.values["name"] == "Bob", "multiplayer config: loaded name stripped")
	return true
