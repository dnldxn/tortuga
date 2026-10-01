extends RefCounted
## Practice initialization/reset checks. Plan 02 task 5 extends this with the practice target.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")

const DT := 1.0 / 60.0
const GUNS := {"sloop": 4, "brig": 6, "frigate": 8}


func run(t) -> bool:
	_test_initial_weapons(t)
	_test_independent_arrays(t)
	_test_target_preset(t)
	_test_target_stationary(t)
	_test_target_ignores_commands(t)
	for vessel_id in GUNS:
		_test_bump(t, vessel_id)
	_test_target_defeat_keeps_practice(t)
	for vessel_id in GUNS:
		_test_exact_reset(t, vessel_id)
	return true


func _fresh(vessel_id: String) -> Dictionary:
	var sim = NavalSimulation.new()
	sim.reset("practice", vessel_id)
	return _snapshot(sim)


func _of_type(sim, type: String) -> Array:
	return sim.events.filter(func(e): return e["type"] == type)


## A test-only round shot record already overlapping the target's circle (hits next step).
func _shot_at(sim, owner_id: int, victim_id: int) -> void:
	var at: Vector2 = sim.ships[victim_id]["position"] - Vector2(0, 10)
	sim.projectiles.append({"id": sim.next_projectile_id, "owner_id": owner_id, "ammo": "round",
		"position": at, "direction": Vector2.DOWN, "remaining_range": 900.0, "owner_cleared": true})
	sim.next_projectile_id += 1


func _snapshot(sim) -> Dictionary:
	return {
		"ships": sim.ships.duplicate(true), "projectiles": sim.projectiles.duplicate(true),
		"events": sim.events.duplicate(true), "elapsed": sim.elapsed, "result": sim.result.duplicate(true),
		"next_projectile_id": sim.next_projectile_id, "preset_id": sim.preset_id,
		"selected_vessel_id": sim.selected_vessel_id, "wind_heading": sim.wind_heading,
	}


func _test_initial_weapons(t) -> void:
	for vessel_id in GUNS:
		var sim = NavalSimulation.new()
		sim.reset("practice", vessel_id)
		var ship: Dictionary = sim.ships[1]
		t.check(ship.get("role") == "ship" and ship.get("defeat_reasons") == [], "%s role ship, no defeat reasons" % vessel_id)
		t.check(sim.next_projectile_id == 1, "%s projectile counter starts at 1" % vessel_id)
		for side in ["port", "starboard"]:
			var weapon: Dictionary = ship.get("weapons", {}).get(side, {})
			var loads: Array = weapon.get("loads", [])
			t.check(weapon.get("ammo") == "round", "%s %s starts round" % [vessel_id, side])
			t.check(loads.size() == GUNS[vessel_id] and loads.all(func(l): return l == 1.0), "%s %s has %d loaded guns" % [vessel_id, side, GUNS[vessel_id]])


func _test_independent_arrays(t) -> void:
	var a = NavalSimulation.new()
	var b = NavalSimulation.new()
	a.reset("practice", "brig")
	b.reset("practice", "brig")
	a.ships[1]["weapons"]["port"]["loads"][2] = 0.3
	t.check(a.ships[1]["weapons"]["starboard"]["loads"][2] == 1.0, "port load change leaves starboard")
	t.check(a.ships[2]["weapons"]["port"]["loads"][2] == 1.0, "port load change leaves other ship")
	t.check(b.ships[1]["weapons"]["port"]["loads"][2] == 1.0, "port load change leaves other simulation")
	a.ships[1]["defeat_reasons"].append("x")
	t.check(a.ships[2]["defeat_reasons"].is_empty(), "defeat_reasons not shared between ships")
	a.reset("practice", "brig")
	t.check(a.ships[1]["weapons"]["port"]["loads"][2] == 1.0 and a.ships[1]["defeat_reasons"].is_empty(), "reset allocates fresh arrays")


func _test_target_preset(t) -> void:
	for vessel_id in GUNS:
		var sim = NavalSimulation.new()
		sim.reset("practice", vessel_id)
		var target: Dictionary = sim.ships.get(2, {})
		t.check(sim.ships.keys() == [1, 2], "%s practice has player 1 and target 2" % vessel_id)
		t.check(target.get("team") == 1 and target.get("role") == "practice_target" and target.get("vessel_id") == "brig",
			"%s target is team-1 brig with role practice_target" % vessel_id)
		t.check(target.get("position") == Vector2(3000, 2100) and target.get("heading") == 0.0 and target.get("speed") == 0.0,
			"%s target at (3000,2100) heading 0, still" % vessel_id)
		t.check(target.get("active") == true and target.get("reefed") == false and target.get("defeat_reasons") == [],
			"%s target active, full sails, undefeated" % vessel_id)
		t.check([target.get("hull"), target.get("sails"), target.get("crew")] == [160.0, 100.0, 90.0], "%s target full tracks" % vessel_id)
		for side in ["port", "starboard"]:
			var weapon: Dictionary = target.get("weapons", {}).get(side, {})
			t.check(weapon.get("ammo") == "round" and weapon.get("loads") == [1.0, 1.0, 1.0, 1.0, 1.0, 1.0], "%s target %s loaded round" % [vessel_id, side])
			t.check(sim.aim_for(1, side)["reason"] == "outside_arc", "%s initial target due east is outside the %s arc" % [vessel_id, side])
		t.check(sim.ships[1]["position"] == Vector2(2500, 2100) and sim.ships[1]["heading"] == 0.0 and sim.ships[1]["role"] == "ship",
			"%s player unchanged at (2500,2100) heading 0" % vessel_id)


func _test_target_stationary(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("practice", "sloop")
	for i in 120:  # player sails east but does not reach the target in 2 s
		sim.step(DT, {})
		var target: Dictionary = sim.ships[2]
		if target["position"] != Vector2(3000, 2100) or target["heading"] != 0.0 or target["speed"] != 0.0:
			t.check(false, "target moved on neutral tick %d" % i)
			return
	t.check(true, "120 neutral ticks leave target position/heading/speed fixed")


func _test_target_ignores_commands(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("practice", "sloop")
	var before: Dictionary = sim.ships[2].duplicate(true)
	var own_events := 0
	for i in 60:
		sim.step(DT, {2: {"turn": 1.0, "toggle_sails": i % 2 == 0, "fire_port": true, "fire_starboard": true,
			"cycle_port": i == 10, "cycle_starboard": i == 20}})
		own_events += sim.events.filter(func(e): return e.get("ship_id") == 2).size()
	t.check(sim.ships[2] == before, "injected commands leave the target unchanged (no sail/turn/cycle/fire)")
	t.check(own_events == 0 and sim.projectiles.is_empty() and sim.next_projectile_id == 1, "target never fires or emits rejection feedback")


## Player sails east into the target, pushes it via the ordinary solver, then turns away free.
func _test_bump(t, vessel_id: String) -> void:
	var sim = NavalSimulation.new()
	sim.reset("practice", vessel_id)
	var sum_r: float = Definitions.VESSELS[vessel_id]["radius"] + Definitions.VESSELS["brig"]["radius"]
	var ticks := 0
	while ticks < 600 and sim.ships[1]["position"].distance_to(sim.ships[2]["position"]) > sum_r + 0.5:
		sim.step(DT, {})
		ticks += 1
	t.check(ticks < 600, "%s reaches the target" % vessel_id)
	var worst := 0.0
	for i in 60:  # keep pushing
		sim.step(DT, {})
		worst = maxf(worst, sum_r - sim.ships[1]["position"].distance_to(sim.ships[2]["position"]))
	var target: Dictionary = sim.ships[2]
	t.check(worst <= NavalSimulation.CONTACT_TOLERANCE, "%s bump leaves no overlap (worst %s)" % [vessel_id, worst])
	t.check(target["position"].x > 3000.0 and target["heading"] == 0.0 and target["speed"] == 0.0,
		"%s bump displaces target east without steering it" % vessel_id)
	var full := [Definitions.VESSELS[vessel_id]["hull"], Definitions.VESSELS[vessel_id]["sails"], Definitions.VESSELS[vessel_id]["crew"]]
	t.check([sim.ships[1]["hull"], sim.ships[1]["sails"], sim.ships[1]["crew"]] == full
		and [target["hull"], target["sails"], target["crew"]] == [160.0, 100.0, 90.0], "%s bump deals no damage" % vessel_id)
	t.check(sim.ships[1]["active"] and target["active"], "%s bump keeps both active" % vessel_id)
	for i in 180:
		sim.step(DT, {1: {"turn": 1.0}})
	var parked: Vector2 = sim.ships[2]["position"]
	for i in 120:
		sim.step(DT, {})
	var gap: float = sim.ships[1]["position"].distance_to(sim.ships[2]["position"]) - sum_r
	t.check(gap > 50.0, "%s turns away and separates, not trapped (gap %s)" % [vessel_id, gap])
	t.check(sim.ships[2]["position"] == parked and sim.ships[2]["heading"] == 0.0, "%s target stays where it was pushed" % vessel_id)


func _test_target_defeat_keeps_practice(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("practice", "sloop")
	sim.ships[2]["hull"] = 3.0
	_shot_at(sim, 1, 2)
	sim.step(DT, {})
	var target: Dictionary = sim.ships[2]
	t.check(not target["active"] and target["defeat_reasons"] == ["sunk"], "target sunk")
	t.check(sim.result.is_empty(), "target defeat produces no result")
	var heading: float = sim.ships[1]["heading"]
	sim.step(DT, {1: {"turn": 1.0}})
	t.check(sim.ships[1]["heading"] > heading, "player still controllable after target defeat")
	sim.ships[1]["heading"] = 0.0
	for i in 400:  # sail due east straight through the wreck's circle
		sim.step(DT, {})
	var p: Vector2 = sim.ships[1]["position"]
	t.check(p.x > 3000.0 + 50.0 and absf(p.y - 2100.0) < 1.0, "player sails through the inactive target (at %s)" % p)
	t.check(target["position"] == Vector2(3000, 2100) and sim.result.is_empty(), "wreck not pushed; practice stays open")


## Real gameplay dirt (damage, partial reload, ammo change, reef, target defeat, shots in
## flight), then reset must equal a freshly reset sim exactly; repeated three times.
func _test_exact_reset(t, vessel_id: String) -> void:
	var fresh := _fresh(vessel_id)
	var sim = NavalSimulation.new()
	sim.reset("practice", vessel_id)
	for round_i in 3:
		sim.ships[2]["hull"] = 3.0
		_shot_at(sim, 1, 2)
		for i in 30:
			sim.step(DT, {1: {"turn": 0.5, "toggle_sails": i == 2, "fire_port": i == 0, "fire_starboard": i == 1, "cycle_starboard": i == 5}})
		sim.ships[1]["hull"] -= 10.0
		var player: Dictionary = sim.ships[1]
		var dirty: bool = not sim.ships[2]["active"] and sim.ships[2]["defeat_reasons"] == ["sunk"] \
			and not sim.projectiles.is_empty() and sim.next_projectile_id > 1 and player["reefed"] \
			and player["weapons"]["starboard"]["ammo"] == "chain" \
			and player["weapons"]["port"]["loads"].any(func(l): return l > 0.0 and l < 1.0) and sim.elapsed > 0.0
		t.check(dirty, "%s round %d: dirty state reached" % [vessel_id, round_i])
		sim.reset("practice", vessel_id)
		t.check(_snapshot(sim) == fresh, "%s round %d: reset equals a freshly reset sim" % [vessel_id, round_i])
	sim.step(DT, {1: {"fire_port": true}})
	t.check(sim.projectiles.size() > 0 and sim.projectiles[0]["id"] == 1, "%s projectile IDs restart at 1 after reset" % vessel_id)
