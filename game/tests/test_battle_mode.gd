extends RefCounted
## Multi-captain battle mode (Phase 3 plan 01): group presets, battle reset, captain ops, drop-in,
## linger/reclaim/abandon, per-captain escape, outcomes and the battle result.
## Invalid-op ERROR lines in the output are deliberate.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const AIController := preload("res://sim/ai_controller.gd")
const DT := 1.0 / 60.0
const GROUP_PRESETS := {
	"brig_squadron": {
		"label": "Brig squadron", "wind_heading": PI / 2.0,
		"opposition": [[2, "brig", Vector2(3900, 1500)], [3, "brig", Vector2(3900, 2100)], [4, "brig", Vector2(3900, 2700)]],
	},
	"frigate_escort": {
		"label": "Frigate escort", "wind_heading": -PI / 2.0,
		"opposition": [[2, "frigate", Vector2(4100, 2100)], [3, "sloop", Vector2(3700, 1600)], [4, "sloop", Vector2(3700, 2600)]],
	},
}
const NEW_SHIP_KEYS := {"escape_armed": false, "escape_clear_ticks": 0, "lingering": false, "linger_ticks": 0}


func run(t) -> bool:
	for test in [_test_definitions, _test_reset_battle, _test_first_captain, _test_drop_in, _test_invalid_ops,
			_test_linger_neutral_and_sunk, _test_linger_expiry, _test_reclaim, _test_linger_no_escape, _test_abandon,
			_test_captain_escape, _test_battle_results, _test_offline_escape_mirror, _test_determinism,
			_test_group_presets_to_result]:
		t.check(test.call(t) == true, "battle: %s completed" % test.get_method())
	return true


## reset_battle, then one step adding each [id, vessel] in order.
func _battle(preset_id: String, captains: Array):
	var sim = NavalSimulation.new()
	sim.reset_battle(preset_id)
	var ops := []
	for c in captains:
		ops.append({"op": "add_captain", "ship_id": c[0], "vessel_id": c[1]})
	sim.step(DT, {}, ops)
	return sim


## One step with a single op.
func _op(sim, op, commands := {}) -> void:
	sim.step(DT, commands, [op])


## Sails to 0 on every ship except `keep`: ships turn but never move.
func _becalm(sim, keep := -1) -> void:
	for id in sim.ships:
		if id != keep:
			sim.ships[id]["sails"] = 0.0


## Owner's round shot 10 units above the victim, moving into it; the victim's hull is set to 1.
func _lethal(sim, owner: int, victim: int) -> void:
	sim.ships[victim]["hull"] = 1.0
	sim.projectiles.append({"id": sim.next_projectile_id, "owner_id": owner, "ammo": "round",
		"position": sim.ships[victim]["position"] - Vector2(0, 10), "direction": Vector2.DOWN,
		"remaining_range": 900.0, "owner_cleared": true})
	sim.next_projectile_id += 1


## AI fixtures only: the ship is a sunk wreck without going through a step.
func _sink(sim, id: int) -> void:
	var ship: Dictionary = sim.ships[id]
	ship["active"] = false
	ship["hull"] = 0.0
	ship["speed"] = 0.0
	ship["defeat_reasons"] = ["sunk"]


## Brig captains 100 and 101, becalmed except `keep`; 101 at (3300, 1500), 600 from AI 2,
## keeps the battle running and never escapes.
func _fixture(keep := -1):
	var sim = _battle("brig_squadron", [[100, "brig"], [101, "brig"]])
	_becalm(sim, keep)
	sim.ships[101]["position"] = Vector2(3300, 1500)
	return sim


func _steps(sim, n: int, commands := {}) -> void:
	for i in n:
		sim.step(DT, commands)


func _has_event(sim, event: Dictionary) -> bool:
	return sim.events.any(func(e): return e == event)


func _snapshot(sim) -> Dictionary:
	return {
		"ships": sim.ships.duplicate(true), "projectiles": sim.projectiles.duplicate(true),
		"events": sim.events.duplicate(true), "elapsed": sim.elapsed, "result": sim.result.duplicate(true),
		"outcomes": sim.outcomes.duplicate(true), "battle_mode": sim.battle_mode, "preset_id": sim.preset_id,
		"captain_ids": sim._captain_ids.duplicate(true),
	}


func _expected_opposition(preset_id: String) -> Dictionary:
	var ships := {}
	for s in Definitions.PRESETS[preset_id]["opposition"]:
		ships[s["id"]] = NavalSimulation.make_ship(s["id"], s["team"], s["vessel_id"], s["position"], s["heading"], s["role"])
	return ships


func _test_definitions(t) -> bool:
	t.check(Definitions.BATTLE_PRESETS == ["duel_sloop", "duel_brig", "duel_frigate", "two_sloops", "brig_squadron", "frigate_escort"],
		"BATTLE_PRESETS lists the 4 combat presets then the 2 group presets")
	t.check(not "practice" in Definitions.BATTLE_PRESETS, "practice is never a battle preset")
	t.check(Definitions.MAX_CAPTAINS == 4 and Definitions.MAX_BATTLES == 4, "captain and battle caps are 4")
	t.check(Definitions.LINGER_SECONDS == 30.0, "linger grace is 30 s")
	t.check(Definitions.DROP_IN == {"margin": 200.0}, "drop-in margin is 200")
	for preset_id in Definitions.BATTLE_PRESETS:
		var preset: Dictionary = Definitions.PRESETS.get(preset_id, {})
		t.check(preset.get("label", "") is String and preset.get("label", "") != "", "%s has a label" % preset_id)
	var labels := {"duel_sloop": "Sloop duel", "duel_brig": "Brig duel", "duel_frigate": "Frigate duel", "two_sloops": "Two-ship encounter"}
	for preset_id in labels:
		t.check(Definitions.PRESETS[preset_id].get("label") == labels[preset_id], "%s label is %s" % [preset_id, labels[preset_id]])
	for preset_id in Definitions.PRESETS:
		t.check(Definitions.PRESETS[preset_id].get("multiplayer_only", false) == GROUP_PRESETS.has(preset_id),
			"%s multiplayer_only only on group presets" % preset_id)
	for preset_id in GROUP_PRESETS:
		var want: Dictionary = GROUP_PRESETS[preset_id]
		var preset: Dictionary = Definitions.PRESETS.get(preset_id, {})
		t.check(not preset.is_empty(), "%s registered" % preset_id)
		if preset.is_empty():
			continue
		t.check(preset["label"] == want["label"] and preset["multiplayer_only"] == true, "%s label and multiplayer_only" % preset_id)
		t.check(preset["wind_heading"] == want["wind_heading"], "%s beam wind" % preset_id)
		t.check(preset["player_position"] == Vector2(2200, 2100) and preset["player_heading"] == 0.0,
			"%s first captain at (2200, 2100) heading 0" % preset_id)
		var opposition: Array = preset["opposition"]
		t.check(opposition.size() == 3, "%s has 3 AI ships" % preset_id)
		for i in mini(opposition.size(), 3):
			var s: Dictionary = opposition[i]
			t.check(s["id"] == want["opposition"][i][0] and s["vessel_id"] == want["opposition"][i][1]
				and s["position"] == want["opposition"][i][2] and s["team"] == 1 and s["role"] == "ship" and s["heading"] == PI,
				"%s AI %d matches the table" % [preset_id, want["opposition"][i][0]])
			var r: float = Definitions.VESSELS[s["vessel_id"]]["radius"]
			t.check(Definitions.safe_bounds(r).has_point(s["position"]), "%s AI %d inside safe bounds" % [preset_id, s["id"]])
			t.check(preset["player_position"].distance_to(s["position"]) > Definitions.ESCAPE_DISTANCE,
				"%s first captain beyond ESCAPE_DISTANCE of AI %d" % [preset_id, s["id"]])
			for j in range(i + 1, opposition.size()):
				var o: Dictionary = opposition[j]
				var min_gap: float = r + Definitions.VESSELS[o["vessel_id"]]["radius"] + Definitions.AI["ship_clearance"]
				t.check(s["position"].distance_to(o["position"]) > min_gap, "%s AI %d/%d spaced apart" % [preset_id, s["id"], o["id"]])
		t.check(Definitions.safe_bounds(Definitions.VESSELS["frigate"]["radius"]).has_point(preset["player_position"]),
			"%s first captain inside frigate safe bounds" % preset_id)
	return true


func _test_reset_battle(t) -> bool:
	for preset_id in Definitions.BATTLE_PRESETS:
		var sim = NavalSimulation.new()
		sim.reset_battle(preset_id)
		t.check(sim.battle_mode and sim.preset_id == preset_id and sim.selected_vessel_id == "", "%s: battle mode, preset, no vessel" % preset_id)
		t.check(sim.wind_heading == Definitions.PRESETS[preset_id]["wind_heading"] and sim.elapsed == 0.0, "%s: wind and clock" % preset_id)
		t.check(sim.result.is_empty() and sim.outcomes.is_empty() and sim.projectiles.is_empty() and sim.events.is_empty(),
			"%s: empty result, outcomes, projectiles and events" % preset_id)
		t.check(sim.ships == _expected_opposition(preset_id), "%s: ships are exactly the AI fleet" % preset_id)
		t.check(sim.ships.keys().all(func(id): return id >= 2 and id < NavalSimulation.FIRST_CAPTAIN_SHIP_ID), "%s: no captain ship" % preset_id)
		for id in sim.ships:
			for key in NEW_SHIP_KEYS:
				t.check(sim.ships[id].has(key) and sim.ships[id][key] == NEW_SHIP_KEYS[key] and typeof(sim.ships[id][key]) == typeof(NEW_SHIP_KEYS[key]),
					"%s: ship %d %s default" % [preset_id, id, key])
	var sim = _battle("brig_squadron", [[100, "brig"]])
	sim.outcomes = {100: {"outcome": "victory", "elapsed": 1.0}}  # stand-in: Task 3 records outcomes
	var before := _snapshot(sim)
	for bad in ["practice", "nope"]:
		sim.reset_battle(bad)
		t.check(_snapshot(sim) == before, "reset_battle('%s') rejected, state intact" % bad)
	sim.reset("duel_sloop", "brig")
	t.check(not sim.battle_mode and sim.outcomes.is_empty() and sim._captain_ids.is_empty(), "offline reset leaves battle mode")
	t.check(sim.ships.keys() == [1, 2] and sim.selected_vessel_id == "brig", "offline reset builds player 1 and AI 2")
	for key in NEW_SHIP_KEYS:
		t.check(sim.ships[1][key] == NEW_SHIP_KEYS[key], "offline player %s default" % key)
	return true


func _test_first_captain(t) -> bool:
	var sim = NavalSimulation.new()
	sim.reset_battle("brig_squadron")
	_op(sim, {"op": "add_captain", "ship_id": 100, "vessel_id": "brig"})
	t.check(sim.events == [{"type": "captain_joined", "ship_id": 100, "position": Vector2(2200, 2100), "heading": 0.0, "vessel_id": "brig"}],
		"first captain: exactly one captain_joined event at the preset spot")
	var ship: Dictionary = sim.ships.get(100, {})
	t.check(not ship.is_empty(), "captain 100 present")
	if ship.is_empty():
		return true
	var brig: Dictionary = Definitions.VESSELS["brig"]
	t.check(ship["team"] == NavalSimulation.TEAM_PLAYER and ship["role"] == "ship" and ship["active"] and ship["vessel_id"] == "brig",
		"captain 100 is an active player-team brig")
	t.check(ship["hull"] == brig["hull"] and ship["sails"] == brig["sails"] and ship["crew"] == brig["crew"], "captain 100 full brig tracks")
	t.check(ship["position"].x > 2200.0, "captain 100 sailed in its join step")
	t.check(sim._captain_ids.has(100) and sim.ships.keys().size() == 4, "captain 100 recorded; AI fleet kept")
	return true


## Brig captain 100 becalmed at (1000, 1800), then sloop 101 joins; returns the join event.
func _drop_in_case(sim) -> Dictionary:
	_op(sim, {"op": "add_captain", "ship_id": 101, "vessel_id": "sloop"})
	var joined: Array = sim.events.filter(func(e): return e["type"] == "captain_joined")
	return joined[0] if joined.size() == 1 else {}


func _drop_in_fixture():
	var sim = _battle("brig_squadron", [[100, "brig"]])
	_becalm(sim)
	sim.ships[100]["position"] = Vector2(1000, 1800)
	return sim


func _check_drop_in(t, event: Dictionary, sim, want: Vector2, label: String) -> void:
	t.check(event.get("ship_id") == 101 and event.get("vessel_id") == "sloop", "%s: sloop 101 joined" % label)
	t.check(event.get("position") == want, "%s: dropped in at %s (got %s)" % [label, want, event.get("position")])
	t.check(event.get("heading") == (Definitions.ARENA_SIZE / 2.0 - want).angle(), "%s: heading toward arena center" % label)
	t.check(sim.ships.has(101) and sim.ships[101]["team"] == NavalSimulation.TEAM_PLAYER, "%s: ship 101 is a captain ship" % label)


func _test_drop_in(t) -> bool:
	var c: Array = NavalSimulation.drop_in_candidates(27.5)
	t.check(c.size() == 16, "16 drop-in candidates")
	t.check(c[0] == Vector2(890.625, 187.5) and c[9] == Vector2(3703.125, 4012.5) and c[14] == Vector2(187.5, 1621.875),
		"candidates clockwise from the top-left corner")
	# (a) nearest qualifying candidate to the captain centroid
	var sim = _drop_in_fixture()
	_check_drop_in(t, _drop_in_case(sim), sim, c[14], "nearest qualifying")
	# (b) AI 2 close to the west edge disqualifies c[13..15]
	sim = _drop_in_fixture()
	sim.ships[2]["position"] = Vector2(300, 1600)
	_check_drop_in(t, _drop_in_case(sim), sim, c[0], "out of range")
	# (c) nothing qualifies: farthest from its nearest active AI
	sim = _drop_in_fixture()
	for k in 16:
		var pos: Vector2 = c[k] if k != 9 else c[9] + Vector2(0, -600)
		sim.ships[10 + k] = NavalSimulation.make_ship(10 + k, NavalSimulation.TEAM_OPPOSITION, "sloop", pos, 0.0)
	_becalm(sim)
	_check_drop_in(t, _drop_in_case(sim), sim, c[9], "fallback")
	# Ops apply in list order against op-time state: two joins both land; a repeated id in one list is rejected.
	sim = _drop_in_fixture()
	sim.step(DT, {}, [{"op": "add_captain", "ship_id": 101, "vessel_id": "sloop"}, {"op": "add_captain", "ship_id": 102, "vessel_id": "sloop"},
		{"op": "add_captain", "ship_id": 101, "vessel_id": "brig"}])
	var joined: Array = sim.events.filter(func(e): return e["type"] == "captain_joined")
	t.check(joined.size() == 2 and joined[0]["ship_id"] == 101 and joined[1]["ship_id"] == 102, "two joins in list order")
	t.check(sim.ships.has(101) and sim.ships[101]["vessel_id"] == "sloop", "a repeated id in the same op list is rejected")
	return true


func _test_invalid_ops(t) -> bool:
	var cases := [
		["add_captain 100 again while present", {"op": "add_captain", "ship_id": 100, "vessel_id": "sloop"}],
		["unknown op", {"op": "teleport", "ship_id": 100}],
		["non-Dictionary op", "add_captain"],
		["captain id below 100", {"op": "add_captain", "ship_id": 99, "vessel_id": "sloop"}],
		["float captain id", {"op": "add_captain", "ship_id": 101.0, "vessel_id": "sloop"}],
		["unknown vessel", {"op": "add_captain", "ship_id": 101, "vessel_id": "unknown_ship"}],
		["missing vessel", {"op": "add_captain", "ship_id": 101}],
		["linger an AI ship", {"op": "linger", "ship_id": 2}],
		["linger an unknown id", {"op": "linger", "ship_id": 555}],
		["linger a float id", {"op": "linger", "ship_id": 100.0}],
		["linger without ship_id", {"op": "linger"}],
		["reclaim an AI ship", {"op": "reclaim", "ship_id": 2}],
		["reclaim a non-lingering ship", {"op": "reclaim", "ship_id": 100}],
		["abandon an AI ship", {"op": "abandon", "ship_id": 3}],
		["abandon an unknown id", {"op": "abandon", "ship_id": 555}],
		["second linger never extends the grace", {"op": "linger", "ship_id": 100}, [{"op": "linger", "ship_id": 100}]],
		["linger a removed captain", {"op": "linger", "ship_id": 100},
			[{"op": "add_captain", "ship_id": 101, "vessel_id": "sloop"}, {"op": "abandon", "ship_id": 100}]],
		["abandon a removed captain", {"op": "abandon", "ship_id": 100},
			[{"op": "add_captain", "ship_id": 101, "vessel_id": "sloop"}, {"op": "abandon", "ship_id": 100}]],
		["add_captain reusing a removed captain id", {"op": "add_captain", "ship_id": 100, "vessel_id": "brig"},
			[{"op": "add_captain", "ship_id": 101, "vessel_id": "sloop"}, {"op": "abandon", "ship_id": 100}]],
	]
	for case in cases:
		var a = _battle("brig_squadron", [[100, "brig"]])
		var b = _battle("brig_squadron", [[100, "brig"]])
		if case.size() > 2:
			a.step(DT, {}, case[2])
			b.step(DT, {}, case[2])
			t.check(a.result.is_empty(), "prelude leaves the battle running: %s" % case[0])
		_op(a, case[1])
		b.step(DT, {})
		t.check(_snapshot(a) == _snapshot(b), "invalid op skipped: %s" % case[0])
	var a = NavalSimulation.new()
	var b = NavalSimulation.new()
	a.reset("duel_sloop", "sloop")
	b.reset("duel_sloop", "sloop")
	_op(a, {"op": "add_captain", "ship_id": 100, "vessel_id": "sloop"})
	b.step(DT, {})
	t.check(_snapshot(a) == _snapshot(b), "offline ops ignored")
	return true


func _test_linger_neutral_and_sunk(t) -> bool:
	# a and b run in lockstep; b is the twin for "an invalid abandon changes nothing".
	var a = _fixture(100)
	var b = _fixture(100)
	for sim in [a, b]:
		sim.ships[100]["position"] = Vector2(1500, 1000)
		sim.ships[100]["heading"] = 0.0
		sim.ships[100]["reefed"] = false
	var weapons: Dictionary = a.ships[100]["weapons"].duplicate(true)
	var all_commands := {100: {"turn": 1.0, "toggle_sails": true, "fire_port": true, "fire_starboard": true,
		"cycle_port": true, "cycle_starboard": true}}
	var lingering_events := 0
	var acted := false
	for i in 121:
		for sim in [a, b]:
			sim.step(DT, all_commands, [{"op": "linger", "ship_id": 100}] if i == 0 else [])
		lingering_events += a.events.filter(func(e): return e == {"type": "ship_lingering", "ship_id": 100}).size()
		acted = acted or a.events.any(func(e): return e["type"] in ["shot", "fire_rejected"] and e.get("ship_id") == 100)
	var ship: Dictionary = a.ships[100]
	t.check(lingering_events == 1, "linger: exactly one ship_lingering event")
	t.check(ship["heading"] == 0.0 and ship["reefed"] == false and ship["weapons"] == weapons,
		"linger: heading, reef and ammo/loads unchanged by commands")
	t.check(not acted, "linger: no shot or fire_rejected for the lingering ship")
	t.check(ship["position"].x > 1500.0 and ship["active"] and ship["lingering"], "linger: keeps sailing, active, lingering")
	t.check(ship["linger_ticks"] == 121, "linger: op step is tick 1 (got %d)" % ship["linger_ticks"])
	for sim in [a, b]:
		_lethal(sim, 2, 100)
		sim.step(DT, {})
	t.check(a.events.any(func(e): return e["type"] == "hit" and e["victim_id"] == 100), "lingering ship can be hit")
	t.check(a.events.any(func(e): return e["type"] == "ship_defeated" and e["ship_id"] == 100), "lingering ship defeated")
	t.check(a.outcomes.get(100) == {"outcome": "sunk", "elapsed": a.elapsed}, "sunk lingering ship: outcome sunk at post-step elapsed")
	t.check(a.ships[100]["lingering"] == false, "defeat clears lingering")
	var sunk: Dictionary = a.outcomes[100].duplicate()
	var abandoned := false
	for i in 1800:
		for sim in [a, b]:
			sim.step(DT, {})
		abandoned = abandoned or a.events.any(func(e): return e["type"] == "ship_abandoned")
	t.check(a.ships.has(100) and not a.ships[100]["active"] and a.outcomes[100] == sunk and not abandoned,
		"sunk lingering ship stays an inactive wreck, still sunk, never abandoned")
	t.check(a.result.is_empty(), "captain 101 keeps the battle running")
	_op(a, {"op": "abandon", "ship_id": 100})  # deliberate ERROR: defeated ship
	b.step(DT, {})
	t.check(_snapshot(a) == _snapshot(b), "abandon of a defeated ship is rejected and changes nothing")
	return true


func _test_linger_expiry(t) -> bool:
	var sim = _fixture()
	_op(sim, {"op": "linger", "ship_id": 100})
	_steps(sim, 1798)
	t.check(sim.ships.has(100) and sim.ships[100]["linger_ticks"] == 1799, "linger: present after 1799 ticks")
	sim.step(DT, {})
	t.check(not sim.ships.has(100), "linger: removed on tick 1800")
	t.check(sim.outcomes.get(100) == {"outcome": "abandoned", "elapsed": sim.elapsed}, "linger expiry: outcome abandoned at post-step elapsed")
	t.check(_has_event(sim, {"type": "ship_abandoned", "ship_id": 100}), "linger expiry: ship_abandoned event")
	t.check(sim.result.is_empty(), "linger expiry: captain 101 keeps the battle running")
	t.check(NavalSimulation.linger_ticks_required(DT) == 1800, "linger_ticks_required(1/60) == 1800")
	return true


func _test_reclaim(t) -> bool:
	var sim = _fixture()
	_op(sim, {"op": "linger", "ship_id": 100})
	_steps(sim, 598)
	var heading: float = sim.ships[100]["heading"]
	_op(sim, {"op": "reclaim", "ship_id": 100}, {100: {"turn": 1.0}})  # step 600
	t.check(sim.events == [{"type": "ship_reclaimed", "ship_id": 100}], "reclaim: ship_reclaimed event")
	t.check(sim.ships[100]["lingering"] == false and sim.ships[100]["linger_ticks"] == 0, "reclaim: linger keys reset")
	t.check(sim.ships[100]["heading"] != heading, "reclaim: commands act in the reclaim step")
	_op(sim, {"op": "linger", "ship_id": 100})
	_steps(sim, 1798)
	t.check(sim.ships.has(100) and sim.ships[100]["linger_ticks"] == 1799, "re-linger: a fresh grace, present after 1799 ticks")
	sim.step(DT, {})
	t.check(not sim.ships.has(100) and sim.outcomes.get(100, {}).get("outcome") == "abandoned", "re-linger: gone on tick 1800")
	return true


func _test_linger_no_escape(t) -> bool:
	var sim = _fixture()
	sim.ships[100]["position"] = Vector2(400, 400)
	_op(sim, {"op": "linger", "ship_id": 100})
	sim.ships[100]["escape_armed"] = true  # after the op (which resets it): unguarded, it would escape at step 480
	var escaped := false
	for i in 600:
		sim.step(DT, {})
		escaped = escaped or sim.events.any(func(e): return e["type"] == "ship_escaped")
	var ship: Dictionary = sim.ships.get(100, {})
	t.check(not ship.is_empty(), "lingering ship far from every AI is still present")
	t.check(ship.get("escape_armed") == false and ship.get("escape_clear_ticks") == 0, "lingering ship: escape keys reset")
	t.check(not escaped and not sim.outcomes.has(100), "lingering ship never escapes")
	return true


func _test_abandon(t) -> bool:
	var sim = _fixture()
	var shot_id: int = sim.next_projectile_id
	sim.projectiles.append({"id": shot_id, "owner_id": 100, "ammo": "round",
		"position": sim.ships[2]["position"] - Vector2(100, 0), "direction": Vector2.RIGHT,
		"remaining_range": 900.0, "owner_cleared": true})
	sim.next_projectile_id += 1
	_op(sim, {"op": "abandon", "ship_id": 100})
	t.check(not sim.ships.has(100), "abandon: ship erased")
	t.check(sim.outcomes.get(100) == {"outcome": "abandoned", "elapsed": sim.elapsed}, "abandon: outcome abandoned at post-step elapsed")
	t.check(_has_event(sim, {"type": "ship_abandoned", "ship_id": 100}), "abandon: ship_abandoned event")
	t.check(sim.result.is_empty(), "abandon: captain 101 keeps the battle running")
	var hit := false
	for i in 30:
		sim.step(DT, {})
		hit = hit or sim.events.any(func(e): return e["type"] == "hit" and e["projectile_id"] == shot_id and e["victim_id"] == 2)
	t.check(hit, "an abandoned ship's in-flight shot still hits AI 2")
	return true


func _test_captain_escape(t) -> bool:
	var sim = _fixture()
	sim.ships[100]["position"] = Vector2(400, 400)
	sim.ships[100]["escape_armed"] = true
	_steps(sim, 479)
	t.check(sim.ships.has(100) and sim.ships[100]["escape_clear_ticks"] == 479, "captain escape: 479 clear ticks")
	sim.step(DT, {})
	t.check(not sim.ships.has(100), "captain escape: erased on tick 480")
	t.check(sim.outcomes.get(100) == {"outcome": "escaped", "elapsed": sim.elapsed}, "captain escape: outcome escaped at post-step elapsed")
	t.check(_has_event(sim, {"type": "ship_escaped", "ship_id": 100}), "captain escape: ship_escaped event")
	var other: Dictionary = sim.ships.get(101, {})
	t.check(other.get("escape_armed") == true and other.get("escape_clear_ticks") == 0, "captain 101 present, armed, no progress")
	t.check(sim.result.is_empty(), "captain escape does not end the battle")
	t.check(sim.escape_armed == false and sim.escape_clear_ticks == 0, "battle mode leaves the top-level escape fields alone")
	return true


func _ids(defeated: Array) -> Array:
	return defeated.map(func(d): return d["ship_id"])


func _test_battle_results(t) -> bool:
	# victory: a lingering captain counts as active
	var sim = _fixture()
	_sink(sim, 3)
	_sink(sim, 4)
	_op(sim, {"op": "linger", "ship_id": 100})
	_lethal(sim, 101, 2)
	sim.step(DT, {})
	var result: Dictionary = sim.result
	t.check(result.get("outcome") == "victory" and result.get("elapsed") == sim.elapsed, "victory with a lingering captain")
	for id in [100, 101]:
		t.check(sim.outcomes.get(id) == {"outcome": "victory", "elapsed": result.get("elapsed")}, "victory: captain %d outcome" % id)
	t.check(result.get("outcomes") == sim.outcomes, "victory: result carries the outcomes")
	t.check(_ids(result.get("defeated", [])) == [2, 3, 4], "victory: defeated ids [2, 3, 4]")
	# freeze: ops and commands are silently ignored once the result is set
	var before := _snapshot(sim)
	sim.step(DT, {101: {"turn": 1.0}}, [{"op": "add_captain", "ship_id": 150, "vessel_id": "sloop"}, {"op": "abandon", "ship_id": 101}])
	before["events"] = []
	t.check(_snapshot(sim) == before, "result freezes the battle: ops and commands ignored, events cleared")
	# draw: both sides' last ships go down in the same step
	sim = _battle("brig_squadron", [[100, "brig"]])
	_becalm(sim)
	_sink(sim, 3)
	_sink(sim, 4)
	_lethal(sim, 2, 100)
	_lethal(sim, 100, 2)
	sim.step(DT, {})
	t.check(sim.result.get("outcome") == "draw", "draw: no active ship on either side")
	t.check(sim.outcomes.get(100) == {"outcome": "sunk", "elapsed": sim.elapsed}, "draw: captain 100 sunk")
	# lost: the only captain sinks, or is abandoned
	sim = _battle("brig_squadron", [[100, "brig"]])
	_becalm(sim)
	_lethal(sim, 2, 100)
	sim.step(DT, {})
	t.check(sim.result.get("outcome") == "lost" and sim.outcomes.get(100, {}).get("outcome") == "sunk", "lost: only captain sunk")
	sim = _battle("brig_squadron", [[100, "brig"]])
	_op(sim, {"op": "abandon", "ship_id": 100})
	t.check(sim.result.get("outcome") == "lost" and sim.result.get("elapsed") == sim.elapsed, "lost: only captain abandoned, same step")
	t.check(sim.result.get("outcomes") == {100: {"outcome": "abandoned", "elapsed": sim.elapsed}}, "lost: result outcomes")
	# never joined: no result without a captain
	sim = NavalSimulation.new()
	sim.reset_battle("frigate_escort")
	_steps(sim, 600)
	t.check(sim.result == {} and sim.outcomes == {}, "never joined: no result, no outcomes")
	return true


func _test_offline_escape_mirror(t) -> bool:
	var sim = NavalSimulation.new()
	sim.reset("duel_sloop", "sloop")
	sim.ships[2]["position"] = sim.ships[1]["position"] + Vector2(800, 0)
	sim._update_escape(DT)
	t.check(sim.escape_armed and sim.ships[1]["escape_armed"] and sim.ships[1]["escape_clear_ticks"] == 0, "offline mirror: armed")
	sim.ships[2]["position"] = sim.ships[1]["position"] + Vector2(1500, 0)
	for i in 3:
		sim._update_escape(DT)
		t.check(sim.ships[1]["escape_armed"] == sim.escape_armed and sim.ships[1]["escape_clear_ticks"] == sim.escape_clear_ticks
			and sim.escape_clear_ticks == i + 1, "offline mirror: %d clear ticks" % (i + 1))
	t.check(sim.ships[2]["escape_armed"] == false and sim.ships[2]["escape_clear_ticks"] == 0, "offline: AI escape keys never change")
	return true


const MEMBERSHIP_EVENTS := ["captain_joined", "ship_lingering", "ship_reclaimed", "ship_abandoned"]
## Determinism tape: tick -> ops applied at the start of that tick's step.
const TAPE := {
	0: [{"op": "add_captain", "ship_id": 100, "vessel_id": "brig"}],
	120: [{"op": "add_captain", "ship_id": 101, "vessel_id": "sloop"}],
	600: [{"op": "linger", "ship_id": 100}],
	1200: [{"op": "reclaim", "ship_id": 100}, {"op": "abandon", "ship_id": 101}],
	1800: [{"op": "add_captain", "ship_id": 102, "vessel_id": "frigate"}],
}


## Fixed captain pattern keyed on tick and id: a hard turn for the first 240 ticks after
## `join`, then a slow weave; staggered broadsides, a short reef every 600 ticks and an
## occasional ammo cycle.
func _tape_command(tick: int, id: int, join: int) -> Dictionary:
	var age := tick - join
	var command := {"turn": 1.0 if age < 240 else (0.4 if (age / 180) % 2 == 0 else -0.4)}
	if age % 90 == id % 90:
		command["fire_port"] = true
	if age % 90 == (id + 45) % 90:
		command["fire_starboard"] = true
	if age % 600 in [300, 360]:
		command["toggle_sails"] = true
	if age % 700 == 350:
		command["cycle_port"] = true
	return command


## One tape run: checkpoints every 60th tick plus the [tick, event] membership log.
func _tape_run() -> Dictionary:
	var sim = NavalSimulation.new()
	var ai = AIController.new()
	sim.reset_battle("brig_squadron")
	var joins := {100: 0, 101: 120, 102: 1800}
	var checkpoints := []
	var membership := []
	var shots := 0
	for tick in 3600:
		var commands: Dictionary = ai.commands_for_tick(sim.ai_observation(), DT)
		for id in joins:
			if sim.ships.has(id) and tick >= joins[id]:
				commands[id] = _tape_command(tick, id, joins[id])
		sim.step(DT, commands, TAPE.get(tick, []))
		for e in sim.events:
			if e["type"] in MEMBERSHIP_EVENTS:
				membership.append([tick, e["type"], e["ship_id"]])
			shots += 1 if e["type"] == "shot" else 0
		if tick % 60 == 0:
			checkpoints.append(var_to_str([tick, sim.ships, sim.projectiles, sim.events, sim.elapsed, sim.result, sim.outcomes]))
	return {"checkpoints": checkpoints, "membership": membership, "shots": shots}


## Two identical tape runs (fresh sim and AI each) must match at every checkpoint, and every
## op must have run: its membership event appears at its tick, in tape order.
func _test_determinism(t) -> bool:
	var a := _tape_run()
	var b := _tape_run()
	t.check(a["checkpoints"].size() == 60, "tape: 60 checkpoints")
	t.check(a["checkpoints"] == b["checkpoints"], "tape: identical checkpoints across runs")
	t.check(a["membership"] == b["membership"], "tape: identical membership logs across runs")
	var want := [[0, "captain_joined", 100], [120, "captain_joined", 101], [600, "ship_lingering", 100],
		[1200, "ship_reclaimed", 100], [1200, "ship_abandoned", 101], [1800, "captain_joined", 102]]
	t.check(a["membership"] == want, "tape: every op ran, membership events in tape order (got %s)" % [a["membership"]])
	t.check(a["shots"] > 0, "tape: shots fired")
	return true


## Per group preset: captains join at ticks 0, 300 and 900, hold course and fire both broadsides
## every 180 ticks while the AI commands the fleet, until a result or 36000 ticks.
func _test_group_presets_to_result(t) -> bool:
	const VALID := ["sunk", "disabled", "escaped", "abandoned", "victory"]
	for preset_id in GROUP_PRESETS:
		var sim = NavalSimulation.new()
		var ai = AIController.new()
		sim.reset_battle(preset_id)
		var joins := {0: [100, "brig"], 300: [101, "sloop"], 900: [102, "frigate"]}
		var end_tick := -1  # the 0-based tick whose step set the result
		for tick in 36000:
			var commands: Dictionary = ai.commands_for_tick(sim.ai_observation(), DT)
			if tick % 180 == 0:
				for id in [100, 101, 102]:
					if sim.ships.has(id):
						commands[id] = {"fire_port": true, "fire_starboard": true}
			var ops := []
			if joins.has(tick):
				ops.append({"op": "add_captain", "ship_id": joins[tick][0], "vessel_id": joins[tick][1]})
			sim.step(DT, commands, ops)
			if not sim.result.is_empty():
				end_tick = tick
				break
		var result: Dictionary = sim.result
		var outcome = result.get("outcome")
		print("%s: %s at tick %d" % [preset_id, outcome, end_tick])
		t.check(outcome in ["victory", "draw", "lost"], "%s: battle reached a result (got %s)" % [preset_id, outcome])
		var outcomes: Dictionary = result.get("outcomes", {})
		var ids := outcomes.keys()
		ids.sort()
		t.check(ids == [100, 101, 102], "%s: outcomes for captains 100, 101, 102 (got %s)" % [preset_id, ids])
		var any_victory := false
		for id in ids:
			var o = outcomes[id]
			t.check(o is Dictionary and o.size() == 2 and o.get("outcome") in VALID and o.get("elapsed") is float
				and o["elapsed"] <= result["elapsed"], "%s: captain %d outcome valid (got %s)" % [preset_id, id, o])
			any_victory = any_victory or (o is Dictionary and o.get("outcome") == "victory")
		t.check(any_victory == (outcome == "victory"), "%s: some captain has victory iff the battle is a victory" % preset_id)
		t.check(outcomes == sim.outcomes, "%s: result outcomes match sim.outcomes" % preset_id)
	return true
