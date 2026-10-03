extends RefCounted
## Phase 3 plan 02: session server and client over real localhost ENet (handshake, captains,
## harbor, stop). Nodes stay out of the tree; cases poll them by hand and free them at the end.

const SessionServer := preload("res://net/session_server.gd")
const SessionClient := preload("res://net/session_client.gd")
const VERSION := "0.7"


func run(t) -> bool:
	for test in [_test_auth_refusals, _test_harbor_captains, _test_full_and_replaced, _test_server_stop]:
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
