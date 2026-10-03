extends Node
## Session client (Phase 3 plan 02). Owns its own SceneMultiplayer + ENet client and polls itself,
## so several can run in one process outside the SceneTree. No socket exists before connect_to().
## Connection endings found inside _mp.poll() are only recorded there and acted on afterwards:
## closing the peer inside its own poll is unsafe.

signal auth_refused(reason: String, server_version: String)
signal connected_ok(slot: int)
signal harbor_changed(harbor: Dictionary)
signal joined(info: Dictionary)
signal snapshot_received(snapshot: Dictionary)
signal events_received(battle_id: int, events: Array)
signal outcome(info: Dictionary)
signal battle_result(battle_id: int, result: Dictionary)
signal refused(reason: String)
signal connection_ended(reason: String)  # server_stopped | connection_lost | replaced

const Protocol := preload("res://net/protocol.gd")

var version := Protocol.build_version()
var connect_timeout_ms := Protocol.CONNECT_TIMEOUT_MS
var status := "offline"   # offline | connecting | connected
var slot := -1
var server_version := ""
var battle_id := 0        # from joined until result/leave/own escape or abandon
var ship_id := 0
var ship_active := false  # false after any own outcome
var actions_sent := 0
var actions_applied := 0  # server's count (harbor field)
var disconnects := 0

var _enet: ENetMultiplayerPeer = null
var _mp: SceneMultiplayer = null
var _hello := {}
var _connect_ms := 0
var _pending_refusal := {}  # {"reason", "server_version"} from a refused hello
var _pending_end := false   # the connection went away during _mp.poll()
var _end_reason := ""       # set by server_stopping / replaced
var _polling := false
var _close_requested := false  # disconnect_from() called during _mp.poll()
var _stats := {"bytes_in": 0, "bytes_out": 0, "packets_in": 0, "packets_out": 0}


func net_stats() -> Dictionary:
	var out := _stats.duplicate()
	var live := _enet != null and _enet.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED
	var peer := _enet.get_peer(1) if live else null
	out["rtt_ms"] = peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if peer != null else 0.0
	out["packet_loss"] = peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / 65536.0 if peer != null else 0.0
	out["disconnects"] = disconnects
	return out


func connect_to(host: String, port: int, captain_name: String, password: String, captain_id: String) -> Error:
	if _polling:
		return ERR_BUSY  # not from a signal handler inside poll()
	disconnect_from()
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(host, port, 1)
	if err != OK:
		return err
	enet.get_peer(1).set_timeout(Protocol.TIMEOUT_LIMIT, Protocol.TIMEOUT_MIN_MS, Protocol.TIMEOUT_MAX_MS)
	# Plan 05 ENet knobs (throttle_configure / bandwidth limits) would sit here.
	var mp := SceneMultiplayer.new()
	mp.root_path = NodePath("/root")  # without it every send_bytes packet is dropped
	mp.auth_callback = _on_auth
	mp.peer_authenticating.connect(_on_peer_authenticating)
	mp.connected_to_server.connect(_on_connected_to_server)
	mp.server_disconnected.connect(_on_connection_gone)
	mp.connection_failed.connect(_on_connection_gone)
	mp.peer_packet.connect(_on_peer_packet)
	mp.multiplayer_peer = enet
	_enet = enet
	_mp = mp
	_hello = {"version": version, "password": password, "captain_id": captain_id, "name": captain_name}
	_connect_ms = Time.get_ticks_msec()
	status = "connecting"
	slot = -1
	server_version = ""
	return OK


func start_battle(_preset_id: String, _vessel_id: String) -> void:
	pass  # Task 4


func join_battle(_id: int, _vessel_id: String) -> void:
	pass  # Task 4


func leave_battle() -> void:
	pass  # Task 4


func send_action(_action: String) -> bool:
	return false  # Task 4


func set_steer(_turn: int) -> void:
	pass  # Task 4


## Graceful ENet close; emits nothing. From a signal handler inside poll() it waits for poll's end.
func disconnect_from() -> void:
	if _polling:
		_close_requested = true
	else:
		_close()


func poll() -> void:
	if _mp == null:
		return
	_polling = true
	_mp.poll()
	_polling = false
	if _close_requested:
		_close()
		return
	_collect_stats()
	if not _pending_refusal.is_empty():
		var refusal := _pending_refusal
		_close()
		auth_refused.emit(refusal["reason"], refusal["server_version"])
		return
	if status == "connecting" and Time.get_ticks_msec() - _connect_ms > connect_timeout_ms:
		_pending_end = true
	if _pending_end:
		var reason := _end_reason if _end_reason != "" else "connection_lost"
		_close()
		disconnects += 1
		connection_ended.emit(reason)


func _process(_d: float) -> void:
	poll()


func _close() -> void:
	if _enet != null:
		_collect_stats()
		_enet.close()  # no-op once ENet closed itself
		_mp.multiplayer_peer = null
	_enet = null
	_mp = null
	status = "offline"
	battle_id = 0
	ship_id = 0
	ship_active = false
	_pending_refusal = {}
	_pending_end = false
	_end_reason = ""
	_close_requested = false


func _collect_stats() -> void:
	if _enet == null or _enet.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return  # ENet closes a client itself once the server is gone
	var host := _enet.host
	_stats["bytes_in"] += host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	_stats["bytes_out"] += host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	_stats["packets_in"] += host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
	_stats["packets_out"] += host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)


# --- callbacks (inside _mp.poll) -------------------------------------------------------------

func _on_peer_authenticating(peer: int) -> void:
	if peer == 1:
		_mp.send_auth(1, var_to_bytes(_hello))


func _on_auth(_peer: int, data: PackedByteArray) -> void:
	var reply = bytes_to_var(data) if not data.is_empty() else null
	if not (reply is Dictionary) or not (reply.get("ok") is bool):
		return
	if reply["ok"]:
		slot = int(reply.get("slot", -1))
		server_version = str(reply.get("server_version", ""))
		_mp.complete_auth(1)
	else:
		server_version = str(reply.get("server_version", ""))
		_pending_refusal = {"reason": str(reply.get("reason", "")), "server_version": server_version}


func _on_connected_to_server() -> void:
	status = "connected"
	actions_sent = 0
	actions_applied = 0
	connected_ok.emit(slot)


func _on_connection_gone() -> void:
	_pending_end = true


func _on_peer_packet(_peer: int, packet: PackedByteArray) -> void:
	if packet.is_empty() or packet[0] != Protocol.KIND_MESSAGE:
		return  # snapshots: Task 4
	var msg := Protocol.decode_message(packet)
	match msg.get("t", ""):
		"harbor":
			actions_applied = int(msg.get("actions_applied", 0))
			harbor_changed.emit(msg)
		"server_stopping":
			_end_reason = "server_stopped"
		"replaced":
			_end_reason = "replaced"
