extends Node
## Dedicated server entry (`-- --server`): a verbose SessionServer child that polls in _process
## and ticks in _physics_process. Options come from the CLI, else the environment.
## SIGTERM kills Godot at once and SIGINT is ignored (GDScript sees neither), so a graceful stop
## is requested through a stop file: once it appears, or its mtime changes, the server tells every
## client, stops (<= 1 s) and exits 0. The server never writes or deletes that file.
## Exit codes: 0 stopped, 1 cannot listen, 2 bad options.

const Protocol := preload("res://net/protocol.gd")
const Definitions := preload("res://sim/definitions.gd")
const SessionServer := preload("res://net/session_server.gd")

const STOP_CHECK_MS := 500

var _session: Node = null
var _stop_file := ""
var _stop_mtime := -1
var _next_check_ms := 0


## {"port": int, "password", "stop_file", "error"}; `error` is "" when the options are usable.
static func server_options(cli: Dictionary, env_password: String, env_port: String) -> Dictionary:
	var out := {"port": 0, "password": "", "stop_file": "", "error": ""}
	if cli.get("stop-file") is String:
		out["stop_file"] = cli["stop-file"]
	var port_text := str(cli["port"]) if cli.has("port") else env_port
	if port_text == "":
		out["error"] = "port required (--port or TORTUGA_SERVER_PORT)"
		return out
	if not port_text.is_valid_int() or port_text.to_int() < 1 or port_text.to_int() > 65535:
		out["error"] = "bad port %s" % port_text
		return out
	out["port"] = port_text.to_int()
	out["password"] = cli["password"] if cli.get("password") is String else env_password
	if out["password"] == "":
		out["error"] = "password required (--password or TORTUGA_SERVER_PASSWORD)"
	return out


## True when `path` exists with an mtime other than `seen_mtime` (-1 = it did not exist at start).
static func stop_requested(path: String, seen_mtime: int) -> bool:
	return path != "" and FileAccess.file_exists(path) and FileAccess.get_modified_time(path) != seen_mtime


func _ready() -> void:
	Engine.max_fps = 60  # physics queues sends; the same frame's _process poll flushes them
	var opts := server_options(Protocol.parse_cli(OS.get_cmdline_user_args()),
		OS.get_environment("TORTUGA_SERVER_PASSWORD"), OS.get_environment("TORTUGA_SERVER_PORT"))
	if opts["error"] != "":
		print("SRV error %s" % opts["error"])
		get_tree().quit(2)
		return
	_stop_file = opts["stop_file"]
	if _stop_file != "" and FileAccess.file_exists(_stop_file):
		_stop_mtime = FileAccess.get_modified_time(_stop_file)
	_session = SessionServer.new()
	_session.name = "SessionServer"
	_session.verbose = true
	add_child(_session)
	var err: Error = _session.start(opts["port"], opts["password"], Protocol.build_version())
	if err != OK:
		print("SRV error cannot listen on UDP %d (error %d)" % [opts["port"], err])
		get_tree().quit(1)
		return
	print("SRV listening port=%d version=%s max_captains=%d max_battles=%d" % [opts["port"],
		Protocol.build_version(), Definitions.MAX_CAPTAINS, Definitions.MAX_BATTLES])
	_next_check_ms = Time.get_ticks_msec() + STOP_CHECK_MS


func _process(_d: float) -> void:
	if _session == null or not _session.is_active() or Time.get_ticks_msec() < _next_check_ms:
		return
	_next_check_ms = Time.get_ticks_msec() + STOP_CHECK_MS
	if stop_requested(_stop_file, _stop_mtime):
		print("SRV stopping reason=stop-file")
		_session.stop()
		get_tree().quit(0)
