extends RefCounted
## Weapon state, per-gun reload, firing/cycling order and straight-broadside gun spread checks.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")

const DT := 1.0 / 60.0
const EPS := 1e-6
const VESSEL_IDS := ["sloop", "brig", "frigate"]
const SHOOTER := Vector2(2500, 2100)


func run(t) -> bool:
	_test_definitions(t)
	_test_durations(t)
	_test_partial_volley(t)
	_test_partial_volley_all_vessels(t)
	_test_cycle(t)
	_test_both_sides_and_missing(t)
	_test_projectile_id_order(t)
	_test_crew_rate(t)
	_test_gun_offsets(t)
	_test_gun_spread(t)
	_test_no_aim_assist(t)
	_test_fire_replay(t)
	_test_unaimed_fire(t)
	return true


# --- helpers -----------------------------------------------------------------

func _sim(vessel_id := "sloop"):
	var sim = NavalSimulation.new()
	sim.reset("practice", vessel_id)
	return sim


## Shooter id1 (sloop, heading 0) at SHOOTER plus the given extra ship records.
func _sim_with(extra: Array, reverse := false):
	var sim = _sim()
	var list := [sim.ships[1]] + extra
	if reverse:
		list.reverse()
	sim.ships = {}
	for s in list:
		sim.ships[s["id"]] = s
	return sim


func _enemy(id: int, pos: Vector2, vessel_id := "brig", team := 1) -> Dictionary:
	return NavalSimulation.make_ship(id, team, vessel_id, pos, 0.0)


func _loads(sim, id: int, side: String) -> Array:
	return sim.ships[id]["weapons"][side]["loads"]


func _of_type(sim, type: String) -> Array:
	return sim.events.filter(func(e): return e["type"] == type)


func _dur(vessel_id: String, i: int) -> float:
	var v: Dictionary = Definitions.VESSELS[vessel_id]
	return NavalSimulation.reload_duration(i, v["guns_per_side"], v["base_reload"])


func _vec_near(a: Vector2, b: Vector2, eps: float) -> bool:
	return a.distance_to(b) <= eps


# --- definitions / reload math -------------------------------------------------

func _test_definitions(t) -> void:
	var expected := {"round": [900.0, 345.6, 8.0, "hull"], "chain": [600.0, 288.0, 6.0, "sails"], "grape": [300.0, 259.2, 5.0, "crew"]}
	for ammo in expected:
		var a: Dictionary = Definitions.AMMO.get(ammo, {})
		t.check([a.get("range"), a.get("speed"), a.get("damage"), a.get("track")] == expected[ammo], "%s ammo definition" % ammo)
	t.check(Definitions.AMMO_CYCLE == ["round", "chain", "grape"], "ammo cycle order")
	t.near(Definitions.GUN_SPREAD, 0.7, 1e-12, "guns span +/-0.7 radius along the keel")


func _test_durations(t) -> void:
	var expected := [4.55, 5.3666666667, 6.1833333333, 7.0]
	for i in 4:
		t.near(NavalSimulation.reload_duration(i, 4, 7.0), expected[i], 1e-9, "sloop gun %d duration" % i)
	t.near(NavalSimulation.reload_rate(60.0, 60.0), 1.0, 1e-12, "full crew rate 1")
	t.near(NavalSimulation.reload_rate(30.0, 60.0), 0.625, 1e-12, "half crew rate .625")
	t.near(NavalSimulation.reload_rate(0.0, 60.0), 0.25, 1e-12, "rate floor .25 (math only; zero crew disables)")


# --- firing -------------------------------------------------------------------

func _test_partial_volley(t) -> void:
	var sim = _sim()
	sim.ships[1]["weapons"]["port"]["loads"] = [1.0, 0.4, 1.0, 0.8]
	sim.step(DT, {1: {"fire_port": true}})
	var shots := _of_type(sim, "shot")
	t.check(shots.size() == 2 and sim.projectiles.size() == 2, "partial volley: exactly two shots")
	t.check(shots.size() == 2 and shots[0]["gun_index"] == 0 and shots[1]["gun_index"] == 2, "partial volley: guns 0 and 2 fire")
	var port := _loads(sim, 1, "port")
	t.check(port[0] == 0.0 and port[2] == 0.0, "fired guns empty (no reload after firing)")
	t.near(port[1], 0.4 + DT / 5.3666666667, EPS, "unfinished gun 1 keeps progress")
	t.near(port[3], 0.8 + DT / 7.0, EPS, "unfinished gun 3 keeps progress")
	t.check(_loads(sim, 1, "starboard").all(func(l): return l == 1.0), "starboard stays full")
	t.check(_of_type(sim, "fire_rejected").is_empty(), "no rejection when a gun fired")
	sim.step(DT, {1: {"fire_port": true}})
	t.check(_of_type(sim, "shot").is_empty() and sim.projectiles.size() == 2, "second immediate fire: no new shots")
	var rejected := _of_type(sim, "fire_rejected")
	t.check(rejected == [{"type": "fire_rejected", "ship_id": 1, "side": "port", "reason": "no_loaded_guns"}], "second immediate fire: rejection event")
	# Almost-ready guns are not rounded up.
	var almost = _sim()
	almost.ships[1]["weapons"]["port"]["loads"] = [1.0 - 1e-9 - DT / 4.55, 0.0, 0.0, 0.0]
	almost.step(DT, {1: {"fire_port": true}})
	t.check(_of_type(almost, "shot").is_empty() and _loads(almost, 1, "port")[0] < 1.0, "almost-ready gun does not fire")


func _test_partial_volley_all_vessels(t) -> void:
	for vessel_id in VESSEL_IDS:
		for side in ["port", "starboard"]:
			var other: String = "starboard" if side == "port" else "port"
			var sim = _sim(vessel_id)
			var n: int = Definitions.VESSELS[vessel_id]["guns_per_side"]
			var start := []
			for i in n:
				start.append(1.0 if i % 2 == 0 else 0.5)
			sim.ships[1]["weapons"][side]["loads"] = start.duplicate()
			sim.step(DT, {1: {"fire_" + side: true}})
			var fired := _of_type(sim, "shot").map(func(e): return e["gun_index"])
			var ok := true
			for i in n:
				var expected: float = 0.0 if i % 2 == 0 else 0.5 + DT / _dur(vessel_id, i)
				ok = ok and absf(_loads(sim, 1, side)[i] - expected) <= EPS
			t.check(fired == range(0, n, 2), "%s %s: even guns fire" % [vessel_id, side])
			t.check(ok, "%s %s: fired guns empty, others keep progress" % [vessel_id, side])
			t.check(_loads(sim, 1, other).all(func(l): return l == 1.0), "%s %s: %s untouched" % [vessel_id, side, other])


func _test_cycle(t) -> void:
	var sim = _sim()
	sim.ships[1]["weapons"]["starboard"]["loads"] = [0.5, 0.5, 0.5, 0.5]
	sim.step(DT, {1: {"cycle_port": true}})
	t.check(sim.ships[1]["weapons"]["port"]["ammo"] == "chain", "cycle port: round -> chain")
	t.check(sim.ships[1]["weapons"]["starboard"]["ammo"] == "round", "cycle port leaves starboard ammo")
	var ok_port := true
	var ok_star := true
	for i in 4:
		ok_port = ok_port and absf(_loads(sim, 1, "port")[i] - DT / _dur("sloop", i)) <= EPS
		ok_star = ok_star and absf(_loads(sim, 1, "starboard")[i] - (0.5 + DT / _dur("sloop", i))) <= EPS
	t.check(ok_port, "cycle port restarts all port guns, then one tick of reload")
	t.check(ok_star, "starboard only gets normal reload")
	sim.step(DT, {1: {"cycle_port": true}})
	t.check(sim.ships[1]["weapons"]["port"]["ammo"] == "grape", "second cycle -> grape")
	sim.step(DT, {1: {"cycle_port": true}})
	t.check(sim.ships[1]["weapons"]["port"]["ammo"] == "round", "third cycle returns round")

	var both = _sim()
	both.step(DT, {1: {"cycle_starboard": true, "fire_starboard": true}})
	t.check(_of_type(both, "shot").is_empty() and both.projectiles.is_empty(), "cycle+fire: new ammo cannot fire instantly")
	t.check(_of_type(both, "fire_rejected").size() == 1, "cycle+fire: rejection feedback")
	t.near(_loads(both, 1, "starboard")[0], DT / 4.55, EPS, "cycle+fire: side accrues only this tick's reload")
	t.check(_loads(both, 1, "port").all(func(l): return l == 1.0), "cycle+fire starboard leaves port loaded")


func _test_both_sides_and_missing(t) -> void:
	var sim = _sim("brig")
	sim.step(DT, {})
	t.check(sim.projectiles.is_empty() and sim.events.is_empty(), "missing commands fire nothing")
	sim.step(DT, {1: {"fire_port": true, "fire_starboard": false, "cycle_port": false}})
	t.check(sim.projectiles.size() == 6 and _loads(sim, 1, "starboard").all(func(l): return l == 1.0), "false flags are neutral")
	var both = _sim("brig")
	both.step(DT, {1: {"fire_port": true, "fire_starboard": true}})
	var sides := _of_type(both, "shot").map(func(e): return e["side"])
	t.check(sides == ["port", "port", "port", "port", "port", "port", "starboard", "starboard", "starboard", "starboard", "starboard", "starboard"], "both sides fire together, port first")
	var dirs := _of_type(both, "shot").map(func(e): return e["direction"])
	t.check(_vec_near(dirs[0], Vector2(0, -1), 1e-6) and _vec_near(dirs[11], Vector2(0, 1), 1e-6), "port fires north, starboard south at heading 0")


func _test_projectile_id_order(t) -> void:
	for reverse in [false, true]:
		var sim = _sim_with([_enemy(2, Vector2(1000, 1000), "brig")], reverse)
		sim.step(DT, {2: {"fire_starboard": true, "fire_port": true}, 1: {"fire_port": true, "fire_starboard": true}})
		var shots := _of_type(sim, "shot")
		var ok := shots.size() == 20
		for k in shots.size():
			var e: Dictionary = shots[k]
			var expected_owner := 1 if k < 8 else 2
			var n := 4 if k < 8 else 6
			var local := k if k < 8 else k - 8
			ok = ok and e["projectile_id"] == k + 1 and e["ship_id"] == expected_owner \
				and e["side"] == ("port" if local < n else "starboard") and e["gun_index"] == local % n
			ok = ok and sim.projectiles[k]["id"] == k + 1 and sim.projectiles[k]["owner_id"] == expected_owner
		t.check(ok, "projectile IDs by ship ID, port then starboard, gun index (reverse=%s)" % reverse)
		t.check(sim.next_projectile_id == 21, "projectile counter advanced (reverse=%s)" % reverse)


func _test_crew_rate(t) -> void:
	for crew in [60.0, 30.0]:
		var sim = _sim()
		sim.ships[1]["crew"] = crew
		sim.step(DT, {1: {"fire_port": true}})
		sim.step(DT, {})
		var rate := 1.0 if crew == 60.0 else 0.625
		t.near(_loads(sim, 1, "port")[0], DT * rate / 4.55, EPS, "gun 0 next tick after firing, crew %s" % crew)


# --- straight broadsides (no aim assist) ------------------------------------------

func _test_gun_offsets(t) -> void:
	t.near(NavalSimulation.gun_offset(0, 4, 27.5), 19.25, 1e-9, "sloop gun 0 sits 0.7r toward the bow")
	t.near(NavalSimulation.gun_offset(1, 4, 27.5), 19.25 / 3.0, 1e-9, "sloop gun 1 evenly spaced")
	t.near(NavalSimulation.gun_offset(2, 4, 27.5), -19.25 / 3.0, 1e-9, "sloop gun 2 evenly spaced")
	t.near(NavalSimulation.gun_offset(3, 4, 27.5), -19.25, 1e-9, "sloop gun 3 sits 0.7r toward the stern")
	t.near(NavalSimulation.gun_offset(7, 8, 42.5), -29.75, 1e-9, "frigate last gun at -0.7r")


## Every loaded gun fires from its own place along the keel, straight off the beam.
func _test_gun_spread(t) -> void:
	for vessel_id in VESSEL_IDS:
		var vessel: Dictionary = Definitions.VESSELS[vessel_id]
		var n: int = vessel["guns_per_side"]
		for heading in [0.0, 0.7, -2.5]:
			for side in ["port", "starboard"]:
				var sim = _sim(vessel_id)
				sim.ships = {1: sim.ships[1]}
				sim.ships[1]["heading"] = heading
				sim.step(DT, {1: {"fire_" + side: true}})
				var center: Vector2 = sim.ships[1]["position"]  # fire uses the post-movement center
				var fired_heading: float = sim.ships[1]["heading"]  # wrap_angle may move the last bit
				var keel := Vector2.from_angle(fired_heading)
				var beam := Vector2.from_angle(fired_heading + (-PI / 2.0 if side == "port" else PI / 2.0))
				var shots := _of_type(sim, "shot")
				var ok: bool = shots.size() == n and sim.projectiles.size() == n
				for k in shots.size():
					var offset: Vector2 = shots[k]["position"] - center
					ok = ok and absf(offset.dot(keel) - NavalSimulation.gun_offset(k, n, vessel["radius"])) <= 1e-3
					ok = ok and absf(offset.dot(beam)) <= 1e-3
					ok = ok and shots[k]["direction"] == beam and sim.projectiles[k]["direction"] == beam
				var label := "%s heading %s %s" % [vessel_id, heading, side]
				t.check(ok, "%s: %d shots spread bow to stern, all straight off the beam" % [label, n])
	var partial = _sim()
	partial.ships[1]["weapons"]["port"]["loads"] = [1.0, 0.4, 1.0, 0.8]
	partial.step(DT, {1: {"fire_port": true}})
	var center: Vector2 = partial.ships[1]["position"]
	var shots := _of_type(partial, "shot")
	t.check(shots.size() == 2 and absf(shots[0]["position"].x - center.x - 19.25) <= 1e-3
		and absf(shots[1]["position"].x - center.x + 19.25 / 3.0) <= 1e-3,
		"partial volley: guns 0 and 2 fire from their own places")


func _test_no_aim_assist(t) -> void:
	var port := -PI / 2.0
	for degrees in [0.0, 8.0, -8.0]:
		var sim = _sim_with([_enemy(2, SHOOTER + Vector2.from_angle(port + deg_to_rad(degrees)) * 400.0)])
		sim.step(DT, {1: {"fire_port": true}})
		t.check(sim.projectiles.size() == 4 and sim.projectiles.all(func(p): return p["direction"] == Vector2.from_angle(port)),
			"enemy %s degrees off the beam does not bend any shot" % degrees)


func _test_fire_replay(t) -> void:
	var tape := []
	for i in 240:
		tape.append({1: {"turn": sin(i * 0.05), "fire_port": i % 50 == 0, "fire_starboard": i % 70 == 5}})
	var runs := []
	for run in 2:
		var sim = _sim("frigate")
		for command in tape:
			sim.step(DT, command)
		runs.append([sim.projectiles.duplicate(true), sim.ships.duplicate(true), sim.next_projectile_id])
	t.check(runs[0] == runs[1] and runs[0][2] > 1, "identical fire tapes give identical projectiles and ships")


func _test_unaimed_fire(t) -> void:
	var sim = _sim_with([_enemy(2, Vector2(3000, 2100))])
	sim.step(DT, {1: {"fire_starboard": true}})
	t.check(sim.projectiles.size() == 4 and _loads(sim, 1, "starboard").all(func(l): return l == 0.0), "ready fire without target consumes guns")
	t.check(sim.projectiles.all(func(p): return _vec_near(p["direction"], Vector2(0, 1), 1e-6)), "unaimed shots fly perpendicular")
