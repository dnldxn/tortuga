extends RefCounted
## Phase 3 plan 02 task 1: wire protocol, compact snapshots, steering staleness, CLI parsing and
## result hashing. Expected ERROR lines come from deliberately bad bytes_to_var input.

const Protocol := preload("res://net/protocol.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const DT := 1.0 / 60.0
const FIRST := NavalSimulation.FIRST_CAPTAIN_SHIP_ID


func run(t) -> bool:
	for test in [_test_messages, _test_snapshot, _test_steer_turn, _test_result_hash, _test_cli]:
		t.check(test.call(t) == true, "protocol: %s completed" % test.get_method())
	return true


func _kind0(value, with_objects := false) -> PackedByteArray:
	var bytes := PackedByteArray([Protocol.KIND_MESSAGE])
	bytes.append_array(var_to_bytes_with_objects(value) if with_objects else var_to_bytes(value))
	return bytes


func _test_messages(t) -> bool:
	t.check(Protocol.build_version() == "dev", "protocol: build_version is dev without a stamp")
	var msg := {"t": "action", "action": "fire_port", "n": 3}
	t.check(Protocol.decode_message(Protocol.encode_message(msg)) == msg, "protocol: action message round-trips")
	t.check(Protocol.encode_message(msg)[0] == Protocol.KIND_MESSAGE, "protocol: message kind byte")
	for bad in [PackedByteArray(), PackedByteArray([0]), PackedByteArray([7, 1, 2]),
			_kind0([1, 2]), _kind0({"x": 1}), _kind0({"t": 5}), _kind0({"t": RefCounted.new()}, true)]:
		t.check(Protocol.decode_message(bad).is_empty(), "protocol: bad message bytes decode to {} (%s)" % [bad])
	return true


func _battle_sim():
	var sim = NavalSimulation.new()
	sim.reset_battle("frigate_escort")
	var ops := []
	for c in [[FIRST, "sloop"], [FIRST + 1, "brig"], [FIRST + 2, "frigate"], [FIRST + 3, "sloop"]]:
		ops.append({"op": "add_captain", "ship_id": c[0], "vessel_id": c[1]})
	sim.step(DT, {}, ops)
	for i in 60:
		sim.step(DT, {
			FIRST: {"fire_port": i == 0, "turn": 1.0},
			FIRST + 1: {"toggle_sails": i == 0},
			FIRST + 2: {"fire_starboard": i == 30},
		}, [{"op": "linger", "ship_id": FIRST + 3}] if i == 0 else [])
	sim.ships[FIRST + 2]["escape_armed"] = true
	sim.ships[FIRST + 2]["escape_clear_ticks"] = 7
	return sim


func _test_snapshot(t) -> bool:
	var sim = _battle_sim()
	var bytes := Protocol.encode_snapshot(3, sim, 61)
	var snap := Protocol.decode_snapshot(bytes)
	t.check(not snap.is_empty(), "protocol: snapshot decodes")
	t.check(snap.get("battle_id") == 3 and snap.get("tick") == 61, "protocol: snapshot battle_id and tick")
	t.near(snap.get("elapsed", -1.0), sim.elapsed, 1e-4, "protocol: snapshot elapsed")
	t.near(snap.get("wind_heading", -9.0), sim.wind_heading, 1e-4, "protocol: snapshot wind_heading")
	t.check(snap.get("preset_id") == "frigate_escort", "protocol: snapshot preset_id")
	var ids: Array = sim.ships.keys()
	ids.sort()
	var got_ids: Array = snap.get("ships", {}).keys()
	got_ids.sort()
	t.check(got_ids == ids, "protocol: snapshot ship ids match the sim")
	for id in ids:
		if not snap["ships"].has(id):
			continue
		var want: Dictionary = sim.ships[id]
		var got: Dictionary = snap["ships"][id]
		var want_keys: Array = want.keys()
		var got_keys: Array = got.keys()
		want_keys.sort()
		got_keys.sort()
		t.check(got_keys == want_keys, "protocol: ship %d has exactly the sim keys" % id)
		for key in want_keys:
			if got.has(key):
				t.check(typeof(got[key]) == typeof(want[key]), "protocol: ship %d key %s type" % [id, key])
		for key in ["id", "team", "role", "vessel_id", "reefed", "active", "defeat_reasons",
				"escape_armed", "escape_clear_ticks", "lingering", "linger_ticks", "position"]:
			t.check(got.get(key) == want[key], "protocol: ship %d %s exact" % [id, key])
		for key in ["heading", "speed", "hull", "sails", "crew"]:
			t.near(got.get(key, -1e9), want[key], 1e-3, "protocol: ship %d %s" % [id, key])
		for side in ["port", "starboard"]:
			t.check(got["weapons"][side]["ammo"] == want["weapons"][side]["ammo"], "protocol: ship %d %s ammo" % [id, side])
			var want_loads: Array = want["weapons"][side]["loads"]
			var got_loads: Array = got["weapons"][side]["loads"]
			t.check(got_loads.size() == want_loads.size(), "protocol: ship %d %s gun count" % [id, side])
			for i in mini(want_loads.size(), got_loads.size()):
				if want_loads[i] == 1.0:
					t.check(got_loads[i] == 1.0, "protocol: ship %d %s gun %d full stays exact" % [id, side, i])
				else:
					t.check(got_loads[i] < 1.0 and absf(got_loads[i] - want_loads[i]) <= 1.0 / 255.0,
						"protocol: ship %d %s gun %d partial load" % [id, side, i])
		t.check(got.get("lingering") == (id == FIRST + 3), "protocol: lingering only on the lingering captain")
		t.check(got.get("escape_armed") == (id == FIRST + 2) and (id != FIRST + 2 or got.get("escape_clear_ticks") == 7),
			"protocol: escape_armed and ticks only on the escaping captain")
	t.check(snap["ships"][FIRST]["weapons"]["port"]["loads"].any(func(l): return l < 1.0),
		"protocol: fired port guns are partially loaded")
	var shots: Array = snap.get("projectiles", [])
	t.check(shots.size() > 0 and shots.size() == sim.projectiles.size(), "protocol: projectiles decoded")
	var last := -1
	for i in mini(shots.size(), sim.projectiles.size()):
		t.check(shots[i]["id"] > last, "protocol: projectile ids ascend")
		last = shots[i]["id"]
		t.check(shots[i]["id"] == sim.projectiles[i]["id"] and shots[i]["owner_id"] == sim.projectiles[i]["owner_id"]
			and shots[i]["ammo"] == sim.projectiles[i]["ammo"], "protocol: projectile id/owner/ammo exact")
		t.check(shots[i]["position"].distance_to(sim.projectiles[i]["position"]) < 1e-3, "protocol: projectile position")
	print("  snapshot frigate_escort + 4 captains + %d projectiles: %d bytes" % [shots.size(), bytes.size()])
	t.check(bytes.size() <= 1200, "protocol: snapshot fits in 1200 bytes")
	t.check(Protocol.decode_snapshot(bytes.slice(0, bytes.size() - 1)).is_empty(), "protocol: truncated snapshot rejected")
	var longer := bytes.duplicate()
	longer.append(0)
	t.check(Protocol.decode_snapshot(longer).is_empty(), "protocol: trailing byte rejected")
	t.check(Protocol.decode_snapshot(PackedByteArray()).is_empty(), "protocol: empty snapshot rejected")
	t.check(Protocol.decode_snapshot(Protocol.encode_message({"t": "x"})).is_empty(), "protocol: message is not a snapshot")
	return true


func _test_steer_turn(t) -> bool:
	t.check(Protocol.steer_turn(1, 1000, 1500) == 1, "protocol: steer fresh at the limit")
	t.check(Protocol.steer_turn(1, 1000, 1501) == 0, "protocol: steer stale after 500 ms")
	t.check(Protocol.steer_turn(-1, 1000, 1200) == -1, "protocol: steer left")
	t.check(Protocol.steer_turn(5, 0, 0) == 1, "protocol: steer clamped")
	return true


func _test_result_hash(t) -> bool:
	var r := {"outcome": "victory", "elapsed": 12.5, "outcomes": {
		FIRST: {"outcome": "victory", "elapsed": 12.5}, FIRST + 1: {"outcome": "sunk", "elapsed": 9.0}}}
	var h := Protocol.result_hash(r)
	var hex := RegEx.create_from_string("^[0-9a-f]{64}$")
	t.check(hex.search(h) != null, "protocol: result hash is 64 lowercase hex")
	var reordered := {"outcomes": {FIRST + 1: {"elapsed": 9.0, "outcome": "sunk"},
		FIRST: {"elapsed": 12.5, "outcome": "victory"}}, "elapsed": 12.5, "outcome": "victory"}
	t.check(Protocol.result_hash(reordered) == h, "protocol: result hash ignores key order")
	t.check(Protocol.result_hash(bytes_to_var(var_to_bytes(r))) == h, "protocol: result hash survives var round trip")
	var changed: Dictionary = r.duplicate(true)
	changed["outcomes"][FIRST + 1]["outcome"] = "disabled"
	t.check(Protocol.result_hash(changed) != h, "protocol: result hash changes with an outcome")
	return true


func _test_cli(t) -> bool:
	t.check(Protocol.parse_cli(PackedStringArray(["--server", "--port", "24681", "--bot"]))
		== {"server": true, "port": "24681", "bot": true}, "protocol: parse_cli")
	return true
