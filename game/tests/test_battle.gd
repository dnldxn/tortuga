extends RefCounted
## Phase 3 plan 02 task 2: the server-side battle wrapper (membership guards, outcomes, tape replay).

const Battle := preload("res://net/battle.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const DT := 1.0 / 60.0
const FIRST := NavalSimulation.FIRST_CAPTAIN_SHIP_ID


func run(t) -> bool:
	for test in [_test_membership, _test_tape_replay]:
		t.check(test.call(t) == true, "battle wrapper: %s completed" % test.get_method())
	return true


## Hull 1 plus an owner's round shot at the ship's own position, so the next step sinks it.
func _sink(b, ship_id: int, owner_id: int) -> void:
	var sim = b.sim
	sim.ships[ship_id]["hull"] = 1.0
	sim.projectiles.append({"id": sim.next_projectile_id, "owner_id": owner_id, "ammo": "round",
		"position": sim.ships[ship_id]["position"], "direction": Vector2.RIGHT,
		"remaining_range": 900.0, "owner_cleared": true})
	sim.next_projectile_id += 1


func _test_membership(t) -> bool:
	var b = Battle.new(7, "duel_sloop")
	t.check(b.battle_id == 7 and b.preset_id == "duel_sloop", "battle wrapper: id and preset kept")
	t.check(b.add_captain("a", "Anne", 0, "sloop") == FIRST, "battle wrapper: first captain gets FIRST")
	t.check(b.add_captain("b", "Bonny", 1, "brig") == FIRST + 1, "battle wrapper: ship ids count up")
	t.check(b.has_active_ship("a") and b.has_active_ship("b"), "battle wrapper: add pending counts as active")
	t.check(not b.has_active_ship("zz"), "battle wrapper: unknown captain has no ship")
	t.check(b.add_captain("a", "Again", 2, "sloop") == -1, "battle wrapper: second add for a captain is refused")
	t.check(b.pending_ops.size() == 2, "battle wrapper: refused add queues nothing")
	b.advance(DT, {})
	t.check(b.tick == 1, "battle wrapper: tick counts completed steps")
	t.check(b.sim.ships[FIRST]["team"] == NavalSimulation.TEAM_PLAYER
		and b.sim.ships[FIRST + 1]["team"] == NavalSimulation.TEAM_PLAYER, "battle wrapper: captains are TEAM_PLAYER")
	t.check(b.ai_left() == 1, "battle wrapper: one AI ship left")
	t.check(b.captain_names() == ["Anne", "Bonny"], "battle wrapper: captain_names by ship id")
	var heading_a: float = b.sim.ships[FIRST]["heading"]
	var heading_b: float = b.sim.ships[FIRST + 1]["heading"]
	b.advance(DT, {FIRST: {"turn": 1.0}})
	t.check(b.sim.ships[FIRST]["heading"] != heading_a, "battle wrapper: command turns its own ship")
	t.check(b.sim.ships[FIRST + 1]["heading"] == heading_b, "battle wrapper: other captain unaffected")
	b.linger("a")
	b.linger("a")
	t.check(b.pending_ops.size() == 1 and b.is_lingering("a") and b.lingering.has(FIRST),
		"battle wrapper: linger twice queues one op")
	b.reclaim("a", "Anne2", 0)
	t.check(b.names[FIRST]["name"] == "Anne2" and not b.is_lingering("a"), "battle wrapper: reclaim renames")
	b.reclaim("a", "Anne3", 0)
	t.check(b.pending_ops.size() == 2, "battle wrapper: reclaim without linger queues nothing")
	t.check(b.advance(DT, {}) == [] and not b.sim.ships[FIRST]["lingering"], "battle wrapper: linger+reclaim in one tick")
	b.abandon("b")
	t.check(not b.has_active_ship("b") and b.barred.has("b"), "battle wrapper: abandon bars at once")
	b.abandon("b")
	t.check(b.pending_ops.size() == 1, "battle wrapper: second abandon queues nothing")
	var out: Array = b.advance(DT, {})
	t.check(out == [{"ship_id": FIRST + 1, "captain_id": "b", "outcome": "abandoned", "elapsed": b.sim.elapsed}],
		"battle wrapper: abandon returns its outcome (%s)" % [out])
	t.check(b.advance(DT, {}) == [], "battle wrapper: outcome reported once")
	t.check(b.captain_names() == ["Anne2"], "battle wrapper: abandoned captain leaves captain_names")
	_sink(b, FIRST, 2)
	out = b.advance(DT, {})
	t.check(out.size() == 1 and out[0]["ship_id"] == FIRST and out[0]["captain_id"] == "a"
		and out[0]["outcome"] == "sunk", "battle wrapper: sunk outcome (%s)" % [out])
	t.check(b.barred.has("a") and not b.has_active_ship("a"), "battle wrapper: sunk captain is barred")
	b.linger("a")
	b.abandon("a")
	b.reclaim("a", "x", 0)
	t.check(b.pending_ops.is_empty(), "battle wrapper: barred captain queues nothing")
	return true


func _test_tape_replay(t) -> bool:
	var b = Battle.new(1, "duel_sloop")
	b.record_tape = true
	b.add_captain("a", "Anne", 0, "sloop")
	b.add_captain("b", "Bonny", 1, "brig")
	for step in 300:
		var commands := {}
		if step < 60:
			commands = {FIRST: {"turn": 1.0}, FIRST + 1: {"turn": -1.0}}
		elif step == 60:
			commands = {FIRST: {"fire_port": true}}
		if step == 100:
			b.linger("a")
		elif step == 160:
			b.reclaim("a", "Anne2", 0)
		elif step == 200:
			b.abandon("b")
		b.advance(DT, commands)
	t.check(b.tape.size() == 300 and b.tick == 300, "battle wrapper: tape has one entry per step")
	var replay = NavalSimulation.new()
	replay.reset_battle("duel_sloop")
	for entry in b.tape:
		replay.step(DT, entry["commands"], entry["ops"])
	t.check(var_to_bytes(replay.ships) == var_to_bytes(b.sim.ships), "battle wrapper: replay ships identical")
	t.check(var_to_bytes(replay.outcomes) == var_to_bytes(b.sim.outcomes), "battle wrapper: replay outcomes identical")
	t.check(replay.elapsed == b.sim.elapsed, "battle wrapper: replay elapsed identical")
	t.check(b.sim.outcomes.has(FIRST + 1), "battle wrapper: tape included the abandon")
	return true
