extends Node
## Main scene: overlays the installed update pack, then loads the game.
## Preloads nothing from the game. Part of the base ID: edits force a full download.

const VERSION_CFG := "res://version.cfg"
const UPDATES_DIR := "user://updates"


func _ready() -> void:
	load_installed_pack(VERSION_CFG, UPDATES_DIR)
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")


## Loads installed.cfg's pack if the build isn't "dev", bases match, it is newer and exists.
static func load_installed_pack(version_cfg_path: String, updates_dir: String) -> bool:
	var build := ConfigFile.new()
	var pack := ConfigFile.new()
	var cfg_path := updates_dir.path_join("installed.cfg")
	if build.load(version_cfg_path) != OK or pack.load(cfg_path) != OK:
		return false
	var version := str(build.get_value("build", "version", "dev"))
	var path := updates_dir.path_join(str(pack.get_value("pack", "file", "")))
	if version == "dev" or str(pack.get_value("pack", "base", "")) != str(build.get_value("build", "base", "")) \
			or not is_newer(str(pack.get_value("pack", "version", "")), version) \
			or not FileAccess.file_exists(path):
		return false
	if not ProjectSettings.load_resource_pack(path):
		DirAccess.remove_absolute(cfg_path)
		return false
	return true


## Compares dotted versions as integers: "0.10" is newer than "0.9".
static func is_newer(a: String, b: String) -> bool:
	var x := a.split(".")
	var y := b.split(".")
	for i in maxi(x.size(), y.size()):
		var p := x[i].to_int() if i < x.size() else 0
		var q := y[i].to_int() if i < y.size() else 0
		if p != q:
			return p > q
	return false
