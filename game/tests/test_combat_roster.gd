extends RefCounted
## Plan 05 task 5: roster-wide simulation and controller lifecycle checks.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const AIController := preload("res://sim/ai_controller.gd")
const DT := 1.0 / 60.0
const PRESETS := ["duel_sloop", "duel_brig", "duel_frigate", "two_sloops"]
const VESSELS := ["sloop", "brig", "frigate"]

var main


func run(t) -> bool:
	main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	var pairs := {}
	for preset_id in PRESETS:
		for vessel_id in VESSELS:
			var label := "%s/%s" % [preset_id, vessel_id]
			pairs[label] = true
			_test_pair(t, preset_id, vessel_id)
	t.check(pairs.size() == 12, "12 unique combat roster pairs")
	_test_alternation(t)
	_test_pause(t)
	main.free()
	return true


func _snapshot(sim) -> Dictionary:
	var ordered := []
	var ids: Array = sim.ships.keys()
	ids.sort()
	for id in ids:
		ordered.append(sim.ships[id].duplicate(true))
	return {"preset_id": sim.preset_id, "selected_vessel_id": sim.selected_vessel_id,
		"wind_heading": sim.wind_heading, "ships": ordered,
		"projectiles": sim.projectiles.duplicate(true), "next_projectile_id": sim.next_projectile_id,
		"events": sim.events.duplicate(true), "elapsed": sim.elapsed,
		"result": sim.result.duplicate(true), "escape_armed": sim.escape_armed,
		"escape_clear_ticks": sim.escape_clear_ticks}


func _fresh(preset_id: String, vessel_id: String):
	var sim = NavalSimulation.new()
	sim.reset(preset_id, vessel_id)
	return sim


func _valid(sim) -> bool:
	if not is_finite(sim.elapsed) or sim.elapsed < 0.0 or sim.escape_clear_ticks < 0:
		return false
	for id in sim.ships:
		var ship: Dictionary = sim.ships[id]
		var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
		var pos: Vector2 = ship["position"]
		var bounds := Definitions.safe_bounds(vessel["radius"])
		if not is_finite(pos.x) or not is_finite(pos.y) or not is_finite(ship["heading"]) \
			or not is_finite(ship["speed"]) or ship["speed"] < 0.0 \
			or ship["speed"] > vessel["full_speed"] or (not ship["active"] and ship["speed"] != 0.0) \
			or (ship["active"] and not ship["defeat_reasons"].is_empty()):
			return false
		if ship["active"] and not bounds.has_point(pos):
			return false
		for track in ["hull", "sails", "crew"]:
			if not is_finite(ship[track]) or ship[track] < 0.0 or ship[track] > vessel[track]:
				return false
		for side in Definitions.SIDES:
			var weapon: Dictionary = ship["weapons"][side]
			if not Definitions.AMMO.has(weapon["ammo"]) or weapon["loads"].size() != vessel["guns_per_side"]:
				return false
			for load in weapon["loads"]:
				if not is_finite(load) or load < 0.0 or load > 1.0:
					return false
	for shot in sim.projectiles:
		if not is_finite(shot["position"].x) or not is_finite(shot["position"].y) \
			or not is_finite(shot["direction"].x) or not is_finite(shot["direction"].y) \
			or not is_finite(shot["remaining_range"]) or shot["remaining_range"] <= 0.0 \
			or shot["remaining_range"] > Definitions.AMMO[shot["ammo"]]["range"]:
			return false
	var active_enemy := false
	for id in sim.ships:
		if id != 1 and sim.ships[id]["active"]:
			active_enemy = true
	var outcome: String = sim.result.get("outcome", "")
	if outcome != "":
		var defeated := []
		var ids: Array = sim.ships.keys()
		ids.sort()
		for id in ids:
			if not sim.ships[id]["active"]:
				defeated.append(id)
		if sim.result.get("elapsed") != sim.elapsed \
			or sim.result.get("defeated", []).map(func(d): return d["ship_id"]) != defeated:
			return false
	return (outcome == "" and sim.ships[1]["active"] and active_enemy) \
		or (outcome == "victory" and sim.ships[1]["active"] and not active_enemy) \
		or (outcome == "defeat" and not sim.ships[1]["active"] and active_enemy) \
		or (outcome == "draw" and not sim.ships[1]["active"] and not active_enemy) \
		or (outcome == "escaped" and sim.ships[1]["active"] and active_enemy)


## A test-only shot starts inside its victim; the ordinary projectile pass supplies damage.
func _hit(sim, victim_id: int, ammo: String) -> void:
	var owner := 2 if victim_id == 1 else 1
	sim.projectiles.append({"id": sim.next_projectile_id, "owner_id": owner, "ammo": ammo,
		"position": sim.ships[victim_id]["position"] - Vector2(0, 5),
		"direction": Vector2.DOWN, "remaining_range": Definitions.AMMO[ammo]["range"],
		"owner_cleared": true})
	sim.next_projectile_id += 1


func _defeat(sim, victim_id: int, tracks: Array) -> void:
	for track in tracks:
		var ammo := "round" if track == "hull" else "chain" if track == "sails" else "grape"
		sim.ships[victim_id][track] = Definitions.AMMO[ammo]["damage"]
		_hit(sim, victim_id, ammo)


func _test_pair(t, preset_id: String, vessel_id: String) -> void:
	var label := "%s/%s" % [preset_id, vessel_id]
	var sim = _fresh(preset_id, vessel_id)
	var preset: Dictionary = Definitions.PRESETS[preset_id]
	var ids: Array = sim.ships.keys()
	ids.sort()
	var spawn_ok: bool = ids.size() == preset["opposition"].size() + 1 and ids[0] == 1 \
		and sim.ships[1]["vessel_id"] == vessel_id and sim.ships[1]["team"] == 0 \
		and sim.ships[1]["position"] == preset["player_position"] \
		and sim.ships[1]["heading"] == preset["player_heading"] \
		and sim.wind_heading == preset["wind_heading"] \
		and sim.elapsed == 0.0 and sim.projectiles.is_empty() and sim.events.is_empty() \
		and sim.result.is_empty() and sim.next_projectile_id == 1 \
		and not sim.escape_armed and sim.escape_clear_ticks == 0
	for entry in preset["opposition"]:
		var enemy: Dictionary = sim.ships[entry["id"]]
		spawn_ok = spawn_ok and enemy["team"] == 1 and enemy["role"] == "ship" \
			and enemy["vessel_id"] == entry["vessel_id"] and enemy["position"] == entry["position"] \
			and enemy["heading"] == entry["heading"]
	for id in ids:
		var ship: Dictionary = sim.ships[id]
		var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
		spawn_ok = spawn_ok and ship["active"] and not ship["reefed"] \
			and ship["defeat_reasons"].is_empty() and ship["speed"] == 0.0
		for track in ["hull", "sails", "crew"]:
			spawn_ok = spawn_ok and ship[track] == vessel[track]
		for side in Definitions.SIDES:
			spawn_ok = spawn_ok and ship["weapons"][side]["ammo"] == "round" \
				and ship["weapons"][side]["loads"].size() == vessel["guns_per_side"] \
				and ship["weapons"][side]["loads"].all(func(load): return load == 1.0)
	t.check(spawn_ok, "%s: full spawn, counts and resources" % label)
	var ai = AIController.new()
	var valid := _valid(sim)
	var ticks := 0
	for tick in 600:
		var commands: Dictionary = ai.commands_for_tick(sim.ai_observation(), DT)
		commands[1] = {}
		sim.step(DT, commands)
		ticks += 1
		valid = valid and _valid(sim)
		if not sim.result.is_empty():
			break
	t.check(valid and ticks > 0 and ticks <= 600 and sim.elapsed > 0.0,
		"%s: %d production AI ticks finite/bounded/clamped with coherent result" % [label, ticks])
	for tracks in [["hull"], ["sails"], ["crew"], ["sails", "crew"]]:
		var fixture = _fresh(preset_id, vessel_id)
		for id in fixture.ships:
			if id != 1:
				_defeat(fixture, id, tracks)
		fixture.step(DT, {})
		var reason := "sunk" if tracks[0] == "hull" else "disabled"
		t.check(fixture.result.get("outcome") == "victory" and _valid(fixture) \
			and fixture.result["defeated"].size() == ids.size() - 1 \
			and fixture.result["defeated"].all(func(d): return d["reason"] == reason \
				and d["disabled_by"] == ([] if reason == "sunk" else tracks)),
			"%s: outcome plumbing victory by %s" % [label, "+".join(tracks)])
		_test_replay(t, fixture, preset_id, vessel_id, "%s/%s" % [label, "+".join(tracks)])
	var lost = _fresh(preset_id, vessel_id)
	_defeat(lost, 1, ["hull"])
	lost.step(DT, {})
	t.check(lost.result.get("outcome") == "defeat" and _valid(lost),
		"%s: outcome plumbing player defeat" % label)
	_test_replay(t, lost, preset_id, vessel_id, label + "/defeat")
	var draw = _fresh(preset_id, vessel_id)
	for id in draw.ships:
		_defeat(draw, id, ["hull"])
	draw.step(DT, {})
	t.check(draw.result.get("outcome") == "draw" and _valid(draw) \
		and draw.result["defeated"].map(func(d): return d["ship_id"]) == ids,
		"%s: outcome plumbing simultaneous final draw" % label)
	_test_replay(t, draw, preset_id, vessel_id, label + "/draw")
	if ids.size() == 3:
		var continuing = _fresh(preset_id, vessel_id)
		_defeat(continuing, 2, ["sails", "crew"])
		continuing.step(DT, {})
		t.check(continuing.result.is_empty() and continuing.ships[3]["active"] \
			and continuing.ships[2]["defeat_reasons"] == ["sails", "crew"],
			"%s: outcome plumbing first enemy disabled, encounter continues" % label)
		var survivor_before: Vector2 = continuing.ships[3]["position"]
		var follow: Dictionary = AIController.new().commands_for_tick(continuing.ai_observation(), DT)
		continuing.step(DT, follow)
		t.check(follow.keys() == [3] and continuing.ships[3]["position"] != survivor_before \
			and continuing.result.is_empty(), "%s: surviving enemy still acts" % label)
		_defeat(continuing, 1, ["hull"])
		_defeat(continuing, 3, ["hull"])
		continuing.step(DT, {})
		t.check(continuing.result.get("outcome") == "draw" and _valid(continuing),
			"%s: outcome plumbing final mutual defeat after earlier loss" % label)
		_test_replay(t, continuing, preset_id, vessel_id, label + "/final draw")
		var partial = _fresh(preset_id, vessel_id)
		_defeat(partial, 2, ["hull"])
		partial.step(DT, {})
		_defeat(partial, 1, ["hull"])
		partial.step(DT, {})
		t.check(partial.result.get("outcome") == "defeat" and _valid(partial) \
			and partial.result["defeated"].map(func(d): return d["ship_id"]) == [1, 2],
			"%s: outcome plumbing player/first enemy down, survivor wins" % label)
		_test_replay(t, partial, preset_id, vessel_id, label + "/partial defeat")


func _test_replay(t, sim, preset_id: String, vessel_id: String, label: String) -> void:
	var fresh = _fresh(preset_id, vessel_id)
	main.start_encounter(preset_id, vessel_id)
	main.sim = sim
	main.ai.commands_for_tick(sim.ai_observation(), DT)
	sim.ships[1]["weapons"]["port"]["ammo"] = "chain"
	sim.ships[1]["weapons"]["port"]["loads"][0] = 0.5
	sim.escape_armed = true
	sim.escape_clear_ticks = 23
	_hit(sim, 1, "round")
	var dirty: bool = _snapshot(sim) != _snapshot(fresh) and not sim.result.is_empty() \
		and not sim.projectiles.is_empty() and main.ai._clock > 0.0
	main._enter_mode("result")
	main._edges["fire_starboard"] = true
	main._toggle_queued = true
	main._held["turn_left"] = true
	main._reset_queued = true
	main.restart_practice()
	t.check(dirty and main.mode == "sailing" and _snapshot(main.sim) == _snapshot(fresh),
		"%s: result replay restores full canonical state incl weapons/projectiles/escape" % label)
	t.check(main.ai._memory.is_empty() and main.ai._clock == 0.0 and main._edges.is_empty() \
		and main._held.is_empty() and not main._toggle_queued and not main._reset_queued,
		"%s: result replay clears AI memory and controller edges" % label)
	t.check(main.ai.commands_for_tick(main.sim.ai_observation(), DT) \
		== AIController.new().commands_for_tick(fresh.ai_observation(), DT),
		"%s: replay first AI commands equal fresh" % label)


func _test_alternation(t) -> void:
	var clean := true
	for i in 10:
		for preset_id in ["duel_sloop", "two_sloops", "duel_brig"]:
			main.start_encounter(preset_id, VESSELS[i % VESSELS.size()])
			clean = clean and _snapshot(main.sim) == _snapshot(_fresh(preset_id, VESSELS[i % VESSELS.size()])) \
				and main.ai._memory.is_empty() and main.ai._clock == 0.0 \
				and main._edges.is_empty() and not main._toggle_queued
			main.advance_tick()
			clean = clean and main.ai._memory.size() == (2 if preset_id == "two_sloops" else 1) \
				and main.ai._memory.has(3) == (preset_id == "two_sloops")
	t.check(clean, "10 duel/two-sloops/duel cycles reset ID3, weapons, AI and command edges")


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _test_pause(t) -> void:
	var main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	main.start_encounter("two_sloops", "brig")
	main.advance_tick()  # both enemy memories have one real tick
	main.sim.projectiles.append({"id": main.sim.next_projectile_id, "owner_id": 1, "ammo": "round",
		"position": Vector2(2000, 2000), "direction": Vector2.LEFT,
		"remaining_range": 900.0, "owner_cleared": true})
	main.sim.next_projectile_id += 1
	main.get_viewport().push_input(_key(KEY_E))
	main.get_viewport().push_input(_key(KEY_C))
	main.get_viewport().push_input(_key(KEY_W))
	main.set_paused(true)
	var paused := _snapshot(main.sim)
	var memory: Dictionary = main.ai._memory.duplicate(true)
	var clock: float = main.ai._clock
	for i in 120:
		main.advance_tick()
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.check(main.mode == "paused" and _snapshot(main.sim) == paused \
		and main.ai._memory == memory and main.ai._clock == clock,
		"two opponents and projectile: 120 paused ticks and focus return preserve sim/AI")
	main.set_paused(false)
	main.advance_tick()
	var player: Dictionary = main.sim.ships[1]
	t.check(main.mode == "sailing" and main.sim.elapsed == paused["elapsed"] + DT \
		and main.ai._clock == clock + DT and main.ai._memory.has(2) and main.ai._memory.has(3) \
		and main.sim.ships[2]["position"] != paused["ships"][1]["position"] \
		and main.sim.ships[3]["position"] != paused["ships"][2]["position"] \
		and not player["reefed"] and player["weapons"]["starboard"]["ammo"] == "round" \
		and player["weapons"]["starboard"]["loads"].all(func(load): return load == 1.0) \
		and main.sim.next_projectile_id == paused["next_projectile_id"],
		"explicit resume discards edges and advances both enemies exactly one step")
	main.free()
