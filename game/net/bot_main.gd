extends Node
## Headless bot client (`-- --bot`) for smoke, load and soak runs: a SessionClient child that
## starts (default), joins (--join) or idles in the harbor (--idle); --loop re-enters after each
## battle end; --seconds S leaves, waits for the final harbor and disconnects after S s connected.
## While its ship is active it steers a fixed pattern and fires alternate broadsides.
## Prints one "BOT summary" line on every exit. Exit 0: battle end without --loop, --seconds
## reached, or server_stopped; 1: anything else.

const Protocol := preload("res://net/protocol.gd")
const Definitions := preload("res://sim/definitions.gd")
const SessionClient := preload("res://net/session_client.gd")

const JOIN_WAIT_MS := 10000
const LEAVE_WAIT_MS := 2000
const STEER_PATTERN: Array[int] = [1, 0, -1, 0]
const STEER_PHASE_S := 2.0
const FIRE_EVERY_S := 1.5
const CYCLE_EVERY_S := 15.0

var _opts := {}
var _client: Node = null
var _start_ms := 0
var _connected_ms := -1
var _battle := 0           # the battle this bot is in (until its result, or its own escape/abandon)
var _joined_ms := 0
var _next_fire_s := FIRE_EVERY_S
var _fires := 0
var _next_cycle_s := CYCLE_EVERY_S
var _want_enter := false   # start or join on the next frame (not inside a signal handler)
var _seek_ms := -1         # --join: waiting for a joinable battle since
var _leave_ms := -1        # --seconds: waiting for the final harbor since
var _results := 0
var _snapshots := 0
var _events := 0
var _harbor := {}          # the latest harbor (cleared at a battle end: wait for a fresh one)
var _rtt_ms := 0.0
var _done := false
var _exit_code := 0


## Defaults merged with the CLI ("--captain-id" → "captain_id"); `error` is "" when usable.
static func bot_options(cli: Dictionary) -> Dictionary:
	var out := {"host": "127.0.0.1", "port": Protocol.DEFAULT_PORT, "password": "", "name": "Bot",
		"captain_id": "", "preset": "duel_sloop", "vessel": "sloop", "join": cli.has("join"),
		"loop": cli.has("loop"), "idle": cli.has("idle"), "seconds": 0.0, "error": ""}
	for key in ["host", "password", "name", "preset", "vessel"]:
		if cli.get(key) is String:
			out[key] = cli[key]
	out["captain_id"] = cli["captain-id"] if cli.get("captain-id") is String else "bot-" + out["name"]
	if cli.has("port"):
		var port := str(cli["port"])
		if port.is_valid_int() and port.to_int() >= 1 and port.to_int() <= 65535:
			out["port"] = port.to_int()
		else:
			out["error"] = "bad port %s" % port
	if cli.has("seconds"):
		var seconds := str(cli["seconds"])
		if seconds.is_valid_float() and seconds.to_float() >= 0.0:
			out["seconds"] = seconds.to_float()
		else:
			out["error"] = "bad seconds %s" % seconds
	if not out["preset"] in Definitions.BATTLE_PRESETS:
		out["error"] = "unknown preset %s" % out["preset"]
	if not Definitions.VESSELS.has(out["vessel"]):
		out["error"] = "unknown vessel %s" % out["vessel"]
	return out


func _ready() -> void:
	Engine.max_fps = 60  # sends queued in _process are flushed by the child's poll the same frame
	_start_ms = Time.get_ticks_msec()
	_opts = bot_options(Protocol.parse_cli(OS.get_cmdline_user_args()))
	if _opts["error"] != "":
		print("BOT error %s" % _opts["error"])
		_finish(1)
		return
	_client = SessionClient.new()
	_client.name = "SessionClient"
	add_child(_client)
	_client.auth_refused.connect(_on_auth_refused)
	_client.connected_ok.connect(_on_connected_ok)
	_client.harbor_changed.connect(_on_harbor_changed)
	_client.joined.connect(_on_joined)
	_client.snapshot_received.connect(func(_s): _snapshots += 1)
	_client.events_received.connect(func(_b, events): _events += events.size())
	_client.outcome.connect(_on_outcome)
	_client.battle_result.connect(_on_battle_result)
	_client.refused.connect(_on_refused)
	_client.connection_ended.connect(_on_connection_ended)
	var err: Error = _client.connect_to(_opts["host"], _opts["port"], _opts["name"], _opts["password"],
		_opts["captain_id"])
	if err != OK:
		print("BOT error cannot connect to %s:%d (error %d)" % [_opts["host"], _opts["port"], err])
		_finish(1)


func _process(_d: float) -> void:
	if _done or _client == null:
		return
	var now := Time.get_ticks_msec()
	if _client.status == "connected":
		var rtt: float = _client.net_stats()["rtt_ms"]
		if rtt > 0.0:
			_rtt_ms = rtt
	if _leave_ms >= 0:
		if now - _leave_ms >= LEAVE_WAIT_MS:
			_finish(0)
		return
	if _opts["seconds"] > 0.0 and _connected_ms >= 0 and now - _connected_ms >= _opts["seconds"] * 1000.0:
		if _client.battle_id != 0:
			_client.leave_battle()
		_battle = 0
		_leave_ms = now
		return
	if _want_enter:
		_want_enter = false
		if _opts["join"]:
			_seek_ms = now
			_try_join()
		else:
			_client.start_battle(_opts["preset"], _opts["vessel"])
	if _seek_ms >= 0 and now - _seek_ms > JOIN_WAIT_MS:
		print("BOT error no joinable battle within %d s" % (JOIN_WAIT_MS / 1000))
		_finish(1)
		return
	if _client.ship_active:
		var t := (now - _joined_ms) / 1000.0
		_client.set_steer(STEER_PATTERN[int(t / STEER_PHASE_S) % STEER_PATTERN.size()])
		if t >= _next_fire_s:
			_client.send_action("fire_port" if _fires % 2 == 0 else "fire_starboard")
			_fires += 1
			_next_fire_s += FIRE_EVERY_S
		if t >= _next_cycle_s:
			_client.send_action("cycle_port")
			_next_cycle_s += CYCLE_EVERY_S


func _on_auth_refused(reason: String, server_version: String) -> void:
	print("BOT refused auth reason=%s server_version=%s client_version=%s" % [reason, server_version,
		_client.version])
	_finish(1)


func _on_connected_ok(slot: int) -> void:
	print("BOT connected name=%s slot=%d version=%s" % [_opts["name"], slot, _client.server_version])
	_connected_ms = Time.get_ticks_msec()
	_want_enter = not _opts["idle"]


func _on_harbor_changed(harbor: Dictionary) -> void:
	if _leave_ms >= 0:
		for c in harbor.get("captains", []):
			if c.get("slot") == _client.slot and c.get("battle_id") == 0:
				_finish(0)  # the final harbor: actions_applied is the server's last count
				return
		return
	_harbor = harbor
	_try_join()


## --join: joins the lowest-id joinable battle of the latest harbor, if seeking.
func _try_join() -> void:
	if _seek_ms < 0:
		return
	var ids := []
	for b in _harbor.get("battles", []):
		if b.get("can_join") == true:
			ids.append(int(b.get("battle_id", 0)))
	if not ids.is_empty():
		ids.sort()
		_seek_ms = -1
		_client.join_battle(ids[0], _opts["vessel"])


func _on_joined(info: Dictionary) -> void:
	_battle = int(info.get("battle_id", 0))
	_joined_ms = Time.get_ticks_msec()
	_next_fire_s = FIRE_EVERY_S
	_fires = 0
	_next_cycle_s = CYCLE_EVERY_S
	print("BOT joined battle=%d ship=%d preset=%s" % [_battle, int(info.get("ship_id", 0)), info.get("preset_id", "")])


func _on_outcome(info: Dictionary) -> void:
	var id := int(info.get("battle_id", 0))
	var result: String = str(info.get("outcome", ""))
	print("BOT outcome battle=%d ship=%d outcome=%s" % [id, int(info.get("ship_id", 0)), result])
	# After its own defeat it spectates until battle_result; escaping/abandoning ends its battle.
	if id == _battle and (result == "escaped" or result == "abandoned"):
		_battle_ended()


func _on_battle_result(id: int, result: Dictionary) -> void:
	_results += 1
	print("BOT result battle=%d outcome=%s elapsed=%.2f hash=%s" % [id, result.get("outcome", ""),
		float(result.get("elapsed", 0.0)), Protocol.result_hash(result)])
	if id == _battle:
		_battle_ended()


func _battle_ended() -> void:
	_battle = 0
	_harbor = {}
	if _leave_ms >= 0:
		return
	if _opts["loop"]:
		_want_enter = true
	else:
		_finish(0)


func _on_refused(reason: String) -> void:
	print("BOT refused reason=%s" % reason)
	_finish(1)


func _on_connection_ended(reason: String) -> void:
	print("BOT ended reason=%s" % reason)
	_finish(0 if reason == "server_stopped" else 1)


## Exactly once: a graceful disconnect, then (deferred, after the client's poll has closed and
## counted the last traffic) the summary line and quit(code).
func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	_exit_code = code
	if _client != null:
		_client.disconnect_from()  # inside a signal handler: closes once poll() returns
	_summary_and_quit.call_deferred()


func _summary_and_quit() -> void:
	var stats := {"bytes_in": 0, "bytes_out": 0, "packets_in": 0, "packets_out": 0}
	var counts := {"actions_sent": 0, "actions_applied": 0, "disconnects": 0}
	if _client != null:
		_client.disconnect_from()  # no-op once closed
		stats = _client.net_stats()
		counts = {"actions_sent": _client.actions_sent, "actions_applied": _client.actions_applied,
			"disconnects": _client.disconnects}
	print("BOT summary name=%s exit=%d seconds=%.1f results=%d snapshots=%d events=%d actions_sent=%d actions_applied=%d disconnects=%d bytes_in=%d bytes_out=%d packets_in=%d packets_out=%d rtt_ms=%d" % [
		_opts.get("name", "Bot"), _exit_code, (Time.get_ticks_msec() - _start_ms) / 1000.0, _results,
		_snapshots, _events, counts["actions_sent"], counts["actions_applied"], counts["disconnects"],
		stats["bytes_in"], stats["bytes_out"], stats["packets_in"], stats["packets_out"], roundi(_rtt_ms)])
	get_tree().quit(_exit_code)
