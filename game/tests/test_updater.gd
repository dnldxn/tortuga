extends RefCounted
## Update pack checks: boot.gd's installed-pack rules against real PCKPacker packs, plus the
## update service's manifest, decision, install and node behavior (no network).
## Touches only user://updates/, user://version_test.cfg and user://probe_src.txt (deleted at start
## and end). Loaded packs persist for the whole process, so each pack case has its own probe file.
## The corrupt-pack case may print engine errors.

const Boot := preload("res://boot.gd")
const UpdateService := preload("res://update/update_service.gd")

const UPDATES_DIR := "user://updates"
const VERSION_CFG := "user://version_test.cfg"
const PROBE_SRC := "user://probe_src.txt"


func run(t) -> bool:
	_cleanup()
	# A runtime error inside a callee only aborts that function, so each must report completion.
	for test: Callable in [_test_is_newer, _test_loads_newer_pack, _test_rejected_packs, _test_missing,
			_test_corrupt_pack, _test_parse_manifest, _test_platform_key, _test_decide, _test_install_pack,
			_test_node_dev_build, _test_node_manifest, _test_node_bad_pack, _test_menu_dev_build,
			_test_menu_wiring, _test_menu_states, _test_menu_focus, _test_menu_mode_screen_only,
			_test_menu_fits_screen]:
		t.check(test.call(t) == true, "%s ran to the end" % test.get_method())
	_cleanup()
	return true


# --- helpers ---


## Deletes everything this suite may have written.
func _cleanup() -> void:
	var dir := DirAccess.open(UPDATES_DIR)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(UPDATES_DIR)
	DirAccess.remove_absolute(VERSION_CFG)
	DirAccess.remove_absolute(PROBE_SRC)


## Packs res://update_probe_<n>.txt (content "probe <n>") into user://updates/<file>.
func _make_pack(t, n: int, file: String) -> void:
	DirAccess.make_dir_recursive_absolute(UPDATES_DIR)
	var src := FileAccess.open(PROBE_SRC, FileAccess.WRITE)
	src.store_string("probe %d" % n)
	src.close()
	var packer := PCKPacker.new()
	var started := packer.pck_start(UPDATES_DIR.path_join(file))
	var added := packer.add_file("res://update_probe_%d.txt" % n, PROBE_SRC)
	var flushed := packer.flush()
	t.check(started == OK and added == OK and flushed == OK, "pack %s built" % file)


## Writes the build's version.cfg stand-in.
func _write_build(version: String, base: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("build", "version", version)
	cfg.set_value("build", "base", base)
	cfg.save(VERSION_CFG)


## Writes installed.cfg naming `file` (creating user://updates/ if needed).
func _write_installed(version: String, base: String, file: String) -> void:
	DirAccess.make_dir_recursive_absolute(UPDATES_DIR)
	var cfg := ConfigFile.new()
	cfg.set_value("pack", "version", version)
	cfg.set_value("pack", "base", base)
	cfg.set_value("pack", "file", file)
	cfg.save(UPDATES_DIR.path_join("installed.cfg"))


func _load() -> bool:
	return Boot.load_installed_pack(VERSION_CFG, UPDATES_DIR)


## Manifest dictionary listing all three platforms for `version`/`base`.
func _manifest(version: String, base: String) -> Dictionary:
	var packs := {}
	for platform in ["windows", "macos", "linux"]:
		packs[platform] = {"file": "tortuga-%s-%s.pck" % [version, platform], "sha256": "probe".sha256_text()}
	return {"version": version, "base": base, "packs": packs}


func _manifest_json(version: String, base: String) -> String:
	return JSON.stringify(_manifest(version, base))


func _write_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## A service node inside the tree (so _ready ran). Callers free it.
func _new_service(t) -> Node:
	var service := UpdateService.new()
	t.root.add_child(service)
	return service


## A real main scene in selection mode (UI built in _ready). Callers free it.
func _new_main(t) -> Node:
	var main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	return main


## Drives the menu the way the service does. Never press full_download_button or emit
## full_download_requested in tests: it opens a real browser.
func _emit_state(main: Node, state: String, detail := "") -> void:
	main.update_service.state_changed.emit(state, detail)


## The five mode buttons, Multiplayer and Settings (everything a download locks except Quit).
func _locked_buttons(sel) -> Array:
	return [sel.sailing_button, sel.multiplayer_button, sel.settings_button] + sel.duel_buttons.values()


func _all_disabled(buttons: Array) -> bool:
	for button in buttons:
		if not button.disabled:
			return false
	return true


func _all_enabled(buttons: Array) -> bool:
	for button in buttons:
		if button.disabled:
			return false
	return true


## Feeds the service a manifest response as the HTTPRequest would.
func _complete_manifest(service: Node, result: int, code: int, body: String) -> void:
	service._on_manifest_completed(result, code, PackedStringArray(), body.to_utf8_buffer())


# --- tests ---


func _test_is_newer(t) -> bool:
	t.check(Boot.is_newer("0.10", "0.9"), "0.10 is newer than 0.9")
	t.check(Boot.is_newer("1.0", "0.99"), "1.0 is newer than 0.99")
	t.check(not Boot.is_newer("0.9", "0.10"), "0.9 is not newer than 0.10")
	t.check(not Boot.is_newer("0.3", "0.3"), "equal versions are not newer")
	return true


## A newer pack on a matching base loads and overlays its files into res://.
func _test_loads_newer_pack(t) -> bool:
	_make_pack(t, 1, "pack_1.pck")
	_write_build("0.2", "b1")
	_write_installed("0.3", "b1", "pack_1.pck")
	t.check(_load(), "newer pack on the same base loads")
	t.check(FileAccess.file_exists("res://update_probe_1.txt"), "loaded pack overlays its probe file")
	t.check(FileAccess.get_file_as_string("res://update_probe_1.txt") == "probe 1",
		"overlaid probe file has the pack's content")
	t.check(FileAccess.file_exists(UPDATES_DIR.path_join("installed.cfg")), "installed.cfg kept after a good load")
	return true


## Base mismatch, dev builds and not-newer packs are rejected without touching res://.
func _test_rejected_packs(t) -> bool:
	_make_pack(t, 2, "pack_2.pck")
	_write_build("0.2", "b1")
	_write_installed("0.3", "b2", "pack_2.pck")
	t.check(not _load() and not FileAccess.file_exists("res://update_probe_2.txt"),
		"pack with a different base is rejected")

	_make_pack(t, 3, "pack_3.pck")
	_write_build("dev", "dev")
	_write_installed("0.3", "dev", "pack_3.pck")
	t.check(not _load() and not FileAccess.file_exists("res://update_probe_3.txt"),
		"dev build loads no pack")

	_make_pack(t, 4, "pack_4.pck")
	_write_build("0.2", "b1")
	_write_installed("0.2", "b1", "pack_4.pck")
	t.check(not _load() and not FileAccess.file_exists("res://update_probe_4.txt"),
		"pack with the build's own version is rejected")
	return true


func _test_missing(t) -> bool:
	_write_build("0.2", "b1")
	DirAccess.remove_absolute(UPDATES_DIR.path_join("installed.cfg"))
	t.check(not _load(), "no installed.cfg loads nothing")
	_write_installed("0.3", "b1", "no_such_pack.pck")
	t.check(not _load(), "installed.cfg naming a missing pack file loads nothing")
	return true


## A pack file that isn't a pack returns false and its installed.cfg is deleted.
func _test_corrupt_pack(t) -> bool:
	_write_build("0.2", "b1")
	_write_installed("0.3", "b1", "pack_bad.pck")
	var bad := FileAccess.open(UPDATES_DIR.path_join("pack_bad.pck"), FileAccess.WRITE)
	bad.store_buffer(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]))
	bad.close()
	t.check(not _load(), "corrupt pack is not loaded")
	t.check(not FileAccess.file_exists(UPDATES_DIR.path_join("installed.cfg")),
		"corrupt pack deletes installed.cfg")
	return true


# --- update service ---


func _test_parse_manifest(t) -> bool:
	t.check(UpdateService.parse_manifest(_manifest_json("0.4", "b1")).get("version") == "0.4",
		"valid manifest parses")
	for text in ["", "nope", "[]"]:
		t.check(UpdateService.parse_manifest(text).is_empty(), "manifest %s is invalid" % JSON.stringify(text))
	var no_base := _manifest("0.4", "b1")
	no_base.erase("base")
	t.check(UpdateService.parse_manifest(JSON.stringify(no_base)).is_empty(), "manifest without base is invalid")
	var no_sha := _manifest("0.4", "b1")
	no_sha["packs"]["linux"].erase("sha256")
	t.check(UpdateService.parse_manifest(JSON.stringify(no_sha)).is_empty(), "pack without sha256 is invalid")
	var bad_file := _manifest("0.4", "b1")
	bad_file["packs"]["linux"]["file"] = "../x.pck"
	t.check(UpdateService.parse_manifest(JSON.stringify(bad_file)).is_empty(), "pack file with a path is invalid")
	var number_version := _manifest("0.4", "b1")
	number_version["version"] = 0.4
	t.check(UpdateService.parse_manifest(JSON.stringify(number_version)).is_empty(),
		"non-string version is invalid")
	return true


func _test_platform_key(t) -> bool:
	t.check(UpdateService.platform_key() in ["windows", "macos", "linux"], "platform_key names this host")
	return true


func _test_decide(t) -> bool:
	var manifest := UpdateService.parse_manifest(_manifest_json("0.4", "b1"))
	var update := UpdateService.decide(manifest, "0.3", "b1", "linux")
	t.check(update.get("state") == "update" and update.get("version") == "0.4", "newer build gets an update")
	t.check(update.get("file") == "tortuga-0.4-linux.pck" and update.get("sha256") == "probe".sha256_text(),
		"update names the platform's pack file and hash")
	t.check(UpdateService.decide(manifest, "0.4", "b1", "linux").get("state") == "up_to_date",
		"same version is up to date")
	t.check(UpdateService.decide(manifest, "0.5", "b1", "linux").get("state") == "up_to_date",
		"newer build is up to date")
	var other_base := UpdateService.decide(manifest, "0.3", "b2", "linux")
	t.check(other_base.get("state") == "full_download" and other_base.get("version") == "0.4",
		"different base needs a full download")
	var no_platform := UpdateService.decide(manifest, "0.3", "b1", "")
	t.check(no_platform.get("state") == "full_download" and no_platform.get("version") == "0.4",
		"unknown platform needs a full download")
	t.check(UpdateService.is_newer("0.10", "0.9") and not UpdateService.is_newer("0.3", "0.3"),
		"service is_newer follows boot.gd")
	return true


func _test_install_pack(t) -> bool:
	var pack_file := "tortuga-0.4-linux.pck"
	var old_pack := UPDATES_DIR.path_join("tortuga-0.3-linux.pck")
	var tmp := UPDATES_DIR.path_join("installed.cfg.tmp")
	var part := UPDATES_DIR.path_join(pack_file + ".part")
	var final_pack := UPDATES_DIR.path_join(pack_file)
	var installed := UPDATES_DIR.path_join("installed.cfg")
	DirAccess.make_dir_recursive_absolute(UPDATES_DIR)
	_write_file(old_pack, "old")
	_write_file(tmp, "stale")
	_write_file(part, "probe")

	t.check(not UpdateService.install_pack(part, "0".repeat(64), "0.4", "b1", pack_file, UPDATES_DIR),
		"bad hash is rejected")
	t.check(not FileAccess.file_exists(final_pack) and not FileAccess.file_exists(installed)
			and FileAccess.file_exists(old_pack), "bad hash installs nothing")

	t.check(UpdateService.install_pack(part, "probe".sha256_text(), "0.4", "b1", pack_file, UPDATES_DIR),
		"good hash installs")
	t.check(FileAccess.file_exists(final_pack) and not FileAccess.file_exists(part), "pack renamed from .part")
	var cfg := ConfigFile.new()
	t.check(cfg.load(installed) == OK, "installed.cfg written")
	t.check(cfg.get_value("pack", "version", "") == "0.4" and cfg.get_value("pack", "base", "") == "b1"
			and cfg.get_value("pack", "file", "") == pack_file, "installed.cfg names the new pack")
	t.check(not FileAccess.file_exists(old_pack) and not FileAccess.file_exists(tmp),
		"old pack and installed.cfg.tmp removed")

	# Hash case is ignored, and an existing installed.cfg is replaced.
	_write_file(part, "probe")
	t.check(UpdateService.install_pack(part, "probe".sha256_text().to_upper(), "0.5", "b1", pack_file, UPDATES_DIR),
		"upper-case hash installs over an existing installed.cfg")
	t.check(cfg.load(installed) == OK and cfg.get_value("pack", "version", "") == "0.5",
		"installed.cfg replaced")
	_cleanup()
	return true


func _test_node_dev_build(t) -> bool:
	var service := _new_service(t)
	t.check(service.state == "disabled", "dev build starts disabled")
	if service.state != "disabled":  # a stamped version.cfg must never make this test hit the network
		t.check(false, "res://version.cfg is dev (did a killed build_release.sh leave it stamped?)")
		service.free()
		return true
	service.check()
	service.update_and_restart()
	t.check(service.state == "disabled", "dev build stays disabled after check() and update_and_restart()")
	t.check(service._manifest_http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED
			and service._pack_http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED,
		"dev build makes no request")
	service.free()
	return true


func _test_node_manifest(t) -> bool:
	var service := _new_service(t)
	service.version = "0.3"
	service.base = "b1"
	var seen := []
	service.state_changed.connect(func(new_state: String, new_detail: String) -> void:
		seen.append([new_state, new_detail]))

	_complete_manifest(service, HTTPRequest.RESULT_SUCCESS, 200, _manifest_json("0.4", "b1"))
	t.check(service.state == "available" and service.detail == "0.4", "newer manifest makes an update available")
	t.check(seen.size() == 1 and seen[0] == ["available", "0.4"], "state_changed carries the new state and detail")
	_complete_manifest(service, HTTPRequest.RESULT_SUCCESS, 200, _manifest_json("0.4", "b2"))
	t.check(service.state == "full_download" and service.detail == "0.4", "different base offers a full download")
	_complete_manifest(service, HTTPRequest.RESULT_SUCCESS, 200, _manifest_json("0.3", "b1"))
	t.check(service.state == "up_to_date" and service.detail == "", "same version is up to date")

	_complete_manifest(service, HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	t.check(service.state == "error" and service.detail == UpdateService.CHECK_FAILED, "connection failure is an error")
	_complete_manifest(service, HTTPRequest.RESULT_SUCCESS, 200, _manifest_json("0.4", "b1"))
	_complete_manifest(service, HTTPRequest.RESULT_SUCCESS, 404, _manifest_json("0.4", "b1"))
	t.check(service.state == "error" and service.detail == UpdateService.CHECK_FAILED, "404 is an error")
	_complete_manifest(service, HTTPRequest.RESULT_SUCCESS, 200, "not json")
	t.check(service.state == "error" and service.detail == UpdateService.CHECK_FAILED, "bad JSON is an error")
	service.free()
	return true


## A downloaded file that fails verification ends in an error with nothing installed.
func _test_node_bad_pack(t) -> bool:
	var service := _new_service(t)
	service.version = "0.3"
	service.base = "b1"
	_complete_manifest(service, HTTPRequest.RESULT_SUCCESS, 200, _manifest_json("0.4", "b1"))
	t.check(service.state == "available", "bad pack case starts from an available update")
	var part := UPDATES_DIR.path_join("garbage.pck.part")
	DirAccess.make_dir_recursive_absolute(UPDATES_DIR)
	_write_file(part, "not the pack")
	service._pack_http.download_file = part
	service._on_pack_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), PackedByteArray())
	t.check(service.state == "error" and service.detail == UpdateService.UPDATE_FAILED,
		"pack failing verification is an error")
	t.check(not FileAccess.file_exists(UPDATES_DIR.path_join("installed.cfg")), "failed pack writes no installed.cfg")
	t.check(not FileAccess.file_exists(part), "failed pack removes the .part file")

	# Back to available, so the 404 case's error can't be left over from the case above.
	_complete_manifest(service, HTTPRequest.RESULT_SUCCESS, 200, _manifest_json("0.4", "b1"))
	t.check(service.state == "available", "404 case starts from an available update")
	_write_file(part, "probe")  # matches the manifest hash, so only the status code can fail it
	service._on_pack_completed(HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), PackedByteArray())
	t.check(service.state == "error" and service.detail == UpdateService.UPDATE_FAILED,
		"pack download with a 404 is an error")
	t.check(not FileAccess.file_exists(UPDATES_DIR.path_join("installed.cfg")), "404 pack writes no installed.cfg")
	t.check(not FileAccess.file_exists(part), "404 pack removes the .part file")
	service.free()
	return true


# --- selection menu ---


func _test_menu_dev_build(t) -> bool:
	var main := _new_main(t)
	var sel = main.selection
	t.check(main.update_service.state == "disabled", "main's update service is disabled in the dev build")
	t.check(sel.version_label.text == "Development build", "dev build shows Development build")
	t.check(sel.check_updates_button.visible and sel.check_updates_button.disabled, "dev build: Check is shown but disabled")
	t.check(not sel.update_button.visible and not sel.full_download_button.visible,
		"dev build hides Update and Restart and Download full update")
	t.check(not sel.update_status_label.visible, "dev build has no update status")
	sel.show_version("0.7")
	t.check(sel.version_label.text == "Tortuga 0.7", "released build shows its version")
	sel.show_version("dev")
	t.check(sel.version_label.text == "Development build", "dev version shows Development build")
	main.free()
	return true


func _test_menu_wiring(t) -> bool:
	var main := _new_main(t)
	var sel = main.selection
	var service = main.update_service
	t.check(service.get_parent() == main and service.name == "UpdateService", "main owns the UpdateService child")
	t.check(service.state_changed.is_connected(sel.show_update_state), "state_changed drives the menu")
	t.check(sel.check_updates_requested.is_connected(service.check), "Check button signal runs check()")
	t.check(sel.update_requested.is_connected(service.update_and_restart), "Update signal runs update_and_restart()")
	t.check(sel.full_download_requested.get_connections().size() == 1, "full download signal has one handler")
	t.check(sel.check_updates_button.pressed.is_connected(sel.check_updates_requested.emit)
			and sel.update_button.pressed.is_connected(sel.update_requested.emit)
			and sel.full_download_button.pressed.is_connected(sel.full_download_requested.emit),
		"buttons emit the menu's signals")
	var order := [sel.quit_button, sel.check_updates_button, sel.update_button, sel.full_download_button]
	var chained := true
	for i in order.size() - 1:
		chained = chained and order[i].focus_next == order[i].get_path_to(order[i + 1])
	t.check(chained and sel.full_download_button.focus_next == sel.full_download_button.get_path_to(sel.sailing_button),
		"update buttons follow Quit in the focus chain and wrap to the first mode")
	main.free()
	return true


func _test_menu_states(t) -> bool:
	var main := _new_main(t)
	var sel = main.selection
	var locked := _locked_buttons(sel)

	_emit_state(main, "checking")
	t.check(sel.update_status_label.visible and sel.update_status_label.text == "Checking for updates…",
		"checking shows its status")
	t.check(sel.check_updates_button.disabled and not sel.update_button.visible, "checking disables Check")

	_emit_state(main, "available", "0.9")
	t.check(sel.update_status_label.visible and sel.update_status_label.text == "Version 0.9 is available.",
		"available shows the new version")
	t.check(sel.update_button.visible and not sel.update_button.disabled and sel.update_button.text == "Update and Restart",
		"available shows Update and Restart")
	t.check(not sel.full_download_button.visible and not sel.check_updates_button.disabled,
		"available hides the full download and keeps Check enabled")

	_emit_state(main, "full_download", "0.9")
	t.check(sel.update_status_label.text == "Version 0.9 is available.", "full_download shows the new version")
	t.check(sel.full_download_button.visible and sel.full_download_button.text == "Download full update"
			and not sel.update_button.visible, "full_download shows only Download full update")

	_emit_state(main, "downloading", "42")
	t.check(sel.update_status_label.text == "Downloading update… 42%", "downloading shows the percent")
	t.check(sel.update_button.visible and sel.update_button.disabled and sel.check_updates_button.disabled
			and not sel.full_download_button.visible, "downloading disables Update and Check")
	t.check(_all_disabled(locked), "downloading disables the mode and Settings buttons")
	t.check(not sel.quit_button.disabled, "downloading leaves Quit enabled")

	_emit_state(main, "up_to_date")
	t.check(sel.update_status_label.text == "You're up to date.", "up_to_date says so")
	t.check(not sel.update_button.visible and not sel.full_download_button.visible, "up_to_date hides both update buttons")
	t.check(not sel.check_updates_button.disabled and _all_enabled(locked), "up_to_date re-enables everything")

	_emit_state(main, "downloading", "7")
	_emit_state(main, "error", "Update failed. Try again.")
	t.check(sel.update_status_label.visible and sel.update_status_label.text == "Update failed. Try again.",
		"error shows its detail")
	t.check(not sel.update_button.visible and not sel.full_download_button.visible, "error hides both update buttons")
	t.check(not sel.check_updates_button.disabled and _all_enabled(locked),
		"error re-enables Check, the mode buttons and Settings")

	for state in ["idle", "disabled"]:
		_emit_state(main, "available", "0.9")
		_emit_state(main, state)
		t.check(not sel.update_status_label.visible and sel.update_status_label.text == "",
			"%s clears the status" % state)
		t.check(not sel.update_button.visible and not sel.full_download_button.visible,
			"%s hides both update buttons" % state)
		t.check(sel.check_updates_button.disabled == (state == "disabled"), "%s sets Check accordingly" % state)
	main.free()
	return true


## Focus never stays on a button a state change just hid.
func _test_menu_focus(t) -> bool:
	var main := _new_main(t)
	var sel = main.selection
	_emit_state(main, "available", "0.9")
	sel.update_button.grab_focus()
	t.check(sel.update_button.has_focus(), "Update and Restart can take focus")
	_emit_state(main, "downloading", "10")
	t.check(sel.update_button.has_focus(), "focus stays while the button is merely disabled")
	_emit_state(main, "error", "Update failed. Try again.")
	t.check(sel.check_updates_button.has_focus(), "focus moves to Check when Update and Restart is hidden")

	_emit_state(main, "full_download", "0.9")
	sel.full_download_button.grab_focus()
	_emit_state(main, "up_to_date")
	t.check(sel.check_updates_button.has_focus(), "focus moves to Check when Download full update is hidden")

	sel.settings_button.grab_focus()
	_emit_state(main, "available", "0.9")
	_emit_state(main, "error", "x")
	t.check(sel.settings_button.has_focus(), "other focus is left alone")
	main.free()
	return true


## The update controls live on the mode screen, not on the vessel screen or during play.
func _test_menu_mode_screen_only(t) -> bool:
	var main := _new_main(t)
	var sel = main.selection
	t.check(sel.check_updates_button.is_visible_in_tree(), "Check is visible on the mode screen")
	sel.sailing_button.pressed.emit()
	t.check(not sel.check_updates_button.is_visible_in_tree() and not sel.version_label.is_visible_in_tree(),
		"vessel screen has no update controls")
	sel.back_button.pressed.emit()
	t.check(sel.check_updates_button.is_visible_in_tree(), "Back returns to the update controls")
	main.start_practice("sloop")
	t.check(not sel.check_updates_button.is_visible_in_tree(), "Check is not visible while sailing")
	main.free()
	return true


## The update block is two compact rows, so the mode panel still fits a 720 px-high viewport
## (a taller panel grows past the bottom edge and hides Update and Restart).
func _test_menu_fits_screen(t) -> bool:
	var main := _new_main(t)
	var sel = main.selection
	var panel: Control = sel._mode_screen.get_child(0)
	var limit: float = main.get_viewport().get_visible_rect().size.y
	t.check(limit == 720.0, "test viewport is 720 px high")
	for case in [["disabled", ""], ["available", "0.9"], ["full_download", "0.9"], ["downloading", "42"],
			["error", UpdateService.CHECK_FAILED]]:
		_emit_state(main, case[0], case[1])
		var height := panel.get_combined_minimum_size().y
		t.check(height <= limit, "mode panel fits the viewport in %s (%s of %s px)" % [case[0], height, limit])
	t.check(sel.version_label.get_parent() == sel.update_status_label.get_parent()
			and sel.check_updates_button.get_parent() == sel.update_button.get_parent()
			and sel.check_updates_button.get_parent() == sel.full_download_button.get_parent()
			and sel.version_label.get_parent() != sel.check_updates_button.get_parent(),
		"version and status share one row, the three buttons another")
	var shared := true
	for button in [sel.check_updates_button, sel.update_button, sel.full_download_button]:
		shared = shared and button.custom_minimum_size == Vector2(0, 48) \
				and button.size_flags_horizontal == Control.SIZE_EXPAND_FILL
	t.check(shared and sel.update_status_label.size_flags_horizontal == Control.SIZE_EXPAND_FILL,
		"row buttons and the status label share the width")
	main.free()
	return true
