extends RefCounted
## Duel checks. Plan 03 task 1: fixed presets; task 2: command-only AI contract.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const AIController := preload("res://sim/ai_controller.gd")

const DT := 1.0 / 60.0
const COMMAND_KEYS := ["turn", "toggle_sails", "fire_port", "fire_starboard", "cycle_port", "cycle_starboard"]
const SHIP_KEYS := ["id", "team", "vessel_id", "position", "heading", "speed", "reefed",
	"hull", "sails", "crew", "active"]

const PLAYER_IDS: Array[String] = ["sloop", "brig", "frigate"]

const PRESETS := {
	"duel_sloop": {
		"enemy": "sloop", "player_position": Vector2(2500, 2100), "player_heading": 0.0,
		"enemy_position": Vector2(3500, 2100), "enemy_heading": PI, "wind_heading": 0.0,
	},
	"duel_brig": {
		"enemy": "brig", "player_position": Vector2(3000, 1500), "player_heading": PI / 2.0,
		"enemy_position": Vector2(3000, 2500), "enemy_heading": -PI / 2.0, "wind_heading": 0.0,
	},
	"duel_frigate": {
		"enemy": "frigate", "player_position": Vector2(2500, 2100), "player_heading": 0.0,
		"enemy_position": Vector2(3500, 2100), "enemy_heading": PI, "wind_heading": PI / 4.0,
	},
}


func run(t) -> bool:
	for preset_id in PRESETS:
		for vessel_id in PLAYER_IDS:
			_test_reset(t, preset_id, vessel_id)
	_test_independent_gun_arrays(t)
	_test_enemy_is_not_practice_target(t)
	_test_observation_schema(t)
	_test_observation_is_a_copy(t)
	_test_ai_command_contract(t)
	_test_ai_never_mutates_sim(t)
	_test_reset_clears_ai_memory(t)
	_test_replay_ai_commands(t)
	_test_steering_fixtures(t)
	_test_ammo_candidates(t)
	_test_ammo_hysteresis(t)
	_test_cycle_realization(t)
	_test_fire_gating(t)
	return true


func _expected_loads(vessel_id: String) -> Array:
	var loads := []
	loads.resize(Definitions.VESSELS[vessel_id]["guns_per_side"])
	loads.fill(1.0)
	return loads


## Full tracks/full sails/loaded round sides according to the vessel definitions.
func _full_ship(ship: Dictionary) -> bool:
	var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
	if ship["reefed"] or not ship["active"] or not ship["defeat_reasons"].is_empty():
		return false
	if [ship["hull"], ship["sails"], ship["crew"]] != [vessel["hull"], vessel["sails"], vessel["crew"]]:
		return false
	if ship["speed"] != 0.0:
		return false
	for side in ["port", "starboard"]:
		if ship["weapons"][side]["ammo"] != "round" or ship["weapons"][side]["loads"] != _expected_loads(ship["vessel_id"]):
			return false
	return true


func _test_reset(t, preset_id: String, vessel_id: String) -> void:
	var want: Dictionary = PRESETS[preset_id]
	var sim = NavalSimulation.new()
	sim.reset(preset_id, vessel_id)
	var label := "%s/%s" % [preset_id, vessel_id]
	t.check(sim.ships.keys() == [1, 2], "%s: ships 1 and 2 only" % label)
	var player: Dictionary = sim.ships[1]
	var enemy: Dictionary = sim.ships[2]
	t.check(player["team"] == 0 and enemy["team"] == 1, "%s: teams 0 and 1" % label)
	t.check(player["vessel_id"] == vessel_id and enemy["vessel_id"] == want["enemy"],
		"%s: player %s faces enemy %s" % [label, vessel_id, want["enemy"]])
	t.check(enemy["role"] == "ship" and player["role"] == "ship", "%s: both roles ship" % label)
	t.check(player["position"] == want["player_position"] and enemy["position"] == want["enemy_position"],
		"%s: preset positions" % label)
	t.check(player["heading"] == want["player_heading"] and enemy["heading"] == want["enemy_heading"],
		"%s: preset headings" % label)
	t.check(sim.wind_heading == want["wind_heading"] and sim.preset_id == preset_id
		and sim.selected_vessel_id == vessel_id, "%s: wind/preset/vessel recorded" % label)
	t.check(_full_ship(player) and _full_ship(enemy), "%s: both full, unreefed, loaded round" % label)
	t.check(sim.events.is_empty() and sim.projectiles.is_empty() and sim.result.is_empty()
		and sim.next_projectile_id == 1, "%s: no events/projectiles/result" % label)
	t.check(sim.elapsed == 0.0, "%s: elapsed 0" % label)
	var sum_r: float = Definitions.VESSELS[vessel_id]["radius"] + Definitions.VESSELS[want["enemy"]]["radius"]
	t.check(player["position"].distance_to(enemy["position"]) > sum_r, "%s: spawn positions do not overlap" % label)
	t.check(Definitions.safe_bounds(Definitions.VESSELS[vessel_id]["radius"]).has_point(player["position"])
		and Definitions.safe_bounds(Definitions.VESSELS[want["enemy"]]["radius"]).has_point(enemy["position"]),
		"%s: spawn positions inside safe bounds" % label)


## Mutating one duel ship's gun loads/defeat reasons leaves every other array untouched.
func _test_independent_gun_arrays(t) -> void:
	for preset_id in PRESETS:
		var a = NavalSimulation.new()
		var b = NavalSimulation.new()
		a.reset(preset_id, "brig")
		b.reset(preset_id, "brig")
		a.ships[1]["weapons"]["port"]["loads"][1] = 0.25
		a.ships[2]["defeat_reasons"].append("x")
		t.check(a.ships[1]["weapons"]["starboard"]["loads"][1] == 1.0
			and a.ships[1]["weapons"]["port"]["loads"] != _expected_loads("brig"),
			"%s: port load change leaves starboard" % preset_id)
		t.check(b.ships[1]["weapons"]["port"]["loads"][1] == 1.0
			and b.ships[2]["defeat_reasons"].is_empty(), "%s: other simulation untouched" % preset_id)
		a.reset(preset_id, "brig")
		t.check(_full_ship(a.ships[1]) and _full_ship(a.ships[2]), "%s: reset allocates fresh arrays" % preset_id)


## The duel enemy sails and steers on command, unlike the practice target it replaced.
func _test_enemy_is_not_practice_target(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("duel_brig", "sloop")
	var before: Vector2 = sim.ships[2]["position"]
	var heading: float = sim.ships[2]["heading"]
	sim.step(1.0 / 60.0, {2: {"turn": 1.0}})
	var enemy: Dictionary = sim.ships[2]
	t.check(enemy["heading"] > heading and enemy["position"] != before, "enemy turns and moves when commanded")
	t.check(enemy["speed"] > 0.0, "enemy sails rather than sitting still")


## Deep sim snapshot used for AI purity comparisons.
func _snapshot(sim) -> Dictionary:
	return {"ships": sim.ships.duplicate(true), "projectiles": sim.projectiles.duplicate(true),
		"events": sim.events.duplicate(true), "elapsed": sim.elapsed, "result": sim.result.duplicate(true),
		"next_projectile_id": sim.next_projectile_id}


## Observation exposes contract fields only, active ships add reduced per-side state.
func _test_observation_schema(t) -> void:
	for preset_id in PRESETS:
		var sim = NavalSimulation.new()
		sim.reset(preset_id, "brig")
		var obs: Dictionary = sim.ai_observation()
		t.check(obs.keys() == ["ships"], "%s: observation top level is ships only" % preset_id)
		t.check(obs["ships"].keys() == [1, 2], "%s: observation holds both ships" % preset_id)
		for id in [1, 2]:
			var ship: Dictionary = obs["ships"][id]
			t.check(SHIP_KEYS.all(func(k): return ship.has(k)), "%s: ship %d has contract fields" % [preset_id, id])
			t.check(ship.keys().size() == SHIP_KEYS.size() + 1 and ship.has("sides"),
				"%s: active ship %d adds sides" % [preset_id, id])
			var expected_loads: int = 0
			for load in sim.ships[id]["weapons"]["port"]["loads"]:
				expected_loads += 1 if load == 1.0 else 0
			for side in ["port", "starboard"]:
				var weapon: Dictionary = ship["sides"][side]
				t.check(weapon.keys() == ["ammo", "ready", "total"], "%s: %s side keys" % [preset_id, side])
				t.check(weapon["ammo"] == "round" and weapon["ready"] == expected_loads
					and weapon["total"] == sim.ships[id]["weapons"][side]["loads"].size(),
					"%s: ship %d %s ready counts follow load==1.0" % [preset_id, id, side])
		sim.ships[2]["active"] = false
		obs = sim.ai_observation()
		t.check(not obs["ships"][2].has("sides"), "%s: inactive ship has no sides" % preset_id)
		t.check(obs["ships"][2]["hull"] == sim.ships[2]["hull"], "%s: inactive ship still exposes hull" % preset_id)


## Mutating the observation cannot reach the authoritative simulation.
func _test_observation_is_a_copy(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("duel_brig", "sloop")
	var before := _snapshot(sim)
	var obs: Dictionary = sim.ai_observation()
	obs["ships"][2]["hull"] = 0.0
	obs["ships"][2]["position"] = Vector2.ZERO
	obs["ships"][2]["heading"] = 99.0
	obs["ships"][2]["sides"]["port"]["ready"] = 0
	obs["ships"][2]["sides"]["port"]["ammo"] = "grape"
	t.check(_snapshot(sim) == before, "mutating the observation leaves sim unchanged")


## Commands only use allowed keys, finite clamped steering and boolean edges.
func _test_ai_command_contract(t) -> void:
	var ai = AIController.new()
	for preset_id in PRESETS:
		var sim = NavalSimulation.new()
		sim.reset(preset_id, "sloop")
		var commands: Dictionary = ai.commands_for_tick(sim.ai_observation(), DT)
		t.check(commands.keys() == [2], "%s: commands keyed by active opposition only" % preset_id)
		var command: Dictionary = commands[2]
		t.check(command.keys().all(func(k): return k in COMMAND_KEYS), "%s: only allowed command keys" % preset_id)
		t.check(command.keys().size() == COMMAND_KEYS.size(), "%s: every command key initialized" % preset_id)
		t.check(is_finite(command["turn"]) and command["turn"] >= -1.0 and command["turn"] <= 1.0,
			"%s: turn finite and clamped" % preset_id)
		for key in ["toggle_sails", "fire_port", "fire_starboard", "cycle_port", "cycle_starboard"]:
			t.check(typeof(command[key]) == TYPE_BOOL, "%s: %s is boolean" % [preset_id, key])
	# No active player target: no command at all.
	var sim = NavalSimulation.new()
	sim.reset("duel_sloop", "sloop")
	sim.ships[1]["active"] = false
	var ai2 = AIController.new()
	t.check(ai2.commands_for_tick(sim.ai_observation(), DT).is_empty(), "inactive player: no command")
	# No opposition: nothing to command.
	var empty = ai2.commands_for_tick({"ships": {}}, DT)
	t.check(empty.is_empty(), "no ships: no commands")
	# Player-side ship in an observation without opposition also produces nothing.
	t.check(ai2.commands_for_tick({"ships": {1: {"id": 1, "team": 0, "active": true}}}, DT).is_empty(),
		"no enemy ships: no commands")


## Observation and AI calls leave the authoritative state deeply unchanged.
func _test_ai_never_mutates_sim(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("duel_frigate", "brig")
	sim.ships[2]["sails"] = 40.0
	sim.ships[2]["crew"] = 30.0
	sim.ships[2]["weapons"]["port"]["loads"] = [1.0, 0.5, 0.0, 0.25, 0.0, 1.0, 0.9, 0.1]
	var before := _snapshot(sim)
	var ai = AIController.new()
	for i in 10:
		var obs: Dictionary = sim.ai_observation()
		var commands: Dictionary = ai.commands_for_tick(obs, DT)
		t.check(commands.keys() == [2], "damaged enemy still gets a command (tick %d)" % i)
	t.check(_snapshot(sim) == before, "repeated observation/AI calls leave sim deeply unchanged")


## A reset AI behaves exactly like a fresh instance.
func _test_reset_clears_ai_memory(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("duel_brig", "brig")
	var obs: Dictionary = sim.ai_observation()
	var seasoned = AIController.new()
	for i in 120:
		seasoned.commands_for_tick(obs, DT)
	seasoned.reset()
	var fresh = AIController.new()
	t.check(seasoned.commands_for_tick(obs, DT) == fresh.commands_for_tick(obs, DT),
		"reset AI matches a fresh instance on the same observation")


## AI commands replayed as ordinary commands reproduce identical simulations.
func _test_replay_ai_commands(t) -> void:
	for preset_id in PRESETS:
		var live = NavalSimulation.new()
		live.reset(preset_id, "brig")
		var replay = NavalSimulation.new()
		replay.reset(preset_id, "brig")
		for sim in [live, replay]:
			sim.ships[2]["sails"] = 40.0
			sim.ships[2]["crew"] = 30.0  # damaged sails/crew expose any AI-only multiplier
		var ai = AIController.new()
		var tape := []
		var identical := true
		for i in 120:
			var commands: Dictionary = ai.commands_for_tick(live.ai_observation(), DT)
			commands[1] = {"turn": 0.5 if i < 60 else -0.5, "toggle_sails": i == 30, "fire_port": i == 20}
			tape.append(commands.duplicate(true))
			live.step(DT, commands)
			replay.step(DT, tape[i])
			if _snapshot(live) != _snapshot(replay):
				identical = false
				break
		t.check(identical, "%s: replayed AI commands reproduce movement/reload/damage exactly" % preset_id)
		t.check(live.elapsed == replay.elapsed and live.next_projectile_id == replay.next_projectile_id,
			"%s: replayed clocks and projectile counters match" % preset_id)


## Minimal observation matching the task-2 contract; overrides applied to the base spec.
func _observation(overrides: Dictionary = {}) -> Dictionary:
	var ships := {}
	for spec in [
		{"id": 1, "team": 0, "vessel_id": "brig", "position": Vector2(3520, 2100), "heading": PI},
		{"id": 2, "team": 1, "vessel_id": "brig", "position": Vector2(3000, 2100), "heading": PI / 2.0},
	]:
		ships[spec["id"]] = spec
	var obs := {"ships": ships}
	for id in overrides:
		for key in overrides[id]:
			obs["ships"][id][key] = overrides[id][key]
	return obs


## The task-2 schema adds sides to every active ship; keep it valid for steering tests.
## Overrides apply last so track/vessel substitutions survive the full-field fill.
func _full_observation(overrides: Dictionary = {}) -> Dictionary:
	var obs := _observation()
	for id in obs["ships"]:
		var ship: Dictionary = obs["ships"][id]
		var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
		ship["speed"] = 0.0
		ship["reefed"] = false
		ship["hull"] = vessel["hull"]
		ship["sails"] = vessel["sails"]
		ship["crew"] = vessel["crew"]
		ship["active"] = true
		var sides := {}
		for side in Definitions.SIDES:
			sides[side] = {"ammo": "round", "ready": vessel["guns_per_side"], "total": vessel["guns_per_side"]}
		ship["sides"] = sides
	for id in overrides:
		for key in overrides[id]:
			obs["ships"][id][key] = overrides[id][key]
	return obs


func _enemy_command(obs: Dictionary, ai = null) -> Dictionary:
	var controller = ai if ai != null else AIController.new()
	return controller.commands_for_tick(obs, DT).get(2, {})


## AI at (3000,2100) facing south, target due east: port tangent (0,1), starboard (0,-1),
## zero turn at round's desired radius 520.
func _test_steering_fixtures(t) -> void:
	var ai = AIController.new()
	var command := _enemy_command(_full_observation(), ai)
	# Target 520 east: u=(1,0), bearing 0, port chosen (heading PI/2 equals bearing+PI/2),
	# radial 0 keeps desired heading at the tangent PI/2 -> no turn.
	t.check(absf(command["turn"]) < 1e-9, "zero turn at round's desired radius 520 (port)")
	t.check(ai._memory[2].side == "port", "port selected when its broadside already faces the target")
	t.check(not command["toggle_sails"] and not command["cycle_port"],
		"fixture settles without toggle/cycle")
	# Starboard selection: heading -PI/2 makes starboard the closer broadside.
	var star := AIController.new()
	var command2 := _enemy_command(_full_observation({2: {"heading": -PI / 2.0}}), star)
	t.check(star._memory[2].side == "starboard", "starboard selected when its broadside faces the target")
	# Wrapped heading errors +0.5/-0.5 saturate the turn; within 3 degrees is dead.
	var near_cmd := _enemy_command(_full_observation({2: {"heading": PI / 2.0 - 0.5}}))
	t.check(near_cmd["turn"] > 0.99, "+0.5 heading error turns full positive")
	var far_cmd := _enemy_command(_full_observation({2: {"heading": PI / 2.0 + 0.5}}))
	t.check(far_cmd["turn"] < -0.99, "-0.5 heading error turns full negative")
	var settle := _enemy_command(_full_observation({2: {"heading": PI / 2.0 + 2.0 * PI / 180.0}}))
	t.check(settle["turn"] == 0.0, "2-degree error inside the 3-degree dead band")
	# Sails: >35-degree error reefs; a settled ship keeps full sails unreefed.
	var reef := _enemy_command(_full_observation({2: {"heading": PI / 2.0 + 40.0 * PI / 180.0}}))
	t.check(reef["toggle_sails"], "40-degree error requests reefing")
	t.check(not _enemy_command(_full_observation())["toggle_sails"], "settled ship keeps full sails")


## Ordered candidate rules per the plan's distance/fraction table. Candidate goals
## need 1.0s stability plus the 10.0s switch cooldown from reset before committing.
func _test_ammo_candidates(t) -> void:
	var cases := [
		{"distance": 700.0, "overrides": {}, "want": "round"},
		{"distance": 500.0, "overrides": {1: {"sails": 0.40 * Definitions.VESSELS["brig"]["sails"]}}, "want": "chain"},
		{"distance": 250.0, "overrides": {1: {"crew": 0.40 * Definitions.VESSELS["brig"]["crew"]}}, "want": "grape"},
		{"distance": 500.0, "overrides": {1: {"vessel_id": "sloop"}, 2: {"vessel_id": "frigate"}}, "want": "chain"},
	]
	for c in cases:
		var ai = AIController.new()
		var obs := _full_observation(c["overrides"])
		obs["ships"][1]["position"] = Vector2(3000.0 + c["distance"], 2100.0)
		var cycled := false
		for i in 720:  # 12s: past stability plus cooldown
			var command := _enemy_command(obs, ai)
			cycled = cycled or command.get("cycle_port", false) or command.get("cycle_starboard", false)
		var goal: String = ai._memory[2].goal["port"]
		t.check(goal == c["want"], "distance %s with %s commits %s (got %s)" % [c["distance"], c["overrides"], c["want"], goal])
		t.check(c["want"] == "round" or cycled, "distance %s emits cycle commands toward %s" % [c["distance"], c["want"]])
		t.check(c["want"] != "round" or not cycled, "distance 700 keeps round without cycling")
	# Healthy brig at 250: grape allowed (90/5 <= 160/8) with no pre-existing damage.
	var healthy := AIController.new()
	var healthy_obs := _full_observation()
	healthy_obs["ships"][1]["position"] = Vector2(3250, 2100)
	for i in 720:
		_enemy_command(healthy_obs, healthy)
	t.check(healthy._memory[2].goal["port"] == "grape", "healthy brig at 250 permits grape")


## Alternating 539/541 for 2s never commits a switch (candidate never stable 1.0s).
func _test_ammo_hysteresis(t) -> void:
	var ai = AIController.new()
	var obs := _full_observation()
	for i in 240:
		obs["ships"][1]["position"] = Vector2(3000.0 + (539.0 if i % 2 == 0 else 541.0), 2100.0)
		var command := _enemy_command(obs, ai)
		if command.get("cycle_port", false) or command.get("cycle_starboard", false):
			t.check(false, "alternating 539/541 caused a cycle on tick %d" % i)
			return
	t.check(ai._memory[2].goal["port"] == "round" and ai._memory[2].goal["starboard"] == "round",
		"2s of alternating boundary distance keeps round committed")


## Round->grape takes exactly two consecutive cycle commands, no fire while cycling,
## no repeated cycles at goal, no new switch within 10s of reaching it.
func _test_cycle_realization(t) -> void:
	var ai = AIController.new()
	var obs := _full_observation({1: {"crew": 10.0}})
	obs["ships"][1]["position"] = Vector2(3250, 2100)
	for i in 600:  # 10s: past the switch cooldown from reset
		_enemy_command(obs, ai)
	var cycles := 0
	var fires_during_cycles := false
	for i in 300:
		var command := _enemy_command(obs, ai)
		if command.get("cycle_port", false):
			cycles += 1
			fires_during_cycles = fires_during_cycles or command.get("fire_port", false)
			# The observation must advance with the sim's cycle order round->chain->grape.
			obs["ships"][2]["sides"]["port"]["ammo"] = ["chain", "grape"][mini(cycles - 1, 1)]
			obs["ships"][2]["sides"]["port"]["ready"] = 0
		elif cycles > 0:
			break  # cycling finished
	t.check(cycles == 2, "round->grape takes exactly two cycle commands (got %d)" % cycles)
	t.check(not fires_during_cycles, "no fire while cycling")
	t.check(obs["ships"][2]["sides"]["port"]["ammo"] == "grape", "observation confirms grape at goal")
	# At goal: no further cycles for 10s, fire resumes once ready and aligned.
	var stray_cycles := 0
	obs["ships"][2]["sides"]["port"]["ready"] = 6
	var resumed := false
	for i in 599:
		var command := _enemy_command(obs, ai)
		stray_cycles += 1 if command.get("cycle_port", false) else 0
		resumed = resumed or command.get("fire_port", false)
	t.check(stray_cycles == 0, "no repeated cycles at goal within 10s dwell")
	t.check(resumed, "aligned ready side fires after reaching goal")


## One ready gun and 8-degree bearing fires; 13 degrees, out of range, no ready guns
## or inactive target do not.
func _test_fire_gating(t) -> void:
	var obs := _full_observation()
	obs["ships"][1]["position"] = Vector2(3400, 2100)  # 400 east: within round's 900 range
	obs["ships"][2]["sides"]["port"]["ready"] = 1
	var fired := _enemy_command(obs)
	t.check(fired.get("fire_port", false), "one ready gun at 8-degree bearing fires")
	var wide := _full_observation()
	wide["ships"][1]["position"] = Vector2(3400, 2100)
	wide["ships"][2]["sides"]["port"]["ready"] = 1
	wide["ships"][2]["heading"] = PI / 2.0 + 13.0 * PI / 180.0  # 13 degrees off the broadside
	t.check(not _enemy_command(wide).get("fire_port", false), "13-degree bearing does not fire")
	var far := _full_observation()
	far["ships"][1]["position"] = Vector2(4500, 2100)  # 1500: outside every range
	far["ships"][2]["sides"]["port"]["ready"] = 6
	t.check(not _enemy_command(far).get("fire_port", false), "out-of-range target does not fire")
	var unloaded := _full_observation()
	unloaded["ships"][1]["position"] = Vector2(3400, 2100)
	unloaded["ships"][2]["sides"]["port"]["ready"] = 0
	t.check(not _enemy_command(unloaded).get("fire_port", false), "no ready guns does not fire")
	var dead := _full_observation()
	dead["ships"][1]["position"] = Vector2(3400, 2100)
	dead["ships"][2]["sides"]["port"]["ready"] = 1
	dead["ships"][1]["active"] = false
	t.check(_enemy_command(dead).is_empty(), "inactive target produces no command at all")
