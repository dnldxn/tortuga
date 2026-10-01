extends RefCounted
## Plan 05 tasks 1-3: two ordinary opposition ships, shared combat and command-only AI.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const AIController := preload("res://sim/ai_controller.gd")
const DT := 1.0 / 60.0


func run(t) -> bool:
	_test_reset(t)
	_test_sloop_fairness(t)
	_test_ai_commands_and_isolation(t)
	_test_ally_avoidance(t)
	_test_traffic_runs(t)
	_test_traffic_deadlines(t)
	_test_fire_lanes(t)
	_test_assisted_targets(t)
	_test_friendly_hits(t)
	_test_swept_collisions(t)
	_test_outcomes(t)
	_test_simultaneous_fire(t)
	_test_defeated_exclusion(t)
	return true


func _test_reset(t) -> void:
	t.check(Definitions.PRESETS.has("two_sloops"), "two_sloops preset registered")
	if not Definitions.PRESETS.has("two_sloops"):
		return
	for vessel_id in ["sloop", "brig", "frigate"]:
		var sim = NavalSimulation.new()
		sim.reset("two_sloops", vessel_id)
		var label := "two_sloops/%s" % vessel_id
		t.check(sim.ships.keys() == [1, 2, 3], "%s: exactly IDs 1/2/3" % label)
		t.check(sim.preset_id == "two_sloops" and sim.selected_vessel_id == vessel_id
			and sim.wind_heading == 0.0 and sim.elapsed == 0.0, "%s: reset metadata" % label)
		t.check(sim.projectiles.is_empty() and sim.events.is_empty() and sim.result.is_empty()
			and sim.next_projectile_id == 1, "%s: fresh combat state" % label)
		for id in [1, 2, 3]:
			var ship: Dictionary = sim.ships[id]
			var expected_vessel: String = vessel_id if id == 1 else "sloop"
			var vessel: Dictionary = Definitions.VESSELS[expected_vessel]
			var position := Vector2(2400, 2100) if id == 1 else Vector2(3400, 1700 if id == 2 else 2500)
			t.check(ship["team"] == (0 if id == 1 else 1) and ship["role"] == "ship"
				and ship["vessel_id"] == expected_vessel and ship["position"] == position
				and ship["heading"] == (0.0 if id == 1 else PI), "%s: ship %d spawn" % [label, id])
			t.check(ship["active"] and ship["defeat_reasons"].is_empty() and not ship["reefed"]
				and ship["speed"] == 0.0 and [ship["hull"], ship["sails"], ship["crew"]]
				== [vessel["hull"], vessel["sails"], vessel["crew"]], "%s: ship %d full tracks/sails" % [label, id])
			for side in Definitions.SIDES:
				t.check(ship["weapons"][side]["ammo"] == "round"
					and ship["weapons"][side]["loads"].size() == vessel["guns_per_side"]
					and ship["weapons"][side]["loads"].all(func(load): return load == 1.0),
					"%s: ship %d %s loaded" % [label, id, side])
			t.check(Definitions.safe_bounds(vessel["radius"]).has_point(ship["position"]),
				"%s: ship %d inside bounds" % [label, id])
		for a in [1, 2, 3]:
			for b in range(a + 1, 4):
				t.check(sim.ships[a]["position"].distance_to(sim.ships[b]["position"]) >
					Definitions.VESSELS[sim.ships[a]["vessel_id"]]["radius"] +
					Definitions.VESSELS[sim.ships[b]["vessel_id"]]["radius"],
					"%s: ships %d/%d do not overlap" % [label, a, b])


func _test_sloop_fairness(t) -> void:
	var vessel: Dictionary = Definitions.VESSELS["sloop"]
	t.check(vessel["full_speed"] == 129.6 and vessel["turn_rate"] == 1.2
		and [vessel["hull"], vessel["sails"], vessel["crew"]] == [100.0, 70.0, 60.0]
		and [vessel["guns_per_side"], vessel["base_reload"], vessel["radius"]] == [4, 7.0, 22.0],
		"sloops share existing 129.6 speed, turns, tracks, guns, reload and radius")
	var sim = NavalSimulation.new()
	sim.reset("two_sloops", "sloop")
	# Translated, identical orientations and tracks yield identical speed/turn/reload.
	for id in [1, 2, 3]:
		sim.ships[id]["heading"] = 0.0
		sim.ships[id]["crew"] = 30.0
		sim.ships[id]["sails"] = 40.0
		sim.ships[id]["weapons"]["port"]["loads"].fill(0.0)
	var starts := [sim.ships[1]["position"], sim.ships[2]["position"], sim.ships[3]["position"]]
	sim.step(DT, {1: {"turn": 0.5}, 2: {"turn": 0.5}, 3: {"turn": 0.5}})
	for id in [2, 3]:
		t.check(sim.ships[id]["speed"] == sim.ships[1]["speed"]
			and sim.ships[id]["heading"] == sim.ships[1]["heading"]
			and (sim.ships[id]["position"] - starts[id - 1]).distance_to(sim.ships[1]["position"] - starts[0]) < 0.001
			and sim.ships[id]["weapons"]["port"]["loads"] == sim.ships[1]["weapons"]["port"]["loads"],
			"enemy %d has identical movement/reload to player sloop" % id)
	# Damage follows ammo definitions regardless of team.
	for id in [1, 2, 3]:
		sim.ships[id]["position"] = Vector2(2000 + id * 500, 2100)
		_shot(sim, 2 if id == 1 else 1, "round", sim.ships[id]["position"] - Vector2(0, 10))
	sim.step(DT, {})
	t.check([sim.ships[1]["hull"], sim.ships[2]["hull"], sim.ships[3]["hull"]] == [92.0, 92.0, 92.0],
		"ordinary round damage is identical for all three sloops")


func _snapshot(sim) -> Dictionary:
	return {"ships": sim.ships.duplicate(true), "projectiles": sim.projectiles.duplicate(true),
		"events": sim.events.duplicate(true), "elapsed": sim.elapsed, "result": sim.result.duplicate(true),
		"next_projectile_id": sim.next_projectile_id}


func _reordered_observation(sim) -> Dictionary:
	var original: Dictionary = sim.ai_observation()["ships"]
	return {"ships": {3: original[3], 2: original[2], 1: original[1]}}


func _test_ai_commands_and_isolation(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("two_sloops", "brig")
	var before := _snapshot(sim)
	var observation := sim.ai_observation()
	observation["ships"][3]["position"] = Vector2.ZERO
	observation["ships"][2]["sides"]["port"]["ready"] = 0
	t.check(_snapshot(sim) == before, "two-opponent observation is deeply copied")
	var ai = AIController.new()
	var reversed = AIController.new()
	for tick in 120:
		var commands: Dictionary = ai.commands_for_tick(sim.ai_observation(), DT)
		var other: Dictionary = reversed.commands_for_tick(_reordered_observation(sim), DT)
		t.check(commands.keys() == [2, 3] and commands == other, "AI order-independent per-ID commands tick %d" % tick)
		for id in [2, 3]:
			t.check(commands[id].keys() == ["turn", "toggle_sails", "fire_port", "fire_starboard", "cycle_port", "cycle_starboard"]
				and is_finite(commands[id]["turn"]) and absf(commands[id]["turn"]) <= 1.0,
				"ship %d emits only ordinary finite commands" % id)
	t.check(_snapshot(sim) == before, "AI observation and commands never mutate live state")
	var isolated = AIController.new()
	var obs := sim.ai_observation()
	var active_before: Dictionary = isolated.commands_for_tick(obs, DT)
	t.check(active_before.keys() == [2, 3], "both active opponents command independently")
	obs["ships"][3]["active"] = false
	t.check(isolated.commands_for_tick(obs, DT).keys() == [2], "inactive ally excluded from AI commands")
	t.check(not isolated._memory.has(3), "inactive ally discards its per-ID memory")
	obs["ships"][3]["active"] = true
	var fresh = AIController.new()
	# ID 2 has a previous tick; ID 3 must start fresh when activated.
	var independent = isolated.commands_for_tick(obs, DT)
	t.check(independent[3] == fresh.commands_for_tick(obs, DT)[3], "enemy 3 memory independent of enemy 2")
	isolated.reset()
	t.check(isolated._memory.is_empty() and isolated._clock == 0.0, "AI reset removes all per-ID timers")
	t.check(isolated.commands_for_tick(obs, DT) == AIController.new().commands_for_tick(obs, DT),
		"AI reset reproduces fresh commands")


func _test_ally_avoidance(t) -> void:
	# Player is remote; only the slower ally can trigger or hold avoidance.
	var sim = NavalSimulation.new()
	sim.reset("two_sloops", "sloop")
	sim.ships[1]["position"] = Vector2(4800, 3500)
	sim.ships[2]["position"] = Vector2(3000, 2100)
	sim.ships[3]["position"] = Vector2(3080, 2100)
	for id in [2, 3]:
		sim.ships[id]["heading"] = 0.0
		sim.ships[id]["speed"] = 129.6 if id == 2 else 0.0
	var ai = AIController.new()
	var first: Dictionary = ai.commands_for_tick(sim.ai_observation(), DT)
	t.check(ai._memory[2].recovering and ai._memory[3].recovering
		and ai._memory[2].recovery_obstacle == 3 and ai._memory[3].recovery_obstacle == 2,
		"same-direction sloops 80 apart with closing speed treat ally as collision threat")
	t.check(not first[2]["fire_port"] and not first[3]["fire_starboard"], "recovery suppresses fire")
	var inactive = NavalSimulation.new()
	inactive.reset("two_sloops", "sloop")
	inactive.ships[1]["position"] = Vector2(4800, 3500)
	inactive.ships[2]["position"] = Vector2(3000, 2100)
	inactive.ships[2]["heading"] = 0.0
	inactive.ships[2]["speed"] = 129.6
	inactive.ships[3]["position"] = Vector2(3080, 2100)
	inactive.ships[3]["heading"] = 0.0
	inactive.ships[3]["speed"] = 0.0
	inactive.ships[3]["active"] = false
	var ignore = AIController.new()
	ignore.commands_for_tick(inactive.ai_observation(), DT)
	t.check(not ignore._memory[2].recovering, "inactive ally does not trigger recovery")
	# Once the minimum dwell elapses, a nearby ally must still prevent exit.
	for tick in 100:
		ai.commands_for_tick(sim.ai_observation(), DT)
	t.check(ai._memory[2].recovering, "nearby ally prevents recovery exit past minimum dwell")
	sim.ships[3]["position"] = Vector2(3400, 2100)
	sim.ships[3]["heading"] = 0.0
	ai.commands_for_tick(sim.ai_observation(), DT)
	t.check(not ai._memory[2].recovering, "recovery exits after all active obstacles are clear")
	# Insertion order cannot choose a different first danger when two ships threaten.
	sim.ships[3]["position"] = Vector2(3080, 2100)
	sim.ships[1]["position"] = Vector2(3070, 2100)
	var normal = AIController.new()
	var reverse = AIController.new()
	normal.commands_for_tick(sim.ai_observation(), DT)
	reverse.commands_for_tick(_reordered_observation(sim), DT)
	t.check(normal._memory[2].recovery_obstacle == 1 and reverse._memory[2].recovery_obstacle == 1,
		"first threat is lower ID regardless of observation insertion")


func _test_traffic_runs(t) -> void:
	var bounds := Definitions.safe_bounds(Definitions.VESSELS["sloop"]["radius"])
	var scenarios := [
		{"name": "same-direction", "a": Vector2(3000, 2100), "b": Vector2(3080, 2100), "heading_a": 0.0, "heading_b": 0.0},
		{"name": "overlap", "a": Vector2(3000, 2100), "b": Vector2(3000, 2100), "heading_a": 0.0, "heading_b": 0.0},
		{"name": "upwind", "a": Vector2(3000, 2100), "b": Vector2(3080, 2100), "heading_a": PI, "heading_b": PI},
		{"name": "converging", "a": Vector2(2950, 2100), "b": Vector2(3050, 2100), "heading_a": 0.0, "heading_b": PI},
		{"name": "west", "a": Vector2(bounds.position.x + 5, 2100), "b": Vector2(bounds.position.x + 85, 2100), "heading_a": PI, "heading_b": PI},
		{"name": "east", "a": Vector2(bounds.end.x - 5, 2100), "b": Vector2(bounds.end.x - 85, 2100), "heading_a": 0.0, "heading_b": 0.0},
		{"name": "north", "a": Vector2(3000, bounds.position.y + 5), "b": Vector2(3080, bounds.position.y + 5), "heading_a": -PI / 2, "heading_b": -PI / 2},
		{"name": "south", "a": Vector2(3000, bounds.end.y - 5), "b": Vector2(3080, bounds.end.y - 5), "heading_a": PI / 2, "heading_b": PI / 2},
		{"name": "northwest", "a": bounds.position + Vector2(5, 5), "b": bounds.position + Vector2(85, 5), "heading_a": -PI * 3 / 4, "heading_b": -PI * 3 / 4},
		{"name": "northeast", "a": Vector2(bounds.end.x - 5, bounds.position.y + 5), "b": Vector2(bounds.end.x - 85, bounds.position.y + 5), "heading_a": -PI / 4, "heading_b": -PI / 4},
		{"name": "southwest", "a": Vector2(bounds.position.x + 5, bounds.end.y - 5), "b": Vector2(bounds.position.x + 85, bounds.end.y - 5), "heading_a": PI * 3 / 4, "heading_b": PI * 3 / 4},
		{"name": "southeast", "a": bounds.end - Vector2(5, 5), "b": bounds.end - Vector2(85, 5), "heading_a": PI / 4, "heading_b": PI / 4},
	]
	for scenario in scenarios:
		for weakened in [false, true]:
			var sim = NavalSimulation.new()
			sim.reset("two_sloops", "sloop")
			sim.ships[1]["position"] = Vector2(4800, 3500)
			sim.ships[1]["sails"] = 0.0
			for id in [2, 3]:
				sim.ships[id]["position"] = scenario["a" if id == 2 else "b"]
				sim.ships[id]["heading"] = scenario["heading_a" if id == 2 else "heading_b"]
				if weakened:
					sim.ships[id]["sails"] = 35.0
			var ai = AIController.new()
			var bounded := true
			var full_tracks := true
			var separated := false
			var separation_tick := -1
			var max_separation := 0.0
			var min_separation := INF
			var entered_recovery := false
			var exit_tick := -1
			for tick in 720:
				var obs := sim.ai_observation()
				if tick % 2 == 0:
					obs["ships"] = {3: obs["ships"][3], 2: obs["ships"][2], 1: obs["ships"][1]}
				var commands: Dictionary = ai.commands_for_tick(obs, DT)
				if tick == 0:
					entered_recovery = ai._memory[2].recovering and ai._memory[3].recovering
				if separated and exit_tick < 0 and not ai._memory[2].recovering and not ai._memory[3].recovering:
					exit_tick = tick
				commands[1] = {}
				# AI fire is unrelated to movement/recovery isolation in this fixture.
				for id in [2, 3]:
					commands[id]["fire_port"] = false
					commands[id]["fire_starboard"] = false
				sim.step(DT, commands)
				var separation: float = sim.ships[2]["position"].distance_to(sim.ships[3]["position"])
				max_separation = maxf(max_separation, separation)
				min_separation = minf(min_separation, separation)
				if separation_tick < 0 and separation > 2.0 * Definitions.VESSELS["sloop"]["radius"] \
						+ Definitions.AI["recovery_exit_separation"]:
					separated = true
					separation_tick = tick
				for id in [1, 2, 3]:
					var ship: Dictionary = sim.ships[id]
					var pos: Vector2 = ship["position"]
					bounded = bounded and is_finite(pos.x) and is_finite(pos.y) \
						and pos.x >= bounds.position.x and pos.x <= bounds.end.x \
						and pos.y >= bounds.position.y and pos.y <= bounds.end.y
					full_tracks = full_tracks and ship["hull"] == 100.0 and ship["crew"] == 60.0 \
						and ship["sails"] == (35.0 if weakened and id != 1 else 0.0 if id == 1 else 70.0)
			t.check(bounded and full_tracks, "%s weakened=%s: 720 ticks finite, bounded, unchanged tracks" %
				[scenario["name"], weakened])
			if scenario["name"] in ["same-direction", "upwind", "converging"]:
				t.check(separated, "%s weakened=%s: allies separate beyond exit margin within 720 ticks (first %d, max %.2f)" %
					[scenario["name"], weakened, separation_tick, max_separation])
			if scenario["name"] == "same-direction":
				t.check(entered_recovery and exit_tick >= 0 and min_separation > 2.0 * Definitions.VESSELS["sloop"]["radius"],
					"same-direction weakened=%s: both enter/exit recovery without contact (exit %d, min %.2f)" %
					[weakened, exit_tick, min_separation])
				print("  same-direction weakened=%s: separation tick %d, exit tick %d, min %.2f, max %.2f" %
					[weakened, separation_tick, exit_tick, min_separation, max_separation])


func _test_traffic_deadlines(t) -> void:
	var bounds := Definitions.safe_bounds(Definitions.VESSELS["sloop"]["radius"])
	for side in ["west", "east", "north", "south"]:
		var sim = NavalSimulation.new()
		sim.reset("two_sloops", "sloop")
		sim.ships[1]["position"] = Vector2(4800, 3500)
		sim.ships[1]["sails"] = 0.0
		sim.ships[3]["position"] = Vector2(5000, 2500)
		var at: Vector2 = Vector2(bounds.position.x + 5, 2100) if side == "west" else \
			Vector2(bounds.end.x - 5, 2100) if side == "east" else \
			Vector2(3000, bounds.position.y + 5) if side == "north" else Vector2(3000, bounds.end.y - 5)
		var heading := PI if side == "west" else 0.0 if side == "east" else -PI / 2 if side == "north" else PI / 2
		sim.ships[2]["position"] = at
		sim.ships[2]["heading"] = heading
		var ai = AIController.new()
		var cleared := false
		for tick in 720:
			var commands: Dictionary = ai.commands_for_tick(sim.ai_observation(), DT)
			for id in [2, 3]:
				commands[id]["fire_port"] = false
				commands[id]["fire_starboard"] = false
			sim.step(DT, commands)
			var pos: Vector2 = sim.ships[2]["position"]
			if (pos.x > bounds.position.x + 100 if side == "west" else
				pos.x < bounds.end.x - 100 if side == "east" else
				pos.y > bounds.position.y + 100 if side == "north" else pos.y < bounds.end.y - 100):
				cleared = true
				break
		t.check(cleared, "%s outward sloop clears wall by >100 within 720 ticks" % side)


func _fire_observation(side: String, ally_position: Vector2, ally_active := true) -> Dictionary:
	var sim = NavalSimulation.new()
	sim.reset("two_sloops", "sloop")
	sim.ships[2]["position"] = Vector2(3000, 2100)
	sim.ships[2]["heading"] = 0.0
	sim.ships[1]["position"] = Vector2(3000, 1700 if side == "port" else 2500)
	sim.ships[3]["position"] = ally_position
	sim.ships[3]["active"] = ally_active
	return sim.ai_observation()


func _test_fire_lanes(t) -> void:
	for side in Definitions.SIDES:
		var blocker := Vector2(3000, 1900 if side == "port" else 2300)
		var blocked: Dictionary = AIController.new().commands_for_tick(_fire_observation(side, blocker), DT)[2]
		var clear: Dictionary = AIController.new().commands_for_tick(_fire_observation(side, Vector2(3200, 2100)), DT)[2]
		var dead: Dictionary = AIController.new().commands_for_tick(_fire_observation(side, blocker, false), DT)[2]
		t.check(not blocked["fire_" + side] and clear["fire_" + side] and dead["fire_" + side],
			"%s fire withheld only when active ally is first along firing lane" % side)
		var opposite := "starboard" if side == "port" else "port"
		t.check(blocked["fire_" + opposite] == clear["fire_" + opposite]
			and blocked["turn"] == clear["turn"], "%s blocker does not alter other side or steering" % side)
		var obs := _fire_observation(side, blocker)
		var ai = AIController.new()
		ai.commands_for_tick(obs, DT)
		obs["ships"][3]["position"] = Vector2(3200, 2100)
		t.check(ai.commands_for_tick(obs, DT)[2]["fire_" + side], "%s fire lane reevaluated next tick" % side)
		var sign := -1.0 if side == "port" else 1.0
		for offset in [21.5, 22.5]:
			# The 22-unit sloop circle grazes the shot at x=3021.5; x=3022.5 misses.
			var graze := _fire_observation(side, Vector2(3000 + offset, 2100 + sign * 200.0))
			var grazed: Dictionary = AIController.new().commands_for_tick(graze, DT)[2]
			t.check(grazed["fire_" + side] == (offset > 22.0),
				"%s lane %s sloop circle" % [side, "misses" if offset > 22.0 else "grazes"])
		var beyond: Dictionary = AIController.new().commands_for_tick(
			_fire_observation(side, Vector2(3000, 2100 + sign * 600.0)), DT)[2]
		t.check(beyond["fire_" + side], "%s ally behind target leaves shot available" % side)
		for bearing in [9.9, 10.1]:
			var edge := _fire_observation(side, Vector2(3200, 2100))
			edge["ships"][1]["position"] = Vector2(3000 + 400.0 * tan(deg_to_rad(bearing)), 2100 + sign * 400.0)
			var command: Dictionary = AIController.new().commands_for_tick(edge, DT)[2]
			t.check(command["fire_" + side] == (bearing < 10.0),
				"%s %s-degree target obeys 10-degree fire cone" % [side, bearing])


func _test_assisted_targets(t) -> void:
	for reverse in [false, true]:
		var sim = NavalSimulation.new()
		sim.reset("two_sloops", "sloop")
		sim.ships[1]["position"] = Vector2(3000, 2100)
		sim.ships[1]["heading"] = 0.0
		sim.ships[2]["position"] = Vector2(3000, 2400)
		sim.ships[3]["position"] = Vector2(3000, 2600)
		if reverse:
			sim.ships = {3: sim.ships[3], 2: sim.ships[2], 1: sim.ships[1]}
		t.check(sim.aim_for(1, "starboard")["target_id"] == 2, "nearest assisted enemy is 2 (reverse=%s)" % reverse)
		sim.ships[2]["active"] = false
		t.check(sim.aim_for(1, "starboard")["target_id"] == 3, "aim switches to 3 after 2 inactive (reverse=%s)" % reverse)
		sim.ships[2]["active"] = true
		sim.ships[2]["position"] = Vector2(2990, 2400)
		sim.ships[3]["position"] = Vector2(3010, 2400)
		t.check(sim.aim_for(1, "starboard")["target_id"] == 2, "equal distance picks lower ID (reverse=%s)" % reverse)
		for id in [2, 3]:
			sim.ships[id]["position"].y = 1800
		t.check(sim.aim_for(1, "port")["target_id"] == 2, "port mirror tie picks lower ID (reverse=%s)" % reverse)
		sim.ships[2]["position"] = Vector2(5000, 1800)
		t.check(sim.aim_for(1, "port")["target_id"] == 3, "port switches after 2 outside arc/range")
		sim.ships[3]["active"] = false
		t.check(sim.aim_for(1, "port")["target_id"] == null
			and sim.aim_for(1, "port")["direction"].distance_to(Vector2.UP) < 0.00001,
			"no eligible target leaves port fire perpendicular")


func _shot(sim, owner: int, ammo: String, at: Vector2, remaining := -1.0) -> void:
	sim.projectiles.append({"id": sim.next_projectile_id, "owner_id": owner, "ammo": ammo,
		"position": at, "direction": Vector2.DOWN,
		"remaining_range": Definitions.AMMO[ammo]["range"] if remaining < 0 else remaining,
		"owner_cleared": true})
	sim.next_projectile_id += 1


func _test_friendly_hits(t) -> void:
	for ammo in Definitions.AMMO:
		for active in [true, false]:
			var sim = NavalSimulation.new()
			sim.reset("two_sloops", "sloop")
			sim.ships[2]["position"] = Vector2(3000, 1700)
			sim.ships[2]["heading"] = 0.0
			sim.ships[3]["position"] = Vector2(3000, 1850)
			sim.ships[3]["heading"] = PI / 2.0
			sim.ships[3]["active"] = active
			sim.ships[1]["position"] = Vector2(3000, 1930 if ammo == "grape" else 2150)
			sim.ships[1]["heading"] = PI / 2.0 if active else -PI / 2.0  # sail toward the shot if ally inactive
			sim.ships[2]["weapons"]["starboard"] = {"ammo": ammo, "loads": [1.0, 0.0, 0.0, 0.0]}
			var track: String = Definitions.AMMO[ammo]["track"]
			var full: float = Definitions.VESSELS["sloop"][track]
			for tick in 100:
				sim.step(DT, {2: {"fire_starboard": true}} if tick == 0 else {})
				if sim.events.any(func(e): return e["type"] == "hit"):
					break
			var victim := 3 if active else 1
			t.check(sim.events.any(func(e): return e["type"] == "hit" and e["victim_id"] == victim)
				and sim.ships[victim][track] == full - Definitions.AMMO[ammo]["damage"]
				and sim.ships[2][track] == full and sim.ships[1 if active else 3][track] == full
				and sim.projectiles.is_empty(), "%s hits %s for one projectile, no piercing" %
				[ammo, "ally" if active else "player"])


func _test_swept_collisions(t) -> void:
	for reverse in [false, true]:
		var sim = NavalSimulation.new()
		sim.reset("two_sloops", "sloop")
		sim.ships[1]["position"] = Vector2(3000, 2100)
		sim.ships[2]["position"] = Vector2(3000, 2000)
		sim.ships[3]["position"] = Vector2(3000, 2020)
		if reverse:
			sim.ships = {3: sim.ships[3], 2: sim.ships[2], 1: sim.ships[1]}
		_shot(sim, 1, "round", Vector2(3000, 1980))
		sim.step(DT, {})
		t.check(sim.ships[2]["hull"] == 92.0 and sim.ships[3]["hull"] == 100.0,
			"earliest swept contact blocks second ship (reverse=%s)" % reverse)
		# Later ally movement onto the path still takes the hit; fire-edge gating is not immunity.
		var moving = NavalSimulation.new()
		moving.reset("two_sloops", "sloop")
		moving.ships[1]["position"] = Vector2(3000, 2050)
		moving.ships[1]["heading"] = PI / 2.0
		moving.ships[2]["position"] = Vector2(3000, 1700)
		moving.ships[2]["heading"] = 0.0
		moving.ships[2]["weapons"]["starboard"]["loads"] = [1.0, 0.0, 0.0, 0.0]
		moving.ships[3]["position"] = Vector2(2970, 1850)
		moving.ships[3]["heading"] = 0.0  # sails east into the shot's fixed path
		if reverse:
			moving.ships = {3: moving.ships[3], 2: moving.ships[2], 1: moving.ships[1]}
		var start: Vector2 = moving.ships[3]["position"]
		var fire: Dictionary = AIController.new().commands_for_tick(moving.ai_observation(), DT)[2]
		t.check(fire["fire_starboard"], "ally outside initial lane allows fire (reverse=%s)" % reverse)
		moving.step(DT, {2: {"fire_starboard": true}})
		var launched: bool = moving.events.any(func(e): return e["type"] == "shot" and e["ship_id"] == 2)
		var hit_tick := -1
		for tick in range(1, 40):
			moving.step(DT, {})
			if moving.events.any(func(e): return e["type"] == "hit" and e["victim_id"] == 3):
				hit_tick = tick
				break
		t.check(launched and hit_tick > 1 and moving.ships[3]["position"].x > start.x + 5.0
			and moving.ships[3]["hull"] == 92.0 and moving.ships[1]["hull"] == 100.0
			and moving.projectiles.is_empty(), "sailing ally enters after launch and intercepts shot (reverse=%s, tick=%d)" % [reverse, hit_tick])
	var range_sim = NavalSimulation.new()
	range_sim.reset("two_sloops", "sloop")
	range_sim.ships[1]["position"] = Vector2(4000, 3000)
	range_sim.ships[2]["position"] = Vector2(3000, 1700)
	range_sim.ships[3]["position"] = Vector2(3000, 1900)
	range_sim.ships[3]["sails"] = 0.0
	_shot(range_sim, 2, "round", Vector2(3000, 1850), 5.0)
	range_sim.step(DT, {})
	t.check(range_sim.ships[3]["hull"] == 100.0 and range_sim.projectiles.is_empty(),
		"finite range before ally contact splashes without damage")
	for reverse in [false, true]:
		var crossed = NavalSimulation.new()
		crossed.reset("two_sloops", "sloop")
		crossed.ships[1]["position"] = Vector2(4000, 3000)
		crossed.ships[2]["position"] = Vector2(3000, 2000)
		crossed.ships[3]["position"] = Vector2(3000, 2050)
		if reverse:
			crossed.ships = {3: crossed.ships[3], 2: crossed.ships[2], 1: crossed.ships[1]}
		_shot(crossed, 1, "round", Vector2(3000, 1950))
		crossed._apply_damage(crossed._advance_projectiles(DT * 12, [1, 2, 3]))
		t.check(crossed.ships[2]["hull"] == 92.0 and crossed.ships[3]["hull"] == 100.0
			and crossed.projectiles.is_empty(), "two circles crossed in one tick: first hit only (reverse=%s)" % reverse)
		crossed.ships[2]["hull"] = 100.0
		crossed.ships[3]["position"] = crossed.ships[2]["position"]
		_shot(crossed, 1, "round", Vector2(3000, 1950))
		crossed._apply_damage(crossed._advance_projectiles(DT * 12, [1, 2, 3]))
		t.check(crossed.ships[2]["hull"] == 92.0 and crossed.ships[3]["hull"] == 100.0,
			"equal contact time goes to lower ID (reverse=%s)" % reverse)
	var muzzle = NavalSimulation.new()
	muzzle.reset("two_sloops", "sloop")
	muzzle.ships[1]["position"] = Vector2(4000, 3000)
	muzzle.ships[2]["position"] = Vector2(3000, 2000)
	muzzle.ships[3]["position"] = Vector2(3000, 2015)
	_shot(muzzle, 2, "round", muzzle.ships[2]["position"])
	muzzle.projectiles[0]["owner_cleared"] = false
	muzzle._apply_damage(muzzle._advance_projectiles(DT, [1, 2, 3]))
	t.check(muzzle.ships[2]["hull"] == 100.0 and muzzle.ships[3]["hull"] == 92.0,
		"muzzle exit skips only firing ship, not overlapping ally")


func _test_outcomes(t) -> void:
	for reverse in [false, true]:
		for case in [
			{"hits": [2], "want": ""}, {"hits": [1, 2], "want": "defeat"},
			{"hits": [2, 3], "want": "victory"}, {"hits": [1, 2, 3], "want": "draw"},
		]:
			var sim = NavalSimulation.new()
			sim.reset("two_sloops", "sloop")
			for id in [1, 2, 3]:
				sim.ships[id]["position"] = Vector2(2000 + id * 500, 2100)
				sim.ships[id]["sails"] = 1.0
			if reverse:
				sim.ships = {3: sim.ships[3], 2: sim.ships[2], 1: sim.ships[1]}
			var ids: Array = case["hits"].duplicate()
			if reverse:
				ids.reverse()
			for id in ids:
				_shot(sim, 2 if id == 1 else 1, "chain", sim.ships[id]["position"] - Vector2(0, 10))
			sim.step(DT, {})
			t.check(sim.result.get("outcome", "") == case["want"],
				"simultaneous disable %s outcome %s independent of order %s" % [ids, case["want"], reverse])
			if case["want"] == "":
				t.check(not sim.ships[2]["active"] and sim.ships[3]["active"], "one defeat leaves battle running")
				var last: Vector2 = sim.ships[3]["position"]
				sim.step(DT, {3: {"turn": 1.0}})
				t.check(sim.ships[3]["position"] != last and sim.ships[3]["active"],
					"surviving enemy still maneuvers after first defeat")
		var last = NavalSimulation.new()
		last.reset("two_sloops", "sloop")
		last.ships[2]["active"] = false
		last.ships[2]["defeat_reasons"] = ["sails"]
		last.ships[1]["position"] = Vector2(2500, 2100)
		last.ships[3]["position"] = Vector2(3500, 2100)
		last.ships[1]["hull"] = 2.0
		last.ships[3]["hull"] = 2.0
		_shot(last, 3, "round", last.ships[1]["position"] - Vector2(0, 10))
		_shot(last, 1, "round", last.ships[3]["position"] - Vector2(0, 10))
		last.step(DT, {})
		t.check(last.result.get("outcome") == "draw" and last.result["defeated"].size() == 3,
			"player and last enemy simultaneous defeat draws with other already inactive")
	for ammo in ["round", "chain", "grape"]:
		var sim = NavalSimulation.new()
		sim.reset("two_sloops", "sloop")
		sim.ships[1]["position"] = Vector2(2400, 2100)
		sim.ships[2]["position"] = Vector2(3400, 1700)
		sim.ships[3]["position"] = Vector2(3400, 2500)
		var track: String = Definitions.AMMO[ammo]["track"]
		for id in [2, 3]:
			sim.ships[id][track] = 1.0
			_shot(sim, 1, ammo, sim.ships[id]["position"] - Vector2(0, 10))
		sim.step(DT, {})
		t.check(sim.result.get("outcome") == "victory" and sim.result["defeated"].size() == 2
			and sim.result["defeated"][0]["reason"] == ("sunk" if ammo == "round" else "disabled"),
			"%s track defeat resolves two-enemy victory" % ammo)
	var combined = NavalSimulation.new()
	combined.reset("two_sloops", "sloop")
	combined.ships[2]["hull"] = 1.0
	combined.ships[2]["sails"] = 1.0
	combined.ships[2]["crew"] = 1.0
	for ammo in Definitions.AMMO:
		_shot(combined, 1, ammo, combined.ships[2]["position"] - Vector2(0, 10))
	combined.step(DT, {})
	t.check(combined.ships[2]["defeat_reasons"] == ["sunk"], "sunk takes precedence over combined disabled reasons")
	var both = NavalSimulation.new()
	both.reset("two_sloops", "sloop")
	both.ships[2]["sails"] = 1.0
	both.ships[2]["crew"] = 1.0
	for ammo in ["chain", "grape"]:
		_shot(both, 1, ammo, both.ships[2]["position"] - Vector2(0, 10))
	both.step(DT, {})
	t.check(both.ships[2]["defeat_reasons"] == ["sails", "crew"] and both.result.is_empty(),
		"combined disabled reasons remain recorded while survivor keeps encounter open")


func _test_simultaneous_fire(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("two_sloops", "sloop")
	sim.ships[1]["position"] = Vector2(3000, 2100)
	sim.ships[2]["position"] = Vector2(3000, 1800)
	sim.ships[3]["position"] = Vector2(3000, 2400)
	for id in [1, 2, 3]:
		for side in Definitions.SIDES:
			sim.ships[id]["weapons"][side]["loads"] = [1.0, 0.0, 0.0, 0.0]
	_shot(sim, 1, "round", sim.ships[2]["position"] - Vector2(0, 10))
	sim.ships[2]["hull"] = 1.0
	sim.step(DT, {1: {"fire_port": true}, 2: {"fire_starboard": true}, 3: {"fire_port": true}})
	t.check(not sim.ships[2]["active"] and sim.events.any(func(e): return e["type"] == "shot" and e["ship_id"] == 2)
		and sim.events.any(func(e): return e["type"] == "shot" and e["ship_id"] == 3),
		"both enemies active at step start fire before one is defeated")
	var obs := sim.ai_observation()
	t.check(not obs["ships"][2]["active"] and not obs["ships"][2].has("sides")
		and obs["ships"][2]["id"] == 2 and obs["ships"][2]["hull"] == 0.0
		and sim.aim_for(1, "port")["target_id"] == null,
		"defeated ship keeps identity but has no active weapons or aim eligibility")


func _test_defeated_exclusion(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("two_sloops", "sloop")
	sim.ships[1]["position"] = Vector2(3000, 2100)
	sim.ships[2]["position"] = Vector2(3000, 1950)
	sim.ships[2]["hull"] = 1.0
	sim.ships[3]["position"] = Vector2(3000, 1800)
	_shot(sim, 1, "round", sim.ships[2]["position"] - Vector2(0, 10))
	sim.step(DT, {})
	t.check(not sim.ships[2]["active"] and sim.ships[3]["active"] and sim.result.is_empty(),
		"first enemy sunk without ending battle")
	var dead_at := Vector2(3000, 2000)
	sim.ships[2]["position"] = dead_at
	sim.ships[3]["position"] = dead_at  # only active ships participate in contact separation
	sim.ships[3]["heading"] = 0.0
	sim.ships[1]["position"] = Vector2(4000, 3000)
	sim.step(DT, {2: {"turn": 1.0, "fire_port": true}})
	var expected: Vector2 = dead_at + Vector2.RIGHT * Definitions.VESSELS["sloop"]["full_speed"] \
		* Definitions.wind_multiplier(0.0, sim.wind_heading) * DT
	t.check(sim.ships[2]["position"] == dead_at and sim.ships[3]["position"].distance_to(expected) < 0.001
		and sim.ships[3]["position"].distance_to(dead_at) < 44.0
		and not sim.events.any(func(e): return e["type"] == "shot" and e["ship_id"] == 2),
		"defeated ship cannot act or displace overlapping active ship")
	sim.ships[1]["position"] = Vector2(3000, 2100)
	sim.ships[1]["sails"] = 1.0
	sim.ships[1]["heading"] = PI  # positive sails keep player active; upwind drift stays in lane
	sim.ships[2]["position"] = Vector2(3000, 1950)
	sim.ships[3]["position"] = Vector2(3000, 1800)
	sim.ships[3]["sails"] = 0.0  # keep centers aligned while the shot travels
	sim.ships[3]["weapons"]["starboard"]["loads"] = [1.0, 0.0, 0.0, 0.0]
	var command: Dictionary = AIController.new().commands_for_tick(sim.ai_observation(), DT)
	t.check(command.keys() == [3] and command[3]["fire_starboard"],
		"survivor may fire through defeated ally using ordinary AI commands")
	var hit := false
	for tick in 60:
		var commands := command if tick == 0 else {}
		sim.step(DT, commands)
		if sim.events.any(func(e): return e["type"] == "hit" and e["victim_id"] == 1):
			hit = true
			break
	t.check(hit and sim.ships[1]["hull"] == 92.0 and sim.ships[2]["hull"] == 0.0
		and sim.projectiles.is_empty() and sim.result.is_empty(),
		"survivor's projectile crosses defeated ally, hits player once and combat continues")
