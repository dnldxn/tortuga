extends RefCounted
## Phase 3 plan 02: session server and client over real localhost ENet (handshake, captains,
## harbor, stop, battles). Nodes stay out of the tree; cases poll them by hand and free them at the end.

const SessionServer := preload("res://net/session_server.gd")
const SessionClient := preload("res://net/session_client.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const Definitions := preload("res://sim/definitions.gd")
const Protocol := preload("res://net/protocol.gd")
const VERSION := "0.7"
const FIRST := NavalSimulation.FIRST_CAPTAIN_SHIP_ID


func run(t) -> bool:
	for test in [_test_auth_refusals, _test_harbor_captains, _test_full_and_replaced, _test_server_stop,
			_test_battle_join_and_harbor, _test_steering_actions_events, _test_defeat_and_victory, _test_lost,
			_test_four_battles]:
		t.check(test.call(t) == true, "session: %s completed" % test.get_method())
	return true


func _server(t, port: int):
	var server = SessionServer.new()
	t.check(server.start(port, "pw", VERSION) == OK, "session: server listens on %d" % port)
	return server


## A connecting client whose signal args land in its "rec" meta (one list per signal).
func _client(port: int, captain_name: String, cid: String, password := "pw", version := VERSION):
	var c = SessionClient.new()
	var rec := {"auth": [], "connected": [], "harbor": [], "joined": [], "snapshots": [], "events": [],
		"outcomes": [], "results": [], "refused": [], "ended": []}
	c.set_meta("rec", rec)
	c.auth_refused.connect(func(reason, server_version): rec["auth"].append([reason, server_version]))
	c.connected_ok.connect(func(slot): rec["connected"].append(slot))
	c.harbor_changed.connect(func(harbor): rec["harbor"].append(harbor))
	c.joined.connect(func(info): rec["joined"].append(info))
	c.snapshot_received.connect(func(snap): rec["snapshots"].append(snap))
	c.events_received.connect(func(_battle_id, events): rec["events"].append_array(events))
	c.outcome.connect(func(info): rec["outcomes"].append(info))
	c.battle_result.connect(func(battle_id, result): rec["results"].append([battle_id, result]))
	c.refused.connect(func(reason): rec["refused"].append(reason))
	c.connection_ended.connect(func(reason): rec["ended"].append(reason))
	c.version = version
	c.connect_to("127.0.0.1", port, captain_name, password, cid)
	return c


func _rec(c) -> Dictionary:
	return c.get_meta("rec")


func _last_harbor(c) -> Dictionary:
	var list: Array = _rec(c)["harbor"]
	return list[-1] if not list.is_empty() else {}


func _harbor_captains(c) -> Array:
	return _last_harbor(c).get("captains", [])


## Polls every node with 1 ms sleeps until done.call() is true; false on timeout.
func _pump(nodes: Array, done: Callable, timeout_ms := 2000) -> bool:
	var start := Time.get_ticks_msec()
	while not done.call():
		if Time.get_ticks_msec() - start > timeout_ms:
			return false
		for node in nodes:
			node.poll()
		OS.delay_msec(1)
	return true


## n server ticks with no sleeps; `steer` maps client -> turn sent every tick.
func _ticks(server, clients: Array, n: int, steer := {}) -> void:
	for _i in n:
		for c in steer:
			c.set_steer(steer[c])
		for c in clients:
			c.poll()
		server.poll()
		server.advance_tick()
		server.poll()
		for c in clients:
			c.poll()


func _finish(server, clients: Array) -> void:
	for c in clients:
		c.disconnect_from()
	server.stop(0)
	for c in clients:
		c.free()
	server.free()


func _test_auth_refusals(t) -> bool:
	var fresh = SessionClient.new()
	t.check(fresh.status == "offline" and fresh._enet == null, "session: fresh client has no socket")
	fresh.free()
	# Nothing listens on the port yet.
	var lost = _client(24760, "Lost", "lost")
	lost.connect_timeout_ms = 500
	var started := Time.get_ticks_msec()
	_pump([lost], func(): return not _rec(lost)["ended"].is_empty(), 3000)
	var took := Time.get_ticks_msec() - started
	t.check(_rec(lost)["ended"] == ["connection_lost"] and took <= 1500,
		"session: closed port ends connection_lost within 1500 ms (took %d ms)" % took)
	t.check(lost.status == "offline" and lost.disconnects == 1, "session: lost client is offline")
	lost.free()

	var server = _server(t, 24760)
	var old = _client(24760, "Old", "old", "pw", "0.6")
	var dev = _client(24760, "Dev", "dev", "pw", "dev")
	var nope = _client(24760, "Nope", "nope", "nope")
	var blank = _client(24760, "Blank", "")
	var bad := [old, dev, nope, blank]
	t.check(_pump([server] + bad, func(): return bad.all(func(c): return not _rec(c)["auth"].is_empty())),
		"session: every bad hello is refused")
	t.check(_rec(old)["auth"] == [["version_mismatch", VERSION]], "session: old version refused")
	t.check(_rec(dev)["auth"] == [["version_mismatch", VERSION]], "session: dev matches only dev")
	t.check(_rec(nope)["auth"] == [["wrong_password", VERSION]], "session: wrong password refused")
	t.check(_rec(blank)["auth"] == [["bad_request", VERSION]], "session: empty captain id refused")
	_pump([server] + bad, func(): return false, 100)  # the disconnects land
	var quiet := func(c): return _rec(c)["ended"].is_empty() and _rec(c)["connected"].is_empty() and c.status == "offline"
	t.check(bad.all(quiet), "session: a refusal emits no ended/connected")
	t.check(server.captains.is_empty() and server.connected_count() == 0, "session: refusals reserve nothing")

	var good = _client(24760, "Anne", "anne")
	t.check(_pump([server, good], func(): return server.connected_count() == 1 and good.status == "connected"),
		"session: good client connects")
	t.check(_rec(good)["connected"] == [0] and good.slot == 0 and good.server_version == VERSION
		and good.status == "connected", "session: accept stores slot and server version")
	t.check(server.connected_count() == 1 and server.captain_by_id("anne").get("name") == "Anne",
		"session: server records the captain")
	t.check(server.captain_by_id("nobody") == {}, "session: unknown captain id -> {}")
	_finish(server, bad + [good])
	return true


func _test_harbor_captains(t) -> bool:
	var server = _server(t, 24761)
	var a = _client(24761, "Anne", "anne")
	t.check(_pump([server, a], func(): return not _rec(a)["harbor"].is_empty()), "session: A gets a harbor")
	var harbor := _last_harbor(a)
	t.check(harbor.get("t") == "harbor" and harbor.get("battles") == [], "session: harbor has no battles")
	t.check(_harbor_captains(a) == [{"name": "Anne", "slot": 0, "battle_id": 0}], "session: harbor lists Anne/0")
	t.check(harbor.get("can_start") == true and harbor.get("actions_applied") == 0, "session: can_start, nothing applied")
	t.check(a.actions_applied == 0, "session: client stores actions_applied")
	var net: Dictionary = a.net_stats()
	t.check(net["bytes_in"] > 0 and net["bytes_out"] > 0 and net["packets_in"] > 0 and net["packets_out"] > 0
		and net["disconnects"] == 0 and net.has("rtt_ms") and net.has("packet_loss"), "session: client net_stats show traffic")
	var stats: Array = server.captain_stats()
	t.check(stats.size() == 1 and stats[0]["name"] == "Anne" and stats[0]["captain_id"] == "anne"
		and stats[0]["slot"] == 0 and stats[0]["bytes_out"] > 0 and stats[0]["received"] == 0
		and stats[0]["applied"] == 0, "session: captain_stats show traffic")

	var b = _client(24761, "  Bonny  ", "bonny")
	var both := [{"name": "Anne", "slot": 0, "battle_id": 0}, {"name": "Bonny", "slot": 1, "battle_id": 0}]
	t.check(_pump([server, a, b], func(): return _harbor_captains(a) == both and _harbor_captains(b) == both),
		"session: both see Anne/0 and Bonny/1 (names stripped)")
	t.check(_rec(b)["connected"] == [1], "session: B gets slot 1")
	a.disconnect_from()
	t.check(a.status == "offline" and _rec(a)["ended"].is_empty(), "session: disconnect_from emits nothing")
	t.check(_pump([server, b], func(): return _harbor_captains(b) == [both[1]]), "session: B sees only Bonny after A leaves")
	t.check(server.connected_count() == 1 and server.captain_by_id("anne") == {}, "session: A's record is gone")
	_finish(server, [a, b])
	return true


func _test_full_and_replaced(t) -> bool:
	var server = _server(t, 24762)
	var clients := []
	for i in 4:
		clients.append(_client(24762, "C%d" % i, "c%d" % i))
	var all_in := func(): return server.connected_count() == 4 and clients.all(func(c): return c.status == "connected")
	t.check(_pump([server] + clients, all_in), "session: four captains connect")
	t.check(clients.map(func(c): return c.slot) == [0, 1, 2, 3], "session: slots 0-3 in order")
	var extra = _client(24762, "Extra", "c9")
	t.check(_pump([server, extra] + clients, func(): return not _rec(extra)["auth"].is_empty()), "session: fifth refused")
	t.check(_rec(extra)["auth"] == [["server_full", VERSION]], "session: fifth captain -> server_full")
	var again = _client(24762, "Again", "c1")
	var swapped := func(): return _rec(clients[1])["ended"] == ["replaced"] and not _rec(again)["connected"].is_empty() and server.connected_count() == 4
	t.check(_pump([server, again] + clients, swapped), "session: same captain id replaces the old connection")
	t.check(_rec(again)["connected"] == [1] and again.slot == 1, "session: replacement keeps the slot")
	t.check(clients[1].status == "offline" and clients[1].disconnects == 1, "session: replaced client is offline")
	t.check(server.captain_by_id("c1").get("name") == "Again" and server.captains.size() == 4,
		"session: one record per captain id")
	t.check(clients.all(func(c): return c == clients[1] or c.status == "connected"), "session: others unaffected")
	_finish(server, clients + [extra, again])
	return true


func _test_server_stop(t) -> bool:
	var server = _server(t, 24763)
	var a = _client(24763, "Anne", "anne")
	var b = _client(24763, "Bonny", "bonny")
	t.check(_pump([server, a, b], func(): return server.connected_count() == 2), "session: A and B connect")
	server.stop(0)
	t.check(server.captains.is_empty() and server.battles.is_empty() and not server.is_active(),
		"session: stop clears the server")
	# A and B were not polled during stop(0), so their disconnect_later never completed and
	# close() skips such peers: they end by ENet timeout (~3 s measured), reason from server_stopping.
	t.check(_pump([a, b], func(): return not _rec(a)["ended"].is_empty() and not _rec(b)["ended"].is_empty(), 6000),
		"session: A and B see the stop")
	t.check(_rec(a)["ended"] == ["server_stopped"] and _rec(b)["ended"] == ["server_stopped"],
		"session: stop ends server_stopped")
	t.check(a.disconnects == 1 and b.disconnects == 1 and a.status == "offline", "session: one disconnect each")
	server.stop(0)  # no-op when inactive
	server.free()

	server = _server(t, 24763)
	var c = _client(24763, "Calico", "calico")
	t.check(_pump([server, c], func(): return c.status == "connected"), "session: C connects to a new server")
	server._enet.close()  # abrupt: ENet sends disconnect_now to connected peers
	t.check(_pump([c], func(): return not _rec(c)["ended"].is_empty()), "session: C sees the loss")
	t.check(_rec(c)["ended"] == ["connection_lost"], "session: abrupt close ends connection_lost")
	_finish(server, [a, b, c])
	return true


# --- battles (Task 4) ------------------------------------------------------------------------

## Hull 1 plus an owner's round shot at the ship's own position, so the next step sinks it.
## Same as test_battle.gd's helper (ruling R2), taking the Battle.
func _sink(b, ship_id: int, owner_id: int) -> void:
	var sim = b.sim
	sim.ships[ship_id]["hull"] = 1.0
	sim.projectiles.append({"id": sim.next_projectile_id, "owner_id": owner_id, "ammo": "round",
		"position": sim.ships[ship_id]["position"], "direction": Vector2.RIGHT,
		"remaining_range": 900.0, "owner_cleared": true})
	sim.next_projectile_id += 1


## Connects every client and waits until the server sees them all.
func _connect_all(t, server, clients: Array) -> void:
	var ready := func(): return server.connected_count() == clients.size() and clients.all(func(c): return c.status == "connected")
	t.check(_pump([server] + clients, ready), "session: %d captains connect" % clients.size())


## Sends the request and waits for the client's joined (or refused) reply.
func _start(t, server, clients: Array, c, preset_id: String, vessel_id: String) -> void:
	var before: int = _rec(c)["joined"].size()
	c.start_battle(preset_id, vessel_id)
	t.check(_pump([server] + clients, func(): return _rec(c)["joined"].size() > before),
		"session: start %s is answered" % preset_id)


func _join(t, server, clients: Array, c, id: int, vessel_id: String) -> void:
	var before: int = _rec(c)["joined"].size()
	c.join_battle(id, vessel_id)
	t.check(_pump([server] + clients, func(): return _rec(c)["joined"].size() > before), "session: join battle %d" % id)


## Waits for the client's next refusal (after a request it just sent) and returns its reason ("" on timeout).
func _refusal(server, clients: Array, c) -> String:
	var before: int = _rec(c)["refused"].size()
	if not _pump([server] + clients, func(): return _rec(c)["refused"].size() > before):
		return ""
	return _rec(c)["refused"][-1]


## One tick at a time until done.call() is true; false after max_ticks.
func _tick_until(server, clients: Array, done: Callable, max_ticks := 120) -> bool:
	for _i in max_ticks:
		if done.call():
			return true
		_ticks(server, clients, 1)
	return done.call()


func _events_of(c, type: String) -> Array:
	return _rec(c)["events"].filter(func(e): return e.get("type") == type)


func _ticks_ordered(events: Array) -> bool:
	var last := -1
	for e in events:
		if not (e.get("tick") is int) or e["tick"] < last:
			return false
		last = e["tick"]
	return true


func _test_battle_join_and_harbor(t) -> bool:
	var server = _server(t, 24764)
	var a = _client(24764, "Anne", "anne")
	var b = _client(24764, "Bonny", "bonny")
	var clients := [a, b]
	var all := [server, a, b]
	_connect_all(t, server, clients)
	a.start_battle("practice", "sloop")
	t.check(_refusal(server, clients, a) == "bad_request" and server.battles.is_empty() and a.battle_id == 0,
		"session: practice preset -> bad_request, no battle")
	a.start_battle("duel_sloop", "sloop")
	t.check(_pump(all, func(): return not _rec(a)["joined"].is_empty()), "session: A's start is answered")
	var info: Dictionary = _rec(a)["joined"][0]
	t.check(info.get("t") == "joined" and info.get("battle_id") == 1 and info.get("ship_id") == FIRST
		and info.get("preset_id") == "duel_sloop" and info.get("captains") == {FIRST: {"name": "Anne", "slot": 0}},
		"session: A joined battle 1 as ship FIRST (%s)" % [info])
	t.check(a.battle_id == 1 and a.ship_id == FIRST and a.ship_active, "session: client stores the joined battle")
	t.check(server.battles.keys() == [1] and server.captain_by_id("anne").state == "in_battle", "session: server runs battle 1")
	var battle = server.battles[1]
	_ticks(server, clients, 1)
	var listed := func(): return _last_harbor(b).get("battles", []).size() == 1 and _last_harbor(b)["battles"][0]["captains"] == ["Anne"]
	t.check(_pump(all, listed), "session: B's harbor lists Anne's battle")
	var entry: Dictionary = _last_harbor(b)["battles"][0]
	t.check(entry["battle_id"] == 1 and entry["preset_id"] == "duel_sloop" and entry["label"] == "Sloop duel"
		and entry["ai_left"] == 1 and entry["can_join"] == true and entry["lingering_here"] == false,
		"session: harbor entry (%s)" % [entry])
	t.check(_last_harbor(a)["battles"][0]["can_join"] == false, "session: A cannot join its own battle")
	t.check({"name": "Anne", "slot": 0, "battle_id": 1} in _harbor_captains(b), "session: roster shows Anne in battle 1")
	var seen: int = _rec(b)["harbor"].size()
	_ticks(server, clients, 61)
	_pump(all, func(): return false, 30)
	var refreshed: Array = _rec(b)["harbor"].slice(seen).filter(func(h): return h["battles"].size() == 1 and h["battles"][0]["elapsed"] >= 0.9)
	t.check(not refreshed.is_empty(), "session: harbor refreshes with elapsed >= 0.9")

	_join(t, server, clients, b, 1, "brig")
	var info_b: Dictionary = _rec(b)["joined"][0]
	t.check(info_b.get("battle_id") == 1 and info_b.get("ship_id") == FIRST + 1
		and info_b.get("captains") == {FIRST: {"name": "Anne", "slot": 0}, FIRST + 1: {"name": "Bonny", "slot": 1}},
		"session: B joined as ship FIRST+1 with both names (%s)" % [info_b])
	var before: int = _rec(a)["events"].size()
	_ticks(server, clients, 1)
	t.check(_pump(all, func(): return not _events_of(a, "captain_info").is_empty()), "session: A gets captain_info")
	var fresh: Array = _rec(a)["events"].slice(before).filter(func(e): return e["type"] in ["captain_joined", "captain_info"])
	t.check(fresh.size() == 2 and fresh[0]["type"] == "captain_joined" and fresh[0]["ship_id"] == FIRST + 1
		and fresh[0]["tick"] == battle.tick
		and fresh[1] == {"type": "captain_info", "ship_id": FIRST + 1, "name": "Bonny", "slot": 1, "tick": battle.tick},
		"session: captain_joined then captain_info, stamped with the tick (%s)" % [fresh])
	var i: int = _rec(a)["events"].find(fresh[0])
	t.check(_rec(a)["events"][i + 1] == fresh[1], "session: captain_info follows captain_joined directly")
	_finish(server, clients)
	return true


func _test_steering_actions_events(t) -> bool:
	var server = _server(t, 24765)
	var a = _client(24765, "Anne", "anne")
	var b = _client(24765, "Bonny", "bonny")
	var clients := [a, b]
	var all := [server, a, b]
	_connect_all(t, server, clients)
	_start(t, server, clients, a, "duel_sloop", "sloop")
	_join(t, server, clients, b, 1, "brig")
	_ticks(server, clients, 2)
	var battle = server.battles[1]
	# Steering
	var h_a: float = battle.sim.ships[FIRST]["heading"]
	var h_b: float = battle.sim.ships[FIRST + 1]["heading"]
	var positions := {}  # battle tick -> server position of FIRST+1
	for _i in 30:
		_ticks(server, clients, 1, {a: 1, b: -1})
		positions[battle.tick] = battle.sim.ships[FIRST + 1]["position"]
	_pump(all, func(): return false, 30)
	var d_a := Definitions.wrap_angle(battle.sim.ships[FIRST]["heading"] - h_a)
	var d_b := Definitions.wrap_angle(battle.sim.ships[FIRST + 1]["heading"] - h_b)
	t.check(d_a > 0.0 and d_b < 0.0, "session: steering turns A right, B left (%f, %f)" % [d_a, d_b])
	var snaps: Array = _rec(a)["snapshots"]
	t.check(snaps.size() >= 9, "session: A got >= 9 snapshots (%d)" % snaps.size())
	var last_tick := -1
	var shape_ok := true
	for snap in snaps:
		shape_ok = shape_ok and snap["battle_id"] == 1 and snap["tick"] > last_tick and snap["tick"] % 3 == 0 \
			and snap["ships"].has(2) and snap["ships"].has(FIRST) and snap["ships"].has(FIRST + 1)
		last_tick = snap["tick"]
	t.check(shape_ok, "session: snapshots are battle 1, rising, every 3rd tick, with 2/FIRST/FIRST+1")
	var last: Dictionary = snaps[-1]
	t.check(positions.has(last["tick"]) and last["ships"][FIRST + 1]["position"].distance_to(positions[last["tick"]]) < 0.01,
		"session: the snapshot at its tick has FIRST+1 at the server's position")
	# Burst
	var rec_a: Dictionary = server.captain_by_id("anne")
	for action in ["fire_port", "fire_port", "cycle_starboard", "cycle_starboard"]:
		t.check(a.send_action(action), "session: A sends %s" % action)
	t.check(_pump(all, func(): return rec_a.actions.size() == 4), "session: the burst is queued")
	var first_tick: int = battle.tick + 1
	var own := func(e, type): return e["type"] == type and e["ship_id"] == FIRST
	_ticks(server, clients, 1)
	t.check(battle.sim.events.any(func(e): return own.call(e, "shot") and e["side"] == "port"), "session: tick 1 fires port")
	_ticks(server, clients, 1)
	t.check(battle.sim.events.any(func(e): return own.call(e, "fire_rejected") and e["side"] == "port")
		and not battle.sim.events.any(func(e): return own.call(e, "shot")), "session: tick 2 is rejected (port empty)")
	_ticks(server, clients, 1)
	t.check(battle.sim.ships[FIRST]["weapons"]["starboard"]["ammo"] == "chain", "session: tick 3 cycles to chain")
	_ticks(server, clients, 1)
	t.check(battle.sim.ships[FIRST]["weapons"]["starboard"]["ammo"] == "grape", "session: tick 4 cycles to grape")
	t.check(rec_a.applied == 4 and rec_a.received == 4 and a.actions_sent == 4 and rec_a.actions.is_empty(),
		"session: applied == received == sent == 4")
	_pump(all, func(): return false, 30)
	var seen: int = _rec(a)["harbor"].size()
	t.check(_tick_until(server, clients, func(): return _rec(a)["harbor"].size() > seen, 70), "session: a harbor follows")
	t.check(_rec(a)["harbor"][seen]["actions_applied"] == 4 and a.actions_applied == 4, "session: harbor actions_applied == 4")
	# Events
	var shots_a: Array = _events_of(a, "shot").filter(func(e): return e["ship_id"] == FIRST)
	var shots_b: Array = _events_of(b, "shot").filter(func(e): return e["ship_id"] == FIRST)
	t.check(shots_a.size() == 4 and shots_a == shots_b and shots_a.all(func(e): return e["tick"] == first_tick),
		"session: A and B got identical shots stamped with tick %d" % first_tick)
	t.check(_events_of(a, "fire_rejected").size() == 1 and _events_of(b, "fire_rejected").is_empty(),
		"session: fire_rejected only to its owner")
	t.check(_ticks_ordered(_rec(a)["events"]) and _ticks_ordered(_rec(b)["events"]), "session: event ticks are ints, non-decreasing")
	_finish(server, clients)
	return true


func _test_defeat_and_victory(t) -> bool:
	var server = _server(t, 24766)
	var a = _client(24766, "Anne", "anne")
	var b = _client(24766, "Bonny", "bonny")
	var c = _client(24766, "Calico", "calico")
	var d = _client(24766, "Drake", "drake")
	var clients := [a, b, c, d]
	var all := [server] + clients
	_connect_all(t, server, clients)
	_start(t, server, clients, a, "duel_brig", "sloop")
	for other in [b, c, d]:
		_join(t, server, clients, other, 1, "sloop")
	_ticks(server, clients, 2)
	var battle = server.battles[1]
	t.check(battle.sim.ships.has(FIRST + 3), "session: four captains aboard")
	_sink(battle, FIRST + 2, 2)
	_sink(battle, FIRST + 3, 2)
	_ticks(server, clients, 1)
	t.check(_pump(all, func(): return not _rec(c)["outcomes"].is_empty() and not _rec(d)["outcomes"].is_empty()),
		"session: C and D get outcomes")
	_pump(all, func(): return false, 30)
	var outcome_c := {"t": "outcome", "battle_id": 1, "ship_id": FIRST + 2, "outcome": "sunk",
		"elapsed": battle.sim.outcomes[FIRST + 2]["elapsed"]}
	t.check(_rec(c)["outcomes"] == [outcome_c], "session: C gets exactly its own sunk (%s)" % [_rec(c)["outcomes"]])
	t.check(_rec(d)["outcomes"].size() == 1 and _rec(d)["outcomes"][0]["ship_id"] == FIRST + 3
		and _rec(d)["outcomes"][0]["outcome"] == "sunk", "session: D gets its own sunk")
	t.check(_rec(a)["outcomes"].is_empty() and _rec(b)["outcomes"].is_empty(), "session: A and B get no outcome")
	t.check(server.captain_by_id("calico").state == "spectating" and c.battle_id == 1 and not c.ship_active,
		"session: C spectates")
	var snaps: int = _rec(c)["snapshots"].size()
	_ticks(server, clients, 6)
	t.check(_pump(all, func(): return _rec(c)["snapshots"].size() > snaps), "session: the spectator still gets snapshots")
	c.join_battle(1, "sloop")
	t.check(_refusal(server, clients, c) == "no_reentry" and _rec(c)["refused"].size() == 1,
		"session: C rejoining -> no_reentry")
	d.leave_battle()
	t.check(d.battle_id == 0 and d.ship_id == 0, "session: leave clears the client's battle")
	t.check(_pump(all, func(): return server.captain_by_id("drake").state == "harbor"), "session: D is back in the harbor")
	t.check(battle.pending_ops.is_empty(), "session: a sunk captain's leave queues no op")
	_sink(battle, 2, FIRST)
	_ticks(server, clients, 1)
	var done := func(): return [a, b, c].all(func(x): return not _rec(x)["results"].is_empty())
	t.check(_pump(all, done), "session: A, B and C get the result")
	_pump(all, func(): return false, 30)
	t.check(_rec(a)["outcomes"].size() == 1 and _rec(a)["outcomes"][0]["outcome"] == "victory"
		and _rec(a)["outcomes"][0]["ship_id"] == FIRST, "session: A gets victory")
	t.check(_rec(b)["outcomes"].size() == 1 and _rec(b)["outcomes"][0]["outcome"] == "victory"
		and _rec(b)["outcomes"][0]["ship_id"] == FIRST + 1, "session: B gets victory")
	t.check(_rec(c)["outcomes"].size() == 1 and _rec(d)["outcomes"].size() == 1, "session: C and D get nothing more")
	var hashes := []
	for x in [a, b, c]:
		var results: Array = _rec(x)["results"]
		t.check(results.size() == 1 and results[0][0] == 1 and results[0][1]["outcome"] == "victory",
			"session: one victory battle_result each")
		hashes.append(Protocol.result_hash(results[0][1]) if results.size() == 1 else "")
	t.check(hashes[0] == hashes[1] and hashes[1] == hashes[2] and hashes[0] != "", "session: the same result for all")
	t.check(_rec(d)["results"].is_empty(), "session: D (left) gets no result")
	t.check(server.battles.is_empty(), "session: the battle is closed")
	t.check(clients.all(func(x): return x.battle_id == 0 and x.ship_id == 0), "session: every client battle_id == 0")
	t.check(server.captains.values().all(func(r): return r.battle_id == 0 and r.state == "harbor"), "session: every record in the harbor")
	t.check(_pump(all, func(): return clients.all(func(x): return _last_harbor(x).get("battles") == [])),
		"session: harbors list no battles")
	_finish(server, clients)
	return true


func _test_lost(t) -> bool:
	var server = _server(t, 24767)
	var a = _client(24767, "Anne", "anne")
	var all := [server, a]
	_connect_all(t, server, [a])
	_start(t, server, [a], a, "duel_sloop", "sloop")
	_ticks(server, [a], 2)
	var battle = server.battles[1]
	_sink(battle, FIRST, 2)
	_ticks(server, [a], 1)
	t.check(_pump(all, func(): return not _rec(a)["results"].is_empty()), "session: A gets the result")
	t.check(_rec(a)["outcomes"].size() == 1 and _rec(a)["outcomes"][0]["outcome"] == "sunk", "session: A's own outcome is sunk")
	t.check(_rec(a)["results"].size() == 1 and _rec(a)["results"][0][0] == 1 and _rec(a)["results"][0][1]["outcome"] == "lost",
		"session: battle_result lost")
	t.check(server.battles.is_empty() and a.battle_id == 0 and server.captain_by_id("anne").state == "harbor",
		"session: lost battle is closed")
	_finish(server, [a])
	return true


func _test_four_battles(t) -> bool:
	var server = _server(t, 24768)
	var clients := []
	for n in ["Anne", "Bonny", "Calico", "Drake"]:
		clients.append(_client(24768, n, n.to_lower()))
	var all := [server] + clients
	_connect_all(t, server, clients)
	var presets := ["duel_sloop", "duel_brig", "two_sloops", "frigate_escort"]
	for i in 4:
		_start(t, server, clients, clients[i], presets[i], "sloop")
	t.check(_sorted_keys(server.battles) == [1, 2, 3, 4] and clients.map(func(x): return x.battle_id) == [1, 2, 3, 4],
		"session: four battles 1-4")
	t.check(_pump(all, func(): return clients.all(func(x): return _last_harbor(x).get("can_start") == false)),
		"session: can_start is false at the cap")
	var a = clients[0]
	a.start_battle("duel_sloop", "sloop")
	t.check(_refusal(server, clients, a) == "battle_cap" and _rec(a)["refused"].size() == 1,
		"session: a fifth start -> battle_cap")
	var first = server.battles[1]
	t.check(server.battles.size() == 4 and a.battle_id == 1 and a.ship_active and first.has_active_ship("anne")
		and not first.pending_ops.any(func(op): return op["op"] == "abandon")
		and server.captain_by_id("anne").state == "in_battle", "session: A keeps its ship")
	_ticks(server, clients, 30)
	_pump(all, func(): return false, 30)
	t.check(server.battles.values().all(func(x): return x.tick == 30), "session: every battle at tick 30")
	for i in 4:
		var snaps: Array = _rec(clients[i])["snapshots"]
		t.check(not snaps.is_empty() and snaps.all(func(s): return s["battle_id"] == i + 1),
			"session: client %d sees only battle %d" % [i, i + 1])
	_finish(server, clients)
	return true


func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys
