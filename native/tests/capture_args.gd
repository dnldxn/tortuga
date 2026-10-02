extends SceneTree
# Launcher handoff probe (Linux): records Godot's PID, executable path, raw
# /proc/self/cmdline and OS.get_cmdline_user_args() to $TORTUGA_CAPTURE_OUT.
# Run with --script <absolute path>; never shipped in a package.


func _init() -> void:
	var out := OS.get_environment("TORTUGA_CAPTURE_OUT")
	var src := FileAccess.open("/proc/self/cmdline", FileAccess.READ)
	var raw := PackedByteArray()
	while not src.eof_reached():
		raw.append_array(src.get_buffer(4096))
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("%d\n%s\n" % [OS.get_process_id(), OS.get_executable_path()])
	f.store_buffer(raw)
	f.close()
	var u := FileAccess.open(out + ".user", FileAccess.WRITE)
	for a in OS.get_cmdline_user_args():
		u.store_buffer(a.to_utf8_buffer())
		u.store_8(0)
	u.close()
	quit(0)
