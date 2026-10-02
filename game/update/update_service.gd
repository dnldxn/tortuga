extends Node
## Pack updater. On request it fetches the release manifest, downloads and verifies the newer
## pack into user://updates/, then restarts into it. Disabled in "dev" builds; never runs at startup.

const Boot := preload("res://boot.gd")

const MANIFEST_URL := "https://github.com/dnldxn/tortuga/releases/latest/download/update.json"
const PACK_URL := "https://github.com/dnldxn/tortuga/releases/download/v%s/%s"
const RELEASES_URL := "https://github.com/dnldxn/tortuga/releases/latest"
const UPDATES_DIR := Boot.UPDATES_DIR
const CHECK_FAILED := "Couldn't check for updates."
const UPDATE_FAILED := "Update failed. Try again."

signal state_changed(state: String, detail: String)

## idle | disabled | checking | up_to_date | available | full_download | downloading | error
var state := "idle"
## New version (available, full_download), percent (downloading) or error message (error).
var detail := ""
var version := "dev"
var base := "dev"

var _manifest_http: HTTPRequest
var _pack_http: HTTPRequest
var _update := {}  # decide() result for the latest manifest


func _ready() -> void:
	var build := ConfigFile.new()
	if build.load(Boot.VERSION_CFG) == OK:
		version = str(build.get_value("build", "version", "dev"))
		base = str(build.get_value("build", "base", "dev"))
	_manifest_http = _add_request("ManifestRequest", 30.0, _on_manifest_completed)
	_pack_http = _add_request("PackRequest", 300.0, _on_pack_completed)
	_set_state("disabled" if version == "dev" else "idle", "")


func _process(_delta: float) -> void:
	if state != "downloading":
		return
	var total := _pack_http.get_body_size()  # -1 until headers arrive
	if total <= 0:
		return
	var percent := str(int(100.0 * _pack_http.get_downloaded_bytes() / total))
	if percent != detail:
		_set_state("downloading", percent)


## Fetches the manifest. No-op in dev builds and while a check or download is running.
func check() -> void:
	if state in ["disabled", "checking", "downloading"]:
		return
	_set_state("checking", "")
	if _manifest_http.request(MANIFEST_URL) != OK:
		_set_state("error", CHECK_FAILED)


## Downloads, verifies and installs the available pack, then quits so the OS restarts the game.
func update_and_restart() -> void:
	if state != "available":
		return
	DirAccess.make_dir_recursive_absolute(UPDATES_DIR)
	_pack_http.download_file = UPDATES_DIR.path_join(_update["file"] + ".part")
	if _pack_http.request(PACK_URL % [_update["version"], _update["file"]]) == OK:
		_set_state("downloading", "0")
	else:
		_set_state("error", UPDATE_FAILED)


## Returns the manifest if it is valid, else {}.
static func parse_manifest(text: String) -> Dictionary:
	var json := JSON.new()  # unlike JSON.parse_string, a bad document prints no engine error
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	var manifest: Dictionary = json.data
	if not (manifest.get("version") is String and manifest.get("base") is String and manifest.get("packs") is Dictionary):
		return {}
	for pack in manifest["packs"].values():
		if not (pack is Dictionary and pack.get("file") is String and pack.get("sha256") is String
				and pack["file"].get_file() == pack["file"]):
			return {}
	return manifest


static func is_newer(a: String, b: String) -> bool:
	return Boot.is_newer(a, b)


## "windows", "macos" or "linux"; "" on other platforms.
static func platform_key() -> String:
	return {"Windows": "windows", "macOS": "macos", "Linux": "linux"}.get(OS.get_name(), "")


## What a build should do about a valid manifest: {state: up_to_date}, {state: full_download,
## version} (other base or no pack for the platform) or {state: update, version, file, sha256}.
static func decide(manifest: Dictionary, build_version: String, build_base: String, platform: String) -> Dictionary:
	var latest: String = manifest["version"]
	if not is_newer(latest, build_version):
		return {"state": "up_to_date"}
	var pack: Dictionary = manifest["packs"].get(platform, {})
	if manifest["base"] != build_base or pack.is_empty():
		return {"state": "full_download", "version": latest}
	return {"state": "update", "version": latest, "file": pack["file"], "sha256": pack["sha256"]}


## Verifies the downloaded .part, renames it to `file`, points installed.cfg at it (written via
## .tmp), then drops every other file in `updates_dir`. False on a hash mismatch or any failed
## step before cleanup; cleanup failures are ignored (Windows holds the running pack open).
static func install_pack(part_path: String, sha256: String, pack_version: String, pack_base: String,
		file: String, updates_dir: String) -> bool:
	if FileAccess.get_sha256(part_path) != sha256.to_lower():
		return false
	if DirAccess.rename_absolute(part_path, updates_dir.path_join(file)) != OK:
		return false
	var cfg := ConfigFile.new()
	cfg.set_value("pack", "version", pack_version)
	cfg.set_value("pack", "base", pack_base)
	cfg.set_value("pack", "file", file)
	var tmp := updates_dir.path_join("installed.cfg.tmp")
	if cfg.save(tmp) != OK or DirAccess.rename_absolute(tmp, updates_dir.path_join("installed.cfg")) != OK:
		return false
	for other in DirAccess.get_files_at(updates_dir):
		if other != file and other != "installed.cfg":
			DirAccess.remove_absolute(updates_dir.path_join(other))
	return true


func _add_request(node_name: String, timeout: float, on_completed: Callable) -> HTTPRequest:
	var request := HTTPRequest.new()
	request.name = node_name
	request.timeout = timeout
	request.request_completed.connect(on_completed)
	add_child(request)
	return request


func _set_state(new_state: String, new_detail: String) -> void:
	state = new_state
	detail = new_detail
	state_changed.emit(new_state, new_detail)


func _on_manifest_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var manifest := {}
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		manifest = parse_manifest(body.get_string_from_utf8())
	if manifest.is_empty():
		_set_state("error", CHECK_FAILED)
		return
	_update = decide(manifest, version, base, platform_key())
	var decided: String = _update["state"]
	_set_state("available" if decided == "update" else decided, _update.get("version", ""))


func _on_pack_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var part := _pack_http.download_file
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not install_pack(
			part, _update["sha256"], _update["version"], base, _update["file"], UPDATES_DIR):
		DirAccess.remove_absolute(part)
		_set_state("error", UPDATE_FAILED)
		return
	OS.set_restart_on_exit(true)  # desktop only; no effect when run from the editor
	get_tree().quit()
