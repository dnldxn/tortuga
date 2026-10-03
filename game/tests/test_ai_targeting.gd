extends RefCounted
## Nearest-sticky AI targeting (Phase 3 plan 01 task 4): the opposition AI targets the nearest
## active enemy (ties to the lowest id), keeps it until another enemy is closer than
## AI.retarget_ratio x the current distance, and re-targets when it vanishes.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const AiController := preload("res://sim/ai_controller.gd")
const DT := 1.0 / 60.0


func run(t) -> bool:
	for test in [_test_target_rule, _test_target_vanishes, _test_sticky_through_ticks]:
		t.check(test.call(t) == true, "ai targeting: %s completed" % test.get_method())
	return true


## brig_squadron with captains 100 (at (4000, 2100)) and 101 (at (3000 - d, 2100)); AI 3/4 inactive,
## AI 2 at (3000, 2100).
func _fixture(d: float):
	var sim = NavalSimulation.new()
	sim.reset_battle("brig_squadron")
	sim.step(DT, {}, [{"op": "add_captain", "ship_id": 100, "vessel_id": "brig"},
		{"op": "add_captain", "ship_id": 101, "vessel_id": "brig"}])
	for id in [3, 4]:
		sim.ships[id]["active"] = false
	sim.ships[2]["position"] = Vector2(3000, 2100)
	sim.ships[100]["position"] = Vector2(4000, 2100)
	sim.ships[101]["position"] = Vector2(3000.0 - d, 2100)
	return sim


func _pick(ai, sim, current: int) -> int:
	var obs: Dictionary = sim.ai_observation()
	return ai._target_for(obs, obs["ships"][2], current).get("id", -1)


func _test_target_rule(t) -> bool:
	var ai = AiController.new()
	t.check(Definitions.AI["retarget_ratio"] == 0.7, "AI retarget_ratio is 0.7")
	var sim = _fixture(800.0)
	t.check(_pick(ai, sim, -1) == 101, "nearest: 101 at 800 beats 100 at 1000")
	t.check(_pick(ai, sim, 100) == 100, "sticky: 800 is not closer than 0.7 x 1000")
	sim = _fixture(699.5)
	t.check(_pick(ai, sim, 100) == 101, "switch: 699.5 < 0.7 x 1000")
	sim = _fixture(800.0)
	t.check(_pick(ai, sim, 999) == 101, "vanished: a missing current target is replaced by the nearest")
	var obs: Dictionary = sim.ai_observation()
	obs["ships"][100]["active"] = false
	t.check(ai._target_for(obs, obs["ships"][2], 100).get("id", -1) == 101, "vanished: an inactive current target is replaced")
	obs = sim.ai_observation()
	t.check(ai._target_for(obs, obs["ships"][2], 3).get("id", -1) == 101, "an ally current target is replaced by the nearest enemy")
	sim = _fixture(1200.0)
	sim.step(DT, {}, [{"op": "linger", "ship_id": 100}])
	t.check(_pick(ai, sim, -1) == 100, "a lingering captain is still a target")
	var duel = NavalSimulation.new()
	duel.reset("duel_brig", "brig")
	t.check(_pick(ai, duel, -1) == 1, "offline: the single enemy is the player")
	obs = duel.ai_observation()
	t.check(ai._target_for(obs, obs["ships"][2]).get("id", -1) == 1, "current_id defaults to -1")
	return true


func _test_target_vanishes(t) -> bool:
	var sim = _fixture(800.0)
	sim.ships[100]["position"] = Vector2(3600, 2100)
	sim.ships[101]["position"] = Vector2(2000, 2100)
	var ai = AiController.new()
	var commands: Dictionary = ai.commands_for_tick(sim.ai_observation(), DT)
	t.check(ai._memory.has(2) and ai._memory[2].target_id == 100, "AI 2 targets the nearer captain 100")
	t.check(commands.keys() == [2], "only the active AI ship is commanded")
	sim.step(DT, {}, [{"op": "abandon", "ship_id": 100}])
	commands = ai.commands_for_tick(sim.ai_observation(), DT)
	t.check(ai._memory.has(2) and ai._memory[2].target_id == 101, "after 100 abandons, AI 2 re-targets 101")
	t.check(commands.keys() == [2], "re-target tick commands only ship 2")
	return true


## Stickiness through the real commands_for_tick: the target held in memory survives a closer
## enemy until it is nearer than retarget_ratio x the current distance.
func _test_sticky_through_ticks(t) -> bool:
	var sim = _fixture(800.0)
	sim.ships[100]["position"] = Vector2(3600, 2100)  # 600 from AI 2
	sim.ships[101]["position"] = Vector2(2000, 2100)  # 1000
	var ai = AiController.new()
	ai.commands_for_tick(sim.ai_observation(), DT)
	t.check(ai._memory[2].target_id == 100, "sticky ticks: AI 2 first targets 100")
	sim.ships[101]["position"] = Vector2(2490, 2100)  # 510 = 0.85 x 600: closer but not enough
	ai.commands_for_tick(sim.ai_observation(), DT)
	t.check(ai._memory[2].target_id == 100, "sticky ticks: 101 at 0.85 x the distance does not take over")
	sim.ships[101]["position"] = Vector2(2600, 2100)  # 400 < 0.7 x 600
	ai.commands_for_tick(sim.ai_observation(), DT)
	t.check(ai._memory[2].target_id == 101, "sticky ticks: 101 below 0.7 x the distance takes over")
	return true
