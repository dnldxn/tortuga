extends RefCounted

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")

const DT := 1.0 / 60.0

const EXPECTED_VESSELS := {
	"sloop": {"full_speed": 162.0, "turn_rate": 1.2, "hull": 100.0, "sails": 70.0, "crew": 60.0, "guns_per_side": 4, "base_reload": 7.0, "radius": 22.0},
	"brig": {"full_speed": 130.5, "turn_rate": 0.85, "hull": 160.0, "sails": 100.0, "crew": 90.0, "guns_per_side": 6, "base_reload": 8.0, "radius": 28.0},
	"frigate": {"full_speed": 99.0, "turn_rate": 0.6, "hull": 240.0, "sails": 140.0, "crew": 140.0, "guns_per_side": 8, "base_reload": 9.0, "radius": 34.0},
}


func run(t) -> bool:
	_test_definitions(t)
	_test_vessel_resets(t)
	_test_reset_is_repeatable(t)
	_test_invalid_ids_keep_state(t)
	_test_deep_copies(t)
	_test_step_clears_events_and_advances_time(t)
	_test_wind_multiplier(t)
	_test_speed_fixtures(t)
	_test_sail_fractions(t)
	_test_turning(t)
	_test_wrap(t)
	_test_commands(t)
	_test_toggle(t)
	_test_neutral_movement(t)
	_test_vessel_ordering(t)
	_test_damage_keeps_handling(t)
	_test_upwind_recovery(t)
	_test_inactive_and_keyed_commands(t)
	_test_determinism(t)
	return true


func _snapshot(sim) -> Dictionary:
	return {
		"ships": sim.ships.duplicate(true),
		"projectiles": sim.projectiles.duplicate(true),
		"events": sim.events.duplicate(true),
		"elapsed": sim.elapsed,
		"preset_id": sim.preset_id,
		"selected_vessel_id": sim.selected_vessel_id,
		"wind_heading": sim.wind_heading,
		"result": sim.result.duplicate(true),
	}


func _dirty(sim) -> void:
	sim.ships[1]["position"] = Vector2(1, 1)
	sim.ships[1]["hull"] = 1.0
	sim.ships[7] = {"id": 7, "team": 1}
	sim.projectiles.append({"stale": true})
	sim.events.append({"stale": true})
	sim.result["winner"] = 0
	sim.elapsed = 99.0


func _test_definitions(t) -> void:
	for vessel_id in EXPECTED_VESSELS:
		var def: Dictionary = Definitions.VESSELS.get(vessel_id, {})
		for key in EXPECTED_VESSELS[vessel_id]:
			t.check(def.get(key) == EXPECTED_VESSELS[vessel_id][key], "%s.%s definition" % [vessel_id, key])
		t.check(def.get("display_name", "") != "", "%s has display_name" % vessel_id)
	t.check(Definitions.VESSELS["sloop"]["description"] == "Fastest, tightest turns, light protection", "sloop description")
	t.check(Definitions.VESSELS["brig"]["description"] == "Balanced handling and protection", "brig description")
	t.check(Definitions.VESSELS["frigate"]["description"] == "Slow, wide turns, heavy protection", "frigate description")
	t.check(Definitions.ARENA_SIZE == Vector2(6000, 4200), "arena size")
	var bounds: Rect2 = Definitions.safe_bounds(22.0)
	t.check(bounds.position == Vector2(182, 182) and bounds.end == Vector2(5818, 4018), "safe bounds for radius 22")


func _test_vessel_resets(t) -> void:
	for vessel_id in EXPECTED_VESSELS:
		var def: Dictionary = EXPECTED_VESSELS[vessel_id]
		var sim = NavalSimulation.new()
		sim.reset("practice", vessel_id)
		t.check(sim.preset_id == "practice", "%s preset_id" % vessel_id)
		t.check(sim.selected_vessel_id == vessel_id, "%s selected_vessel_id" % vessel_id)
		t.check(sim.ships.keys() == [1, 2], "%s player ship (id 1) plus practice target (id 2)" % vessel_id)
		var ship: Dictionary = sim.ships.get(1, {})
		t.check(ship.get("id") == 1 and ship.get("team") == 0, "%s player id/team" % vessel_id)
		t.check(ship.get("vessel_id") == vessel_id, "%s ship vessel_id" % vessel_id)
		t.check(ship.get("position") == Vector2(2500, 2100), "%s spawn position" % vessel_id)
		t.check(Definitions.safe_bounds(def["radius"]).has_point(ship.get("position", Vector2.ZERO)), "%s spawn inside safe bounds" % vessel_id)
		t.check(ship.get("heading") == 0.0 and ship.get("speed") == 0.0, "%s heading 0, speed 0" % vessel_id)
		t.check(ship.get("reefed") == false and ship.get("active") == true, "%s full sails, active" % vessel_id)
		t.check(ship.get("hull") == def["hull"] and ship.get("sails") == def["sails"] and ship.get("crew") == def["crew"], "%s full tracks" % vessel_id)
		t.check(sim.wind_heading == 0.0, "%s wind heading east" % vessel_id)
		t.check(sim.elapsed == 0.0 and sim.projectiles.is_empty() and sim.events.is_empty() and sim.result.is_empty(), "%s empty transients" % vessel_id)


func _test_reset_is_repeatable(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("practice", "brig")
	var first := _snapshot(sim)
	_dirty(sim)
	sim.reset("practice", "brig")
	t.check(_snapshot(sim) == first, "dirty reset matches initial state")
	_dirty(sim)
	sim.reset("practice", "brig")
	t.check(_snapshot(sim) == first, "second dirty reset matches initial state")
	t.check(sim.projectiles.is_empty() and sim.events.is_empty() and sim.result.is_empty(), "stale projectile/event/result removed")


func _test_invalid_ids_keep_state(t) -> void:
	print("  (expected ERROR lines follow: invalid-ID rejection test)")
	var sim = NavalSimulation.new()
	sim.reset("practice", "sloop")
	_dirty(sim)
	var before := _snapshot(sim)
	sim.reset("no_such_preset", "brig")
	t.check(_snapshot(sim) == before, "invalid preset rejected, state intact")
	sim.reset("practice", "no_such_vessel")
	t.check(_snapshot(sim) == before, "invalid vessel rejected, state intact")


func _test_deep_copies(t) -> void:
	var a = NavalSimulation.new()
	var b = NavalSimulation.new()
	a.reset("practice", "sloop")
	b.reset("practice", "sloop")
	a.ships[1]["hull"] = 0.0
	a.ships[1]["position"] = Vector2(9, 9)
	a.projectiles.append({"x": 1})
	t.check(b.ships[1]["hull"] == 100.0 and b.ships[1]["position"] == Vector2(2500, 2100), "other simulation unaffected")
	t.check(b.projectiles.is_empty(), "other simulation projectiles unaffected")
	t.check(Definitions.VESSELS["sloop"]["hull"] == 100.0, "definitions unaffected")
	a.reset("practice", "sloop")
	t.check(a.ships[1]["hull"] == 100.0, "reset after mutation restores full hull")


func _test_step_clears_events_and_advances_time(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("practice", "sloop")
	sim.events.append({"stale": true})
	sim.step(DT, {})
	t.check(sim.events.is_empty(), "step clears previous events")
	t.check(sim.elapsed == DT, "step advances elapsed once")
	sim.step(DT, {})
	t.near(sim.elapsed, 2.0 * DT, 1e-12, "two steps advance elapsed twice")


func _sim(vessel_id := "sloop", heading := 0.0) -> Object:
	var sim = NavalSimulation.new()
	sim.reset("practice", vessel_id)
	sim.ships[1]["heading"] = heading
	return sim


func _tick(sim, commands := {}) -> Dictionary:
	sim.step(DT, commands)
	return sim.ships[1]


func _test_wind_multiplier(t) -> void:
	var knots := {0.0: 0.8, 45.0: 1.0, 90.0: 0.95, 135.0: 0.45, 180.0: 0.12, 22.5: 0.9, 157.5: 0.285}
	for deg in knots:
		t.near(Definitions.wind_multiplier(deg_to_rad(deg), 0.0), knots[deg], 1e-4, "wind multiplier %s deg" % deg)
		t.near(Definitions.wind_multiplier(-deg_to_rad(deg), 0.0), knots[deg], 1e-4, "wind multiplier -%s deg" % deg)
	t.near(Definitions.wind_multiplier(PI / 2.0 + 1.0, 1.0), 0.95, 1e-4, "wind multiplier relative to wind heading")
	t.near(Definitions.wind_multiplier(TAU + deg_to_rad(45.0), 0.0), 1.0, 1e-4, "wind multiplier wraps heading")


func _test_speed_fixtures(t) -> void:
	var cases := {0.0: 129.6, 45.0: 162.0, 90.0: 153.9, 180.0: 19.44}
	for deg in cases:
		t.near(_tick(_sim("sloop", deg_to_rad(deg)))["speed"], cases[deg], 1e-4, "sloop speed at %s deg" % deg)
	t.near(_tick(_sim(), {1: {"toggle_sails": true}})["speed"], 84.24, 1e-4, "sloop reefed downwind speed")


func _test_sail_fractions(t) -> void:
	var cases := {70.0: 129.6, 35.0: 84.24, 7.0: 47.952, 0.0: 0.0}
	for sails in cases:
		var sim = _sim()
		sim.ships[1]["sails"] = sails
		t.near(_tick(sim)["speed"], cases[sails], 1e-4, "sloop speed with %s sails" % sails)
	var over = _sim()
	over.ships[1]["sails"] = 140.0
	t.near(_tick(over)["speed"], 129.6, 1e-4, "sail fraction clamps above 1")


func _test_turning(t) -> void:
	t.near(_tick(_sim(), {1: {"turn": 1.0}})["heading"], 0.02, 1e-6, "one right tick turns +0.02")
	t.near(_tick(_sim(), {1: {"turn": -1.0}})["heading"], -0.02, 1e-6, "one left tick turns -0.02")
	var reefed = _sim()
	reefed.ships[1]["reefed"] = true
	t.near(_tick(reefed, {1: {"turn": 1.0}})["heading"], 0.028, 1e-6, "one reefed right tick turns +0.028")
	var right = _sim()
	var left = _sim()
	for i in 45:
		_tick(right, {1: {"turn": 1.0}})
		_tick(left, {1: {"turn": -1.0}})
	t.near(right.ships[1]["heading"], -left.ships[1]["heading"], 1e-9, "left/right heading symmetry")
	var rp: Vector2 = right.ships[1]["position"] - Vector2(2500, 2100)
	var lp: Vector2 = left.ships[1]["position"] - Vector2(2500, 2100)
	t.near(rp.x, lp.x, 0.02, "left/right x symmetry")
	t.near(rp.y, -lp.y, 0.02, "left/right y mirrored")
	t.check(rp.y > 0.0, "right turn moves toward +y (clockwise)")


func _test_wrap(t) -> void:
	var h: float = _tick(_sim("sloop", PI - 0.01), {1: {"turn": 1.0}})["heading"]
	t.near(h, -PI + 0.01, 1e-6, "wrap past +PI")
	t.check(h >= -PI and h < PI, "wrapped heading in [-PI, PI)")
	h = _tick(_sim("sloop", -PI + 0.01), {1: {"turn": -1.0}})["heading"]
	t.near(h, PI - 0.01, 1e-6, "wrap past -PI")
	t.check(h >= -PI and h < PI, "wrapped heading in [-PI, PI) (left)")
	h = _tick(_sim("sloop", PI))["heading"]
	t.check(h >= -PI and h < PI, "heading PI wraps into [-PI, PI)")


func _test_commands(t) -> void:
	var s: Dictionary = _tick(_sim(), {})
	t.check(s["heading"] == 0.0 and not s["reefed"], "missing commands are neutral")
	s = _tick(_sim(), {1: {}})
	t.check(s["heading"] == 0.0 and not s["reefed"], "empty command is neutral")
	s = _tick(_sim(), {1: {"fire_port": true, "fire_starboard": true, "cycle_port": true, "cycle_starboard": true}})
	t.check(s["heading"] == 0.0 and not s["reefed"], "fire/cycle actions do not affect sailing")
	t.near(_tick(_sim(), {1: {"turn": 5.0}})["heading"], 0.02, 1e-6, "turn clamped to +1")
	t.near(_tick(_sim(), {1: {"turn": -5.0}})["heading"], -0.02, 1e-6, "turn clamped to -1")
	t.near(_tick(_sim(), {1: {"turn": 0.5}})["heading"], 0.01, 1e-6, "partial turn scales rate")


func _test_toggle(t) -> void:
	var sim = _sim()
	_tick(sim, {1: {"toggle_sails": true}})
	for i in 59:
		_tick(sim)
	t.check(sim.ships[1]["reefed"] == true, "toggle once then 59 neutral ticks stays reefed")
	t.near(sim.ships[1]["speed"], 84.24, 1e-4, "reefed speed persists")
	_tick(sim, {1: {"toggle_sails": true}})
	t.check(sim.ships[1]["reefed"] == false, "second toggle restores full sails")
	t.near(sim.ships[1]["speed"], 129.6, 1e-4, "full sails speed restored")


func _test_neutral_movement(t) -> void:
	var sim = _sim()
	for i in 60:
		_tick(sim)
	var p: Vector2 = sim.ships[1]["position"]
	t.near(p.x, 2500.0 + 129.6, 0.02, "60 neutral ticks move +129.6 x")
	t.near(p.y, 2100.0, 0.02, "60 neutral ticks keep y")


func _test_vessel_ordering(t) -> void:
	var speed := {}
	var turn := {}
	for id in ["sloop", "brig", "frigate"]:
		speed[id] = _tick(_sim(id))["speed"]
		turn[id] = _tick(_sim(id), {1: {"turn": 1.0}})["heading"]
	t.check(speed["sloop"] > speed["brig"] and speed["brig"] > speed["frigate"], "speed order sloop > brig > frigate")
	t.check(turn["sloop"] > turn["brig"] and turn["brig"] > turn["frigate"], "turn order sloop > brig > frigate")


func _test_damage_keeps_handling(t) -> void:
	var full = _sim()
	var hurt = _sim()
	hurt.ships[1]["hull"] = 50.0
	hurt.ships[1]["crew"] = 30.0
	for i in 30:
		_tick(full, {1: {"turn": 1.0}})
		_tick(hurt, {1: {"turn": 1.0}})
	t.check(full.ships[1]["heading"] == hurt.ships[1]["heading"], "half hull/crew keeps turn")
	t.check(full.ships[1]["speed"] == hurt.ships[1]["speed"], "half hull/crew keeps speed")
	t.check(full.ships[1]["position"] == hurt.ships[1]["position"], "half hull/crew keeps position")


func _test_upwind_recovery(t) -> void:
	var sim = _sim("sloop", PI)
	t.near(_tick(sim)["speed"], 19.44, 1e-4, "directly upwind speed")
	for i in 90:
		_tick(sim, {1: {"turn": 1.0}})
	t.near(sim.ships[1]["heading"], -PI + 90.0 * 0.02, 1e-6, "upwind steering keeps full rate")
	t.check(sim.ships[1]["speed"] > 100.0, "speed recovers after turning off the wind")


func _test_inactive_and_keyed_commands(t) -> void:
	var sim = _sim()
	var other: Dictionary = sim.ships[1].duplicate(true)
	other["id"] = 2
	other["position"] = Vector2(1000, 1000)
	sim.ships[2] = other
	sim.step(DT, {2: {"turn": 1.0}})
	t.near(sim.ships[1]["heading"], 0.0, 1e-9, "ship 1 ignores ship 2 command")
	t.near(sim.ships[2]["heading"], 0.02, 1e-6, "ship 2 command applied by id")
	sim.ships[2]["active"] = false
	var pos: Vector2 = sim.ships[2]["position"]
	var head: float = sim.ships[2]["heading"]
	sim.step(DT, {2: {"turn": 1.0, "toggle_sails": true}})
	t.check(sim.ships[2]["position"] == pos and sim.ships[2]["heading"] == head and not sim.ships[2]["reefed"], "inactive ship does not act")


func _test_determinism(t) -> void:
	var a = _sim()
	var b = _sim()
	for i in 600:
		var cmd := {1: {"turn": sin(i * 0.05) * 1.5, "toggle_sails": i % 150 == 0}}
		a.step(DT, cmd)
		b.step(DT, cmd.duplicate(true))
	t.check(_snapshot(a) == _snapshot(b), "identical 600-tick commands give identical state")
