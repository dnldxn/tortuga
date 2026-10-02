extends SceneTree
# External updater-bridge probe. Run against a disposable copy of the project
# whose res://native/bin holds the built extension:
#   <godot> --headless --path <copy> --script <abs>/native/tests/probe.gd
# Prints one "PROBE_RESULT <json>" line; exit 0 only if every check passed.
# Never shipped in a package.

var checks: Array = []


func check(ok: bool, label: String) -> void:
	checks.append({"ok": ok, "label": label})
	print(("ok   " if ok else "FAIL ") + label)


func _init() -> void:
	var result := {
		"pid": OS.get_process_id(),
		"executable": OS.get_executable_path(),
		"user_data_dir": OS.get_user_data_dir(),
		"engine": Engine.get_version_info().string,
	}
	check(ClassDB.class_exists("TortugaUpdaterBridge"), "TortugaUpdaterBridge registered")
	check(ClassDB.is_parent_class("TortugaUpdaterBridge", "RefCounted"), "bridge extends RefCounted")
	var bridge = ClassDB.instantiate("TortugaUpdaterBridge")
	check(bridge != null, "bridge instantiates")
	if bridge == null:
		_finish(result)
		return

	var id: Dictionary = bridge.get_identity()
	result["identity"] = id
	check(id.keys() == ["available", "reason", "identity", "platform_key", "os"], "get_identity keys")
	check(id["available"] == false, "development run unavailable")
	check(String(id["reason"]).begins_with("development build"), "reason names development build")
	check(id["identity"]["package_version"] == "0.0.0-dev" and id["identity"]["is_release"] == false,
			"nested compiled development identity")
	check(id["platform_key"] == "linux-x86_64", "platform_key linux-x86_64")
	check(String(id["os"].get("glibc", "")) != "", "os.glibc observed")

	var target := {
		"app_id": "org.tortuga.game", "channel": "dev", "platform": "linux-x86_64", "version": "0.2.0",
		"base_url": "https://github.com/dnldxn/tortuga/releases/download/v0.2/",
		"full_filename": "org.tortuga.game-0.2.0-full.nupkg", "sha256": "0".repeat(64), "size": 1,
		"minimum_os": "",
	}
	result["begin_check"] = bridge.begin_check(target, 7)
	check(result["begin_check"] == ERR_UNAVAILABLE, "begin_check on unavailable -> ERR_UNAVAILABLE")
	check(bridge.begin_check({}, 8) == ERR_INVALID_PARAMETER, "begin_check malformed target -> ERR_INVALID_PARAMETER")
	var float_size := target.duplicate()
	float_size["size"] = 1.0
	check(bridge.begin_check(float_size, 9) == ERR_INVALID_PARAMETER, "float size -> ERR_INVALID_PARAMETER")
	check(bridge.begin_download(target, 7) == ERR_UNAVAILABLE, "begin_download -> ERR_UNAVAILABLE")
	check(bridge.prepare_apply(7, PackedStringArray()) == ERR_UNAVAILABLE, "prepare_apply -> ERR_UNAVAILABLE")
	check(bridge.is_busy() == false, "not busy")
	check(bridge.poll_events() == [], "no events yet")

	bridge.request_shutdown()
	var events: Array = bridge.poll_events()
	result["events"] = events
	check(events.size() == 1 and events[0] is Dictionary, "one event Dictionary after shutdown")
	if events.size() == 1:
		check(events[0].keys() == ["request_id", "kind", "payload"], "event keys")
		check(events[0]["kind"] == "worker_stopped", "worker_stopped")
		events[0]["kind"] = "mutated"
	check(bridge.poll_events() == [], "queue drained exactly once")
	bridge = null  # RefCounted release: destructor joins any worker
	_finish(result)


func _finish(result: Dictionary) -> void:
	var failed := checks.filter(func(c): return not c["ok"]).size()
	result["checks"] = checks.size()
	result["failures"] = failed
	print("PROBE_RESULT " + JSON.stringify(result))
	quit(1 if failed or checks.is_empty() else 0)
