extends Node
## Authoritative session server (Phase 3 plan 02). Owns its own SceneMultiplayer + ENet host and
## polls itself, so it works outside the SceneTree. No RPCs: Protocol packets via send_bytes.
## poll() receives, dispatches and flushes the harbor; advance_tick() steps battles (Task 4).

const Protocol := preload("res://net/protocol.gd")
const Definitions := preload("res://sim/definitions.gd")
const Battle := preload("res://net/battle.gd")

const AUTH_TIMEOUT_S := 3.0

var battles := {}       # battle_id -> Battle (ids from 1, never reused)
var captains := {}      # peer_id -> captain record (reserved at auth OK, connected at peer_connected)
var verbose := false    # prints the SRV lines

var _enet: ENetMultiplayerPeer = null
var _mp: SceneMultiplayer = null
var _password := ""
var _version := ""
var _harbor_dirty := false
var _next_battle_id := 1
var _ticks := 0


func start(port: int, password: String, version: String) -> Error:
	stop(0)
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, Protocol.MAX_PEERS, 1)
	if err != OK:
		return err
	var mp := SceneMultiplayer.new()
	mp.root_path = NodePath("/root")  # without it every send_bytes packet is dropped
	mp.server_relay = false
	mp.auth_callback = _on_auth
	mp.auth_timeout = AUTH_TIMEOUT_S
	mp.peer_authenticating.connect(_on_peer_authenticating)
	mp.peer_authentication_failed.connect(_on_peer_authentication_failed)
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.peer_packet.connect(_on_peer_packet)
	mp.multiplayer_peer = enet
	_enet = enet
	_mp = mp
	_password = password
	_version = version
	_harbor_dirty = false
	_next_battle_id = 1
	_ticks = 0
	return OK


## Tells every peer, disconnects them gracefully (up to wait_ms), then closes the host.
func stop(wait_ms := 1000) -> void:
	if not is_active():
		return
	if _enet.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_enet.refuse_new_connections = true
		var peers := {}
		for c in captains.values():
			if c.connected:
				_send(c, {"t": "server_stopping"})
			peers[c.peer] = true
		for peer in _mp.get_peers():
			peers[peer] = true
		for peer in peers:
			var packet_peer := _enet.get_peer(peer)
			if packet_peer != null:
				packet_peer.peer_disconnect_later()
		_mp.poll()  # flush
		var start_ms := Time.get_ticks_msec()
		while not _mp.get_peers().is_empty() and Time.get_ticks_msec() - start_ms < wait_ms:
			OS.delay_msec(5)
			_mp.poll()
		var host := _enet.host
		_log("SRV stopped host_bytes_in=%d host_bytes_out=%d" % [
			host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA),
			host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)])
	else:
		_log("SRV stopped host_bytes_in=0 host_bytes_out=0")
	_enet.close()
	_mp.multiplayer_peer = null
	_enet = null
	_mp = null
	battles.clear()
	captains.clear()
	_harbor_dirty = false


func poll() -> void:
	if not is_active() or _enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_mp.poll()
	_flush_harbor()


func advance_tick() -> void:
	return  # battles arrive in Task 4


func connected_count() -> int:
	var count := 0
	for c in captains.values():
		if c.connected:
			count += 1
	return count


func captain_by_id(captain_id: String) -> Dictionary:
	for c in captains.values():
		if c.captain_id == captain_id:
			return c
	return {}


func captain_stats() -> Array:
	var out := []
	for c in _by_slot(captains.values()):
		out.append({"name": c.name, "captain_id": c.captain_id, "slot": c.slot, "received": c.received,
			"applied": c.applied, "bytes_in": c.bytes_in, "bytes_out": c.bytes_out})
	return out


func is_active() -> bool:
	return _mp != null


func _process(_d: float) -> void:
	poll()


func _physics_process(_d: float) -> void:
	advance_tick()


# --- handshake -------------------------------------------------------------------------------

func _on_peer_authenticating(peer: int) -> void:
	var packet_peer := _enet.get_peer(peer)
	if packet_peer != null:
		packet_peer.set_timeout(Protocol.TIMEOUT_LIMIT, Protocol.TIMEOUT_MIN_MS, Protocol.TIMEOUT_MAX_MS)
		# Plan 05 ENet knobs (throttle_configure / bandwidth limits) would sit here.


func _on_peer_authentication_failed(peer: int) -> void:
	captains.erase(peer)


func _on_auth(peer: int, data: PackedByteArray) -> void:
	var hello = bytes_to_var(data) if not data.is_empty() else null
	var client_version: String = hello["version"] if hello is Dictionary and hello.get("version") is String else "?"
	var reason := ""
	if not (hello is Dictionary) or not (hello.get("version") is String) or not (hello.get("password") is String) \
			or not (hello.get("captain_id") is String) or not (hello.get("name") is String) \
			or hello["captain_id"].length() < 1 or hello["captain_id"].length() > Protocol.CAPTAIN_ID_MAX:
		reason = "bad_request"
	elif hello["version"] != _version:
		reason = "version_mismatch"
	elif hello["password"] != _password:
		reason = "wrong_password"
	elif captains.values().filter(func(c): return c.captain_id != hello["captain_id"]).size() >= Definitions.MAX_CAPTAINS:
		reason = "server_full"
	if reason != "":
		_log("SRV auth refuse peer=%d reason=%s client_version=%s" % [peer, reason, client_version])
		_mp.send_auth(peer, var_to_bytes({"ok": false, "reason": reason, "server_version": _version}))
		_disconnect_peer(peer)
		return
	var captain_id: String = hello["captain_id"]
	var captain_name: String = hello["name"].strip_edges().left(Protocol.NAME_MAX)
	if captain_name.is_empty():
		captain_name = "Captain"
	var slot := -1
	var old := captain_by_id(captain_id)
	if not old.is_empty():
		slot = old.slot
		_log("SRV replace captain=%s old_peer=%d new_peer=%d" % [captain_name, old.peer, peer])
		if old.connected:
			_send(old, {"t": "replaced"})
		_detach(old)
		_disconnect_peer(old.peer)
		captains.erase(old.peer)
		_harbor_dirty = true
	else:
		var used := captains.values().map(func(c): return c.slot)
		slot = 0
		while slot in used:
			slot += 1
	captains[peer] = _new_record(peer, captain_id, captain_name, slot)
	_log("SRV auth accept peer=%d captain=%s slot=%d client_version=%s" % [peer, captain_name, slot, client_version])
	_mp.send_auth(peer, var_to_bytes({"ok": true, "server_version": _version, "slot": slot}))
	_mp.complete_auth(peer)


func _new_record(peer: int, captain_id: String, captain_name: String, slot: int) -> Dictionary:
	return {"peer": peer, "captain_id": captain_id, "name": captain_name, "slot": slot, "connected": false,
		"state": "harbor", "battle_id": 0, "turn": 0, "steer_ms": 0, "actions": [],
		"received": 0, "applied": 0, "bytes_in": 0, "bytes_out": 0}


func _disconnect_peer(peer: int) -> void:
	var packet_peer := _enet.get_peer(peer)
	if packet_peer != null:
		packet_peer.peer_disconnect_later()


func _on_peer_connected(peer: int) -> void:
	if not captains.has(peer):
		return
	var c: Dictionary = captains[peer]
	c.connected = true
	_log("SRV join captain=%s slot=%d peer=%d" % [c.name, c.slot, peer])
	_harbor_dirty = true


func _on_peer_disconnected(peer: int) -> void:
	if not captains.has(peer):
		return  # replaced (or never authenticated)
	var c: Dictionary = captains[peer]
	_detach(c)
	_log("SRV leave captain=%s received=%d applied=%d bytes_in=%d bytes_out=%d" % [
		c.name, c.received, c.applied, c.bytes_in, c.bytes_out])
	captains.erase(peer)
	_harbor_dirty = true


## Back to the harbor: an active, non-lingering ship in its battle starts lingering.
func _detach(c: Dictionary) -> void:
	if c.state == "in_battle" and battles.has(c.battle_id):
		var battle = battles[c.battle_id]
		if battle.has_active_ship(c.captain_id) and not battle.is_lingering(c.captain_id):
			battle.linger(c.captain_id)
	c.state = "harbor"
	c.battle_id = 0
	c.actions.clear()
	c.turn = 0


# --- messages --------------------------------------------------------------------------------

func _on_peer_packet(peer: int, packet: PackedByteArray) -> void:
	if not captains.has(peer):
		return
	var c: Dictionary = captains[peer]
	c.bytes_in += packet.size()
	var msg := Protocol.decode_message(packet)  # {} for any other kind or bad bytes
	if not msg.is_empty():
		_dispatch(c, msg)


## Request handlers arrive in Task 4; unknown types are ignored.
func _dispatch(_c: Dictionary, _msg: Dictionary) -> void:
	pass


func _send(c: Dictionary, msg: Dictionary) -> void:
	var bytes := Protocol.encode_message(msg)
	_mp.send_bytes(bytes, c.peer, MultiplayerPeer.TRANSFER_MODE_RELIABLE, Protocol.CHANNEL_RELIABLE)
	c.bytes_out += bytes.size()


# --- harbor ----------------------------------------------------------------------------------

func _flush_harbor() -> void:
	if not _harbor_dirty:
		return
	_harbor_dirty = false
	for c in captains.values():
		if c.connected:
			_send(c, _harbor_for(c))


func _harbor_for(c: Dictionary) -> Dictionary:
	var list := []
	for id in _sorted(battles.keys()):
		var battle = battles[id]
		list.append({"battle_id": id, "preset_id": battle.preset_id,
			"label": Definitions.PRESETS[battle.preset_id].get("label", battle.preset_id),
			"captains": battle.captain_names(), "ai_left": battle.ai_left(), "elapsed": battle.sim.elapsed,
			"can_join": not battle.barred.has(c.captain_id) and not (c.state == "in_battle" and c.battle_id == id),
			"lingering_here": battle.is_lingering(c.captain_id)})
	var roster := []
	for other in _by_slot(captains.values()):
		if other.connected:
			roster.append({"name": other.name, "slot": other.slot, "battle_id": other.battle_id})
	return {"t": "harbor", "battles": list, "captains": roster,
		"can_start": battles.size() < Definitions.MAX_BATTLES, "actions_applied": c.applied}


func _sorted(keys: Array) -> Array:
	var out := keys.duplicate()
	out.sort()
	return out


func _by_slot(records: Array) -> Array:
	var out := records.duplicate()
	out.sort_custom(func(a, b): return a.slot < b.slot)
	return out


func _log(line: String) -> void:
	if verbose:
		print(line)
