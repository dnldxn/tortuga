extends RefCounted
## Two-sloop escape rule integration; isolated positions test rules, not tactical reachability.

const NavalSimulation := preload("res://sim/naval_simulation.gd")
const DT := 1.0 / 60.0
const PLAYER_AT := Vector2(1000, 500)
const REQUIRED := 480


func run(t) -> bool:
	_test_arming(t)
	_test_clearance(t)
	_test_countdown_and_reset(t)
	_test_inactive_and_survivor(t)
	_test_combat_precedence(t)
	_test_practice(t)
	return true


func _fixture(d2: float, d3: float, preset := "two_sloops"):
	var sim = NavalSimulation.new()
	sim.reset(preset, "sloop")
	sim.ships[1]["position"] = PLAYER_AT
	sim.ships[2]["position"] = PLAYER_AT + Vector2(d2, 0)
	if sim.ships.has(3):
		sim.ships[3]["position"] = PLAYER_AT + Vector2(0, d3)
	for id in sim.ships:
		sim.ships[id]["heading"] = 0.0
	return sim


func _ticks(sim, count: int) -> void:
	for i in count:
		sim._update_escape(DT)


func _lethal(sim, owner: int, victim: int) -> void:
	sim.ships[victim]["hull"] = 1.0
	sim.projectiles.append({"id": sim.next_projectile_id, "owner_id": owner, "ammo": "round",
		"position": sim.ships[victim]["position"] - Vector2(0, 10), "direction": Vector2.DOWN,
		"remaining_range": 900.0, "owner_cleared": true})
	sim.next_projectile_id += 1


func _test_arming(t) -> void:
	var remote = _fixture(1600, 1600)
	_ticks(remote, 600)
	t.check(not remote.escape_armed and remote.escape_clear_ticks == 0 and remote.result.is_empty(),
		"remote two-sloop start never arms or escapes")
	for near_id in [2, 3]:
		for distance in [900.001, 900.0, 899.999]:
			var sim = _fixture(distance if near_id == 2 else 1600.0,
				distance if near_id == 3 else 1600.0)
			var actual: float = sim.ships[1]["position"].distance_squared_to(sim.ships[near_id]["position"])
			var within: bool = distance <= 900.0
			t.check((actual <= 900.0 * 900.0) == within,
				"enemy %d center squared distance %s straddles 900 exactly" % [near_id, distance])
			_ticks(sim, 1)
			t.check(sim.escape_armed == within and sim.escape_clear_ticks == 0,
				"enemy %d at %s arms=%s with other remote" % [near_id, distance, within])


func _test_clearance(t) -> void:
	for near_id in [2, 3]:
		for distance in [1399.999, 1400.0, 1400.001]:
			var sim = _fixture(distance if near_id == 2 else 2000.0,
				distance if near_id == 3 else 2000.0)
			sim.escape_armed = true
			sim.escape_clear_ticks = 5
			var actual: float = sim.ships[1]["position"].distance_squared_to(sim.ships[near_id]["position"])
			var clear: bool = distance > 1400.0
			t.check((actual > 1400.0 * 1400.0) == clear,
				"enemy %d center squared distance %s straddles 1400 exactly" % [near_id, distance])
			_ticks(sim, 1)
			t.check(sim.escape_clear_ticks == (6 if clear else 0) and sim.result.is_empty(),
				"enemy %d at %s %s countdown" % [near_id, distance, "advances" if clear else "resets"])


func _test_countdown_and_reset(t) -> void:
	var sim = _fixture(1600, 1600)
	sim.ships[2]["position"] = PLAYER_AT + Vector2(900, 0)
	_ticks(sim, 1)
	t.check(sim.escape_armed, "approach to only enemy 2 arms")
	sim.ships[2]["position"] = PLAYER_AT + Vector2(1600, 0)
	_ticks(sim, REQUIRED - 1)
	t.check(sim.escape_clear_ticks == 479 and sim.result.is_empty(),
		"both active enemies beyond 1400: 479 qualifying ticks remain pending")
	_ticks(sim, 1)
	t.check(sim.escape_clear_ticks == 480 and sim.result.get("outcome") == "escaped"
		and sim.ships[1]["active"] and sim.ships[2]["active"] and sim.ships[3]["active"],
		"both active enemies clear: tick 480 escapes with player and opposition alive")
	for pursuer in [2, 3]:
		var interrupted = _fixture(1600, 1600)
		interrupted.escape_armed = true
		_ticks(interrupted, 479)
		interrupted.ships[pursuer]["position"] = PLAYER_AT + (Vector2(1400, 0) if pursuer == 2 else Vector2(0, 1400))
		_ticks(interrupted, 1)
		t.check(interrupted.escape_armed and interrupted.escape_clear_ticks == 0 and interrupted.result.is_empty(),
			"nearer pursuer %d at 1400 resets 479 ticks" % pursuer)
		interrupted.ships[pursuer]["position"] = PLAYER_AT + (Vector2(1600, 0) if pursuer == 2 else Vector2(0, 1600))
		_ticks(interrupted, 479)
		t.check(interrupted.result.is_empty(), "pursuer %d re-entry requires full new interval" % pursuer)
		_ticks(interrupted, 1)
		t.check(interrupted.result.get("outcome") == "escaped", "pursuer %d clear for 480 new ticks escapes" % pursuer)


func _test_inactive_and_survivor(t) -> void:
	for inactive_id in [2, 3]:
		var sim = _fixture(1600, 1600)
		sim.ships[inactive_id]["active"] = false
		sim.ships[inactive_id]["position"] = PLAYER_AT + (Vector2(100, 0) if inactive_id == 2 else Vector2(0, 100))
		_ticks(sim, 1)
		t.check(not sim.escape_armed, "inactive nearby enemy %d cannot arm" % inactive_id)
		sim.escape_armed = true
		_ticks(sim, 479)
		t.check(sim.escape_clear_ticks == 479 and sim.result.is_empty(),
			"inactive nearby enemy %d ignored; survivor beyond 1400 keeps 479 pending" % inactive_id)
		_ticks(sim, 1)
		t.check(sim.result.get("outcome") == "escaped", "survivor alone is enough to escape with enemy %d inactive" % inactive_id)
	var killed = _fixture(2000, 1400)
	killed.escape_armed = true
	killed.escape_clear_ticks = 479
	_lethal(killed, 1, 2)
	killed.step(DT, {})
	t.check(not killed.ships[2]["active"] and killed.ships[3]["active"]
		and killed.result.is_empty() and killed.escape_clear_ticks == 0,
		"one defeated enemy does not end battle; surviving nearer pursuer resets progress")
	killed.ships[3]["position"] = killed.ships[1]["position"] + Vector2(0, 1600)
	killed.step(DT, {})
	t.check(killed.escape_clear_ticks == 1 and killed.result.is_empty(),
		"defeated enemy excluded; surviving distant enemy alone advances countdown")


func _test_combat_precedence(t) -> void:
	for scenario in ["last_kill", "last_and_player", "player_with_survivor"]:
		var sim = _fixture(2000, 2000)
		sim.escape_armed = true
		sim.escape_clear_ticks = 479
		if scenario != "player_with_survivor":
			sim.ships[2]["active"] = false
			sim.ships[2]["defeat_reasons"] = ["sunk"]
			_lethal(sim, 1, 3)
		if scenario != "last_kill":
			_lethal(sim, 3, 1)
		sim.step(DT, {})
		var want := "victory" if scenario == "last_kill" else "draw" if scenario == "last_and_player" else "defeat"
		t.check(sim.result.get("outcome") == want and sim.escape_clear_ticks == 479,
			"%s on completing tick resolves %s before escape" % [scenario, want])
		t.check(sim.result.get("defeated", []).size() == (3 if scenario == "last_and_player" else 2 if scenario == "last_kill" else 1),
			"%s preserves defeated ship identities" % scenario)


func _test_practice(t) -> void:
	var sim = _fixture(500, 0, "practice")
	sim.step(DT, {})
	t.check(not sim.escape_armed, "practice target proximity does not arm")
	sim.escape_armed = true
	sim.escape_clear_ticks = 479
	sim.ships[2]["position"] = PLAYER_AT + Vector2(2000, 0)
	sim.step(DT, {})
	t.check(not sim.escape_armed and sim.escape_clear_ticks == 0 and sim.result.is_empty(),
		"practice cannot complete escape even with injected progress")
