extends Node
## Authoritative session server (Phase 3 plan 02). Owns its own SceneMultiplayer + ENet host and
## polls itself, so it works outside the SceneTree. No RPCs: Protocol packets via send_bytes.
## poll() receives, dispatches and flushes the harbor; advance_tick() steps every battle.
## Every handler validates its fields; a failure replies {"t": "refused", "reason"} with no side
## effects. A battle closes in the same advance_tick its result appears, so no op ever follows it.

const Protocol := preload("res://net/protocol.gd")
const Definitions := preload("res://sim/definitions.gd")
const Battle := preload("res://net/battle.gd")

const AUTH_TIMEOUT_S := 3.0
const DT := 1.0 / 60.0
## Events that change a harbor entry (captains listed) mark the harbor dirty.
const MEMBERSHIP_EVENTS: Array[String] = ["captain_joined", "ship_lingering", "ship_reclaimed", "ship_abandoned", "ship_escaped"]

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
	if not is_active() or connected_count() == 0:
		return  # pause-when-empty: no steps, linger grace frozen
	var now := Time.get_ticks_msec()
	for id in _sorted(battles.keys()):
		var battle = battles[id]
		var commands := {}
		for c in _subscribers(id):
			if c.state == "in_battle" and battle.has_active_ship(c.captain_id) and not battle.is_lingering(c.captain_id):
				var command := {"turn": float(Protocol.steer_turn(c.turn, c.steer_ms, now))}
				if not c.actions.is_empty():  # FIFO: at most one action per tick
					command[c.actions.pop_front()] = true
					c.applied += 1
				commands[battle.ship_of[c.captain_id]] = command
		var outcomes: Array = battle.advance(DT, commands)
		_send_events(battle)
		for o in outcomes:
			_on_outcome(battle, o)
		if not battle.sim.result.is_empty():
			_send_snapshot(battle)  # final state, then the shared result
			_close_battle(battle)
		elif battle.tick % Protocol.SNAPSHOT_EVERY_TICKS == 0:
			_send_snapshot(battle)
	_ticks += 1
	if not battles.is_empty() and _ticks % Protocol.HARBOR_REFRESH_TICKS == 0:
		_harbor_dirty = true
	_flush_harbor()


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


## Back to the harbor (leave_battle, disconnect, replace): an active, non-lingering ship in its
## battle starts lingering. A spectator just leaves.
func _detach(c: Dictionary) -> void:
	if c.state == "in_battle" and battles.has(c.battle_id):
		var battle = battles[c.battle_id]
		if battle.has_active_ship(c.captain_id) and not battle.is_lingering(c.captain_id):
			battle.linger(c.captain_id)
	_to_harbor(c)


func _to_harbor(c: Dictionary) -> void:
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


## Unknown types are ignored.
func _dispatch(c: Dictionary, msg: Dictionary) -> void:
	match msg["t"]:
		"start_battle":
			_on_start_battle(c, msg)
		"join_battle":
			_on_join_battle(c, msg)
		"leave_battle":
			_detach(c)
			_harbor_dirty = true
		"action":
			_on_action(c, msg)
		"steer":
			_on_steer(c, msg)


func _refuse(c: Dictionary, reason: String) -> void:
	_send(c, {"t": "refused", "reason": reason})


func _valid_vessel(vessel_id) -> bool:
	return vessel_id is String and Definitions.VESSELS.has(vessel_id)


func _on_start_battle(c: Dictionary, msg: Dictionary) -> void:
	var preset_id = msg.get("preset_id")
	var vessel_id = msg.get("vessel_id")
	if not (preset_id is String and preset_id in Definitions.BATTLE_PRESETS) or not _valid_vessel(vessel_id):
		_refuse(c, "bad_request")
		return
	if battles.size() >= Definitions.MAX_BATTLES:
		_refuse(c, "battle_cap")  # before leaving anything
		return
	var id := _next_battle_id
	_next_battle_id += 1
	_leave_for_other(c, id)
	var battle = Battle.new(id, preset_id)
	battles[id] = battle
	battle.add_captain(c.captain_id, c.name, c.slot, vessel_id)
	_enter(c, battle)
	_log("SRV battle start id=%d preset=%s by=%s" % [id, preset_id, c.name])


func _on_join_battle(c: Dictionary, msg: Dictionary) -> void:
	var id = msg.get("battle_id")
	if not (id is int):
		_refuse(c, "bad_request")
		return
	if not battles.has(id):
		_refuse(c, "unknown_battle")
		return
	var battle = battles[id]
	var cid: String = c.captain_id
	if battle.barred.has(cid):
		_refuse(c, "no_reentry")
		return
	if battle.ship_of.has(cid) and not battle.is_lingering(cid):
		_refuse(c, "already_in_battle")  # not barred and not lingering: its ship is active and commanded
		return
	var kind := "join"
	if battle.is_lingering(cid):
		kind = "reclaim"
		battle.reclaim(cid, c.name, c.slot)  # vessel ignored
	elif not _valid_vessel(msg.get("vessel_id")):
		_refuse(c, "bad_request")
		return
	else:
		battle.add_captain(cid, c.name, c.slot, msg["vessel_id"])
	_leave_for_other(c, id)
	_enter(c, battle)
	_log("SRV battle %s id=%d captain=%s ship=%d" % [kind, id, c.name, battle.ship_of[cid]])


## The captain commands its ship in `battle` from now on; it gets `joined` with every captain name.
func _enter(c: Dictionary, battle) -> void:
	c.state = "in_battle"
	c.battle_id = battle.battle_id
	c.actions.clear()
	c.turn = 0
	var names := {}
	for ship_id in battle.names:
		names[ship_id] = battle.names[ship_id].duplicate()
	_send(c, {"t": "joined", "battle_id": battle.battle_id, "ship_id": battle.ship_of[c.captain_id],
		"preset_id": battle.preset_id, "captains": names})
	_harbor_dirty = true


## Abandons the captain's ship (current or lingering) in every other battle; a spectating
## subscription simply ends when the caller moves the record to the kept battle.
func _leave_for_other(c: Dictionary, keep_id: int) -> void:
	for id in battles:
		if id != keep_id and battles[id].has_active_ship(c.captain_id):
			battles[id].abandon(c.captain_id)


func _on_action(c: Dictionary, msg: Dictionary) -> void:
	c.received += 1
	var action = msg.get("action")
	if not (action is String and action in Protocol.ACTIONS) or c.state != "in_battle" or not battles.has(c.battle_id):
		return
	var battle = battles[c.battle_id]
	if battle.has_active_ship(c.captain_id) and not battle.is_lingering(c.captain_id) \
			and c.actions.size() < Protocol.ACTION_QUEUE_MAX:
		c.actions.append(action)


func _on_steer(c: Dictionary, msg: Dictionary) -> void:
	var turn = msg.get("turn")
	if turn is int and turn >= -1 and turn <= 1:
		c.turn = turn
		c.steer_ms = Time.get_ticks_msec()


# --- battle delivery -------------------------------------------------------------------------

## Connected records watching battle `id` (commanding or spectating), by slot.
func _subscribers(id: int) -> Array:
	var out := []
	for c in _by_slot(captains.values()):
		if c.connected and c.battle_id == id and (c.state == "in_battle" or c.state == "spectating"):
			out.append(c)
	return out


## This step's events in sim order, deep-copied and stamped with the battle tick. fire_rejected
## goes only to its ship's owner; each captain_joined / ship_reclaimed is followed by captain_info.
func _send_events(battle) -> void:
	var events := []
	for e in battle.sim.events:
		var copy: Dictionary = e.duplicate(true)
		copy["tick"] = battle.tick
		events.append(copy)
		if copy["type"] in MEMBERSHIP_EVENTS:
			_harbor_dirty = true
		if copy["type"] == "captain_joined" or copy["type"] == "ship_reclaimed":
			var info: Dictionary = battle.names.get(copy["ship_id"], {"name": "", "slot": -1})
			events.append({"type": "captain_info", "ship_id": copy["ship_id"], "name": info["name"],
				"slot": info["slot"], "tick": battle.tick})
	if events.is_empty():
		return
	for c in _subscribers(battle.battle_id):
		var own: int = battle.ship_of.get(c.captain_id, -1)
		var list := events.filter(func(e): return e["type"] != "fire_rejected" or e["ship_id"] == own)
		if not list.is_empty():
			_send(c, {"t": "events", "battle_id": battle.battle_id, "events": list})


func _send_snapshot(battle) -> void:
	var bytes := Protocol.encode_snapshot(battle.battle_id, battle.sim, battle.tick)
	if bytes.is_empty():
		return  # encode_snapshot already push_errored
	for c in _subscribers(battle.battle_id):
		_mp.send_bytes(bytes, c.peer, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, Protocol.CHANNEL_UNRELIABLE)
		c.bytes_out += bytes.size()


func _on_outcome(battle, o: Dictionary) -> void:
	var c := captain_by_id(o.captain_id)
	if not c.is_empty() and c.connected:
		_send(c, {"t": "outcome", "battle_id": battle.battle_id, "ship_id": o.ship_id, "outcome": o.outcome,
			"elapsed": o.elapsed})
	var captain_name: String = battle.names.get(o.ship_id, {}).get("name", o.captain_id)
	_log("SRV outcome battle=%d captain=%s ship=%d outcome=%s" % [battle.battle_id, captain_name, o.ship_id, o.outcome])
	if not c.is_empty() and c.battle_id == battle.battle_id and (c.state == "in_battle" or c.state == "spectating"):
		if o.outcome == "sunk" or o.outcome == "disabled":
			c.state = "spectating"
			c.actions.clear()
		elif o.outcome == "escaped" or o.outcome == "abandoned":
			_to_harbor(c)
	_harbor_dirty = true


## Sends the shared result to every subscriber, returns them to the harbor and drops the battle.
func _close_battle(battle) -> void:
	var result: Dictionary = battle.sim.result
	for c in _subscribers(battle.battle_id):
		_send(c, {"t": "battle_result", "battle_id": battle.battle_id, "result": result.duplicate(true)})
		_to_harbor(c)
	_log("SRV battle result id=%d outcome=%s elapsed=%.2f hash=%s" % [battle.battle_id, result.outcome,
		result.elapsed, Protocol.result_hash(result)])
	battles.erase(battle.battle_id)
	_harbor_dirty = true


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
