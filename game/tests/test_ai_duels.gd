extends RefCounted
## Duel reset checks. Plan 03 task 1: three fixed AI-duel presets x three player vessels.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")

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
