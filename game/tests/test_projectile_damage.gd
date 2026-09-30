extends RefCounted
## Swept projectile geometry, blocking/friendly fire, travel, damage and ship defeat.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")

const DT := 1.0 / 60.0


func run(t) -> bool:
	_test_segment_geometry(t)
	_test_nearest_contact_and_ties(t)
	_test_range_endpoint(t)
	_test_travel(t)
	_test_owner_clearance(t)
	_test_muzzle_and_owner_hits(t)
	_test_friendly_fire(t)
	_test_fixed_direction_and_miss(t)
	_test_track_damage(t)
	_test_clamp_and_reasons(t)
	_test_simultaneous_defeat(t)
	_test_lethal_hit_keeps_blocking(t)
	_test_damage_effects(t)
	_test_defeated_inert(t)
	_test_event_copies(t)
	return true


# --- helpers -----------------------------------------------------------------

func _ship(id: int, team: int, vessel_id: String, pos: Vector2, heading := 0.0) -> Dictionary:
	return NavalSimulation.make_ship(id, team, vessel_id, pos, heading)


func _sim_with(list: Array, reverse := false):
	var sim = NavalSimulation.new()
	sim.reset("practice", "sloop")
	sim.ships = {}
	var order := list.duplicate(true)
	if reverse:
		order.reverse()
	for s in order:
		sim.ships[s["id"]] = s
	return sim


func _shot(sim, owner_id: int, ammo: String, pos: Vector2, dir: Vector2, cleared := true, remaining := -1.0) -> Dictionary:
	var shot := {"id": sim.next_projectile_id, "owner_id": owner_id, "ammo": ammo, "position": pos,
		"direction": dir, "remaining_range": Definitions.AMMO[ammo]["range"] if remaining < 0.0 else remaining,
		"owner_cleared": cleared}
	sim.next_projectile_id += 1
	sim.projectiles.append(shot)
	return shot


func _of_type(sim, type: String) -> Array:
	return sim.events.filter(func(e): return e["type"] == type)


func _tracks(ship: Dictionary) -> Array:
	return [ship["hull"], ship["sails"], ship["crew"]]


## Runs neutral-or-given-command ticks until a hit occurs (max n); returns hit events.
func _run_until_hit(sim, n: int, commands := {}) -> Array:
	for i in n:
		sim.step(DT, commands if i == 0 else {})
		var hits := _of_type(sim, "hit")
		if not hits.is_empty():
			return hits
	return []


# --- geometry -------------------------------------------------------------------

func _test_segment_geometry(t) -> void:
	var a := Vector2(0, 0)
	var b := Vector2(100, 0)
	t.near(NavalSimulation.segment_circle(a, b, Vector2(60, 0), 10.0), 0.5, 1e-9, "circle (60,0) r10 hit at t=.5")
	t.near(NavalSimulation.segment_circle(a, b, Vector2(80, 0), 10.0), 0.7, 1e-9, "circle (80,0) r10 hit at t=.7")
	t.near(NavalSimulation.segment_circle(a, b, Vector2(50, 10), 10.0), 0.5, 1e-9, "tangent (50,10) at t=.5")
	t.check(NavalSimulation.segment_circle(a, b, Vector2(50, 11), 10.0) == -1.0, "(50,11) misses")
	t.check(NavalSimulation.segment_circle(a, b, Vector2(5, 3), 10.0) == 0.0, "start inside returns 0")
	t.check(NavalSimulation.segment_circle(a, a, Vector2(5, 3), 10.0) == 0.0, "zero-length inside returns 0")
	t.check(NavalSimulation.segment_circle(a, a, Vector2(50, 0), 10.0) == -1.0, "zero-length outside misses")
	t.check(NavalSimulation.segment_circle(a, b, Vector2(110, 0), 10.0) == 1.0, "contact at segment endpoint hits")
	t.check(NavalSimulation.segment_circle(a, b, Vector2(110.01, 0), 10.0) == -1.0, "just beyond endpoint misses")
	t.check(NavalSimulation.segment_circle(a, b, Vector2(-20, 0), 10.0) == -1.0, "circle behind start misses")


func _test_nearest_contact_and_ties(t) -> void:
	# Brig (r28) nearer along the path than a frigate inserted first; coincident sloops tie by ID.
	for reverse in [false, true]:
		var sim = _sim_with([_ship(5, 1, "frigate", Vector2(1100, 1000)), _ship(2, 1, "brig", Vector2(1050, 1000))], reverse)
		_shot(sim, 9, "round", Vector2(1000, 1000), Vector2.RIGHT)
		sim._apply_damage(sim._advance_projectiles(DT * 20.0, [2, 5]))  # 200-unit segment reaches both
		t.check(sim.ships[2]["hull"] == 152.0 and sim.ships[5]["hull"] == 240.0, "nearest contact wins regardless of insertion (reverse=%s)" % reverse)
		var tie = _sim_with([_ship(4, 1, "sloop", Vector2(1030, 1000)), _ship(3, 1, "sloop", Vector2(1030, 1000))], reverse)
		_shot(tie, 9, "round", Vector2(1000, 1000), Vector2.RIGHT)
		tie._advance_projectiles(DT, [3, 4])
		t.check(_of_type(tie, "hit").size() == 1 and _of_type(tie, "hit")[0]["victim_id"] == 3, "coincident colliders tie to lower ID (reverse=%s)" % reverse)


func _test_range_endpoint(t) -> void:
	for c in [[Vector2(1027, 1000), true], [Vector2(1027.01, 1000), false]]:
		var sim = _sim_with([_ship(2, 1, "sloop", c[0])])
		_shot(sim, 9, "round", Vector2(1000, 1000), Vector2.RIGHT, true, 5.0)
		sim._advance_projectiles(DT, [2])
		var hit: bool = _of_type(sim, "hit").size() == 1
		var splash: bool = _of_type(sim, "splash").size() == 1
		t.check(hit == c[1] and splash != c[1] and sim.projectiles.is_empty(), "contact at final range endpoint: hit=%s" % c[1])


func _test_travel(t) -> void:
	for c in [["round", 900.0, 90], ["chain", 600.0, 72], ["grape", 300.0, 40]]:
		var sim = _sim_with([_ship(1, 0, "sloop", Vector2(2500, 2100))])
		sim.ships[1]["weapons"]["port"] = {"ammo": c[0], "loads": [1.0, 0.0, 0.0, 0.0]}
		sim.step(DT, {1: {"fire_port": true}})
		var origin: Vector2 = _of_type(sim, "shot")[0]["position"]
		for i in c[2] - 2:
			sim.step(DT, {})
		t.check(sim.projectiles.size() == 1, "%s still in flight after %d ticks" % [c[0], c[2] - 1])
		sim.step(DT, {})
		var splash := _of_type(sim, "splash")
		t.check(sim.projectiles.is_empty() and splash.size() == 1, "%s splashes on tick %d (%.4fs)" % [c[0], c[2], c[2] * DT])
		if splash.size() == 1:
			t.near(origin.distance_to(splash[0]["position"]), c[1], 1e-2, "%s travels its range" % c[0])
			t.check(splash[0].keys() == ["type", "projectile_id", "position"] and splash[0]["type"] == "splash"
				and splash[0]["projectile_id"] == 1, "%s splash event fields" % c[0])
			t.check(splash[0]["position"].distance_to(origin + Vector2.UP * c[1]) < 1e-2, "%s splash at range end along the port broadside" % c[0])


func _test_owner_clearance(t) -> void:
	var sim = _sim_with([_ship(1, 0, "sloop", Vector2(2500, 2100))])
	sim.ships[1]["weapons"]["port"]["loads"] = [1.0, 0.0, 0.0, 0.0]
	sim.step(DT, {1: {"fire_port": true}})
	t.check(sim.projectiles.size() == 1 and not sim.projectiles[0]["owner_cleared"], "fresh shot not cleared, owner not hit")
	sim.step(DT, {})
	t.check(not sim.projectiles[0]["owner_cleared"], "shot still inside owner circle")
	sim.step(DT, {})
	t.check(sim.projectiles[0]["owner_cleared"], "shot cleared once endpoint leaves owner circle")
	t.check(sim.ships[1]["hull"] == 100.0, "owner never hit while leaving")
	var gone = _sim_with([_ship(1, 0, "sloop", Vector2(2500, 2100)), _ship(2, 1, "brig", Vector2(4000, 2100))])
	_shot(gone, 2, "round", Vector2(2500, 1000), Vector2.UP, false)
	gone.ships[2]["active"] = false
	gone.step(DT, {})
	t.check(gone.projectiles[0]["owner_cleared"], "inactive owner clears its shot")


func _test_muzzle_and_owner_hits(t) -> void:
	var sim = _sim_with([_ship(1, 0, "sloop", Vector2(1000, 1000)), _ship(2, 0, "sloop", Vector2(1000, 1015))])
	_shot(sim, 1, "round", Vector2(1000, 1000), Vector2.DOWN, false)
	sim._apply_damage(sim._advance_projectiles(DT, [1, 2]))
	t.check(sim.ships[1]["hull"] == 100.0 and sim.ships[2]["hull"] == 92.0, "muzzle exception skips owner only; overlapping ally hit")
	var own = _sim_with([_ship(1, 0, "sloop", Vector2(1000, 1000))])
	_shot(own, 1, "round", Vector2(1000, 970), Vector2.DOWN, true)
	own._apply_damage(own._advance_projectiles(DT, [1]))
	t.check(own.ships[1]["hull"] == 92.0, "cleared shot can hit its owner")


## Shooter at (2500,2100) fires one starboard gun south; blocker order decides the victim.
func _friendly(ally_y: float, enemy_y: float, ally_active := true, reverse := false) -> Array:
	var shooter := _ship(1, 0, "sloop", Vector2(2500, 2100))
	shooter["weapons"]["starboard"]["loads"] = [1.0, 0.0, 0.0, 0.0]
	var ally := _ship(2, 0, "sloop", Vector2(2500, ally_y))
	ally["active"] = ally_active
	var enemy := _ship(3, 1, "brig", Vector2(2500, enemy_y))
	for s in [ally, enemy]:
		s["sails"] = 0.0  # stationary obstacle (only hull is asserted)
	var sim = _sim_with([shooter, ally, enemy], reverse)
	var untouched := true
	for i in 60:
		sim.step(DT, {1: {"fire_starboard": true}} if i == 0 else {})
		if not _of_type(sim, "hit").is_empty():
			break
		untouched = untouched and sim.ships[2]["hull"] == 100.0 and sim.ships[3]["hull"] == 160.0
	return [sim.ships[2]["hull"], sim.ships[3]["hull"], untouched]


func _test_friendly_fire(t) -> void:
	for reverse in [false, true]:
		var r := _friendly(2200, 2300, true, reverse)
		t.check(r[0] == 92.0 and r[1] == 160.0, "ally in front takes 8 hull, enemy none (reverse=%s, got %s)" % [reverse, r])
		t.check(r[2], "health changes only on contact (reverse=%s)" % reverse)
		r = _friendly(2300, 2200, true, reverse)
		t.check(r[0] == 100.0 and r[1] == 152.0, "enemy in front takes the hit (reverse=%s, got %s)" % [reverse, r])
		r = _friendly(2200, 2300, false, reverse)
		t.check(r[0] == 100.0 and r[1] == 152.0, "inactive ally ignored as blocker (reverse=%s, got %s)" % [reverse, r])


func _test_fixed_direction_and_miss(t) -> void:
	var shooter := _ship(1, 0, "sloop", Vector2(2500, 2100))
	shooter["weapons"]["port"]["loads"] = [1.0, 0.0, 0.0, 0.0]
	var sim = _sim_with([shooter, _ship(2, 1, "sloop", Vector2(2500, 1700))])
	sim.step(DT, {1: {"fire_port": true}})
	var dir: Vector2 = sim.projectiles[0]["direction"]
	t.check(_of_type(sim, "shot")[0]["direction"] == dir, "shot event carries projectile direction")
	var fixed := true
	for i in 120:
		sim.step(DT, {1: {"turn": 1.0}, 2: {"turn": -0.3}})
		if not sim.projectiles.is_empty():
			fixed = fixed and sim.projectiles[0]["direction"] == dir
	t.check(fixed, "direction fixed after fire while shooter turns")
	t.check(sim.ships[2]["hull"] == 100.0 and sim.projectiles.is_empty(), "moving target left the trajectory: miss, then splash")


# --- damage and defeat ---------------------------------------------------------

## One-tick hit on an untouched brig (id 2) by the given ammo; shot starts inside its circle.
func _hit_brig(ammo: String, tracks := []):
	var brig := _ship(2, 1, "brig", Vector2(3000, 2100))
	if not tracks.is_empty():
		brig["hull"] = tracks[0]
		brig["sails"] = tracks[1]
		brig["crew"] = tracks[2]
	var sim = _sim_with([_ship(1, 0, "sloop", Vector2(1000, 1000)), brig])
	for a in ammo.split(","):
		_shot(sim, 1, a, Vector2(3000, 2080), Vector2.DOWN)
	sim.step(DT, {})
	return sim


func _test_track_damage(t) -> void:
	var cases := {"round": [152.0, 100.0, 90.0], "chain": [160.0, 94.0, 90.0], "grape": [160.0, 100.0, 85.0]}
	for ammo in cases:
		var sim = _hit_brig(ammo)
		t.check(_tracks(sim.ships[2]) == cases[ammo], "%s hit: brig tracks %s (got %s)" % [ammo, cases[ammo], _tracks(sim.ships[2])])
		t.check(_tracks(sim.ships[1]) == [100.0, 70.0, 60.0], "%s hit: no collateral on shooter" % ammo)
		t.check(sim.ships[2]["active"] and sim.ships[2]["defeat_reasons"].is_empty() and sim.result.is_empty(), "%s hit: still active, no result" % ammo)
		var hits := _of_type(sim, "hit")
		var track: String = Definitions.AMMO[ammo]["track"]
		t.check(hits.size() == 1 and hits[0]["projectile_id"] == 1 and hits[0]["victim_id"] == 2 and hits[0]["ammo"] == ammo
			and hits[0]["track"] == track and hits[0]["damage"] == Definitions.AMMO[ammo]["damage"]
			and hits[0]["position"] == Vector2(3000, 2080), "%s hit event fields" % ammo)


func _test_clamp_and_reasons(t) -> void:
	var sim = _hit_brig("round", [3.0, 100.0, 90.0])
	t.check(sim.ships[2]["hull"] == 0.0 and sim.ships[2]["defeat_reasons"] == ["sunk"], "overkill clamps hull to 0, sunk")
	t.check(not sim.ships[2]["active"] and sim.ships[2]["speed"] == 0.0, "sunk ship inactive, speed 0")
	var defeated := _of_type(sim, "ship_defeated")
	t.check(defeated == [{"type": "ship_defeated", "ship_id": 2, "reasons": ["sunk"], "position": sim.ships[2]["position"]}], "ship_defeated event")
	sim = _hit_brig("round,chain,grape", [3.0, 3.0, 3.0])
	t.check(_tracks(sim.ships[2]) == [0.0, 0.0, 0.0] and sim.ships[2]["defeat_reasons"] == ["sunk"], "all tracks zero: sunk only")
	sim = _hit_brig("chain,grape", [50.0, 3.0, 3.0])
	t.check(_tracks(sim.ships[2]) == [50.0, 0.0, 0.0] and sim.ships[2]["defeat_reasons"] == ["sails", "crew"], "sails+crew zero keeps both reasons")
	sim = _hit_brig("chain", [50.0, 3.0, 90.0])
	t.check(sim.ships[2]["defeat_reasons"] == ["sails"] and not sim.ships[2]["active"], "zero sails disables")
	sim = _hit_brig("grape", [50.0, 100.0, 3.0])
	t.check(sim.ships[2]["defeat_reasons"] == ["crew"] and not sim.ships[2]["active"], "zero crew disables")
	t.check(sim.result.is_empty(), "defeat generates no combat result")


func _test_simultaneous_defeat(t) -> void:
	# reverse: dictionary insertion order; lower_hits_2: the lower projectile ID targets ship 2.
	for lower_hits_2 in [false, true]:
		for reverse in [false, true]:
			var label := "reverse=%s, lower ID hits ship 2=%s" % [reverse, lower_hits_2]
			var a := _ship(1, 0, "sloop", Vector2(1000, 1000))
			var b := _ship(2, 1, "brig", Vector2(4000, 3000))
			a["hull"] = 3.0
			b["hull"] = 3.0
			var sim = _sim_with([a, b], reverse)
			var incoming := [[2, Vector2(1000, 990)], [1, Vector2(4000, 2990)]]  # [owner, start] onto ship 1, ship 2
			if lower_hits_2:
				incoming.reverse()
			for s in incoming:
				_shot(sim, s[0], "round", s[1], Vector2.DOWN)
			sim.step(DT, {1: {"fire_port": true}, 2: {"fire_starboard": true}})
			var owners := _of_type(sim, "shot").map(func(e): return e["ship_id"])
			t.check(owners.count(1) == 4 and owners.count(2) == 6, "both doomed ships fire before damage (%s)" % label)
			var victims := _of_type(sim, "hit").map(func(e): return [e["projectile_id"], e["victim_id"]])
			t.check(victims == ([[1, 2], [2, 1]] if lower_hits_2 else [[1, 1], [2, 2]]), "hit order follows projectile ID (%s)" % label)
			t.check(not sim.ships[1]["active"] and not sim.ships[2]["active"], "both defeated in one tick (%s)" % label)
			t.check(_of_type(sim, "ship_defeated").map(func(e): return e["ship_id"]) == [1, 2], "defeat events in ID order (%s)" % label)
			t.check(sim.result.is_empty(), "no result for simultaneous defeat (%s)" % label)
			sim.step(DT, {})
			t.check(sim.projectiles.size() == 10, "shots survive owner defeat (%s)" % label)


func _test_lethal_hit_keeps_blocking(t) -> void:
	var brig := _ship(2, 1, "brig", Vector2(3000, 2100))
	brig["hull"] = 3.0
	var sim = _sim_with([_ship(1, 0, "sloop", Vector2(1000, 1000)), brig, _ship(3, 1, "sloop", Vector2(3100, 2100))])
	_shot(sim, 1, "round", Vector2(2980, 2100), Vector2.RIGHT)
	_shot(sim, 1, "round", Vector2(2980, 2100), Vector2.RIGHT)
	sim.step(DT, {})
	var victims := _of_type(sim, "hit").map(func(e): return e["victim_id"])
	t.check(victims == [2, 2] and sim.ships[3]["hull"] == 100.0, "lethal first hit does not let second shot through")
	t.check(not sim.ships[2]["active"], "brig sunk")
	_shot(sim, 1, "round", sim.ships[2]["position"] - Vector2(20, 0), Vector2.RIGHT)
	var hits := _run_until_hit(sim, 60)
	t.check(hits.size() == 1 and hits[0]["victim_id"] == 3 and sim.ships[3]["hull"] == 92.0, "next tick the wreck no longer blocks")
	var wreck_pos: Vector2 = sim.ships[2]["position"]
	sim.ships[3]["position"] = wreck_pos
	sim.step(DT, {})
	t.check(sim.ships[2]["position"] == wreck_pos, "wreck is not a contact obstacle")


func _test_damage_effects(t) -> void:
	# Chain brings sails 56 -> 50 (half): next tick speed uses .3+.7*.5 = .65.
	var sim = _hit_brig("chain", [160.0, 56.0, 90.0])
	sim.step(DT, {})
	t.near(sim.ships[2]["speed"], 145.0 * 0.8 * 0.65, 1e-4, "half sails after chain: .65 speed scale")
	# Grape brings crew 50 -> 45 (half): this tick reloads at pre-damage crew, next at .625.
	var brig := _ship(2, 1, "brig", Vector2(3000, 2100))
	brig["crew"] = 50.0
	brig["weapons"]["port"]["loads"] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var reload = _sim_with([_ship(1, 0, "sloop", Vector2(1000, 1000)), brig])
	_shot(reload, 1, "grape", Vector2(3000, 2080), Vector2.DOWN)
	reload.step(DT, {})
	var d0: float = NavalSimulation.reload_duration(0, 6, 8.0)
	var first: float = DT * (0.25 + 0.75 * 50.0 / 90.0) / d0
	t.near(reload.ships[2]["weapons"]["port"]["loads"][0], first, 1e-9, "hit tick reloads with pre-damage crew")
	t.check(reload.ships[2]["crew"] == 45.0, "grape brought crew to half")
	reload.step(DT, {})
	t.near(reload.ships[2]["weapons"]["port"]["loads"][0], first + DT * 0.625 / d0, 1e-9, "next tick reloads at .625")
	# Hull-only damage changes neither handling nor reload.
	var hurt = _hit_brig("round", [100.0, 100.0, 90.0])
	var fresh = _sim_with([_ship(1, 0, "sloop", Vector2(1000, 1000)), _ship(2, 1, "brig", Vector2(3000, 2100))])
	fresh.step(DT, {})
	for s in [hurt, fresh]:
		s.ships[2]["weapons"]["port"]["loads"] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for i in 30:
			s.step(DT, {2: {"turn": 1.0}})
	var same: bool = hurt.ships[2]["heading"] == fresh.ships[2]["heading"] and hurt.ships[2]["speed"] == fresh.ships[2]["speed"] \
		and hurt.ships[2]["weapons"]["port"]["loads"] == fresh.ships[2]["weapons"]["port"]["loads"]
	t.check(same, "hull-only damage keeps turn, speed and reload")


func _test_defeated_inert(t) -> void:
	var sim = _hit_brig("chain", [160.0, 3.0, 90.0])
	var before: Dictionary = sim.ships[2].duplicate(true)
	sim.step(DT, {2: {"turn": 1.0, "toggle_sails": true, "fire_port": true, "fire_starboard": true, "cycle_port": true, "cycle_starboard": true}})
	t.check(sim.ships[2] == before, "defeated ship ignores all commands next tick")
	t.check(sim.events.is_empty(), "defeated ship emits no fire/rejection events")


func _test_event_copies(t) -> void:
	var sim = _hit_brig("round", [3.0, 100.0, 90.0])
	var e: Dictionary = _of_type(sim, "ship_defeated")[0]
	e["reasons"].append("tampered")
	t.check(sim.ships[2]["defeat_reasons"] == ["sunk"], "event reasons are a copy")
	t.check(sim.events.all(func(ev): return ev.has("type")), "every event has a type")
	var fire = _sim_with([_ship(1, 0, "sloop", Vector2(2500, 2100))])
	fire.step(DT, {1: {"fire_port": true}})
	var shot: Dictionary = _of_type(fire, "shot")[0]
	t.check(shot.keys() == ["type", "ship_id", "side", "gun_index", "projectile_id", "ammo", "position", "direction"], "shot event fields")
	t.check(shot["position"] == fire.ships[1]["position"] and shot["ammo"] == "round", "shot from ship center")
