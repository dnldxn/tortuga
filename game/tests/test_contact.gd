extends RefCounted
## Contact/bounds resolution fixtures. Multi-ship fixtures are test scaffolding, not playable enemies.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")

const DT := 1.0 / 60.0
const TOL := 0.01
const VESSEL_IDS := ["sloop", "brig", "frigate"]
const WALLS := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const CORNERS := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]

var max_penetration := 0.0


func run(t) -> bool:
	_test_projection(t)
	_test_unequal_radii(t)
	_test_equal_split(t)
	_test_stationary_contact(t)
	_test_coincident(t)
	_test_walls(t)
	_test_corners(t)
	_test_inactive(t)
	_test_through_step(t)
	_test_wall_recovery(t)
	_test_soak(t)
	print("  max residual penetration in contact fixtures: %s" % max_penetration)
	return true


# --- helpers -----------------------------------------------------------------

func _ship(id: int, vessel_id: String, pos: Vector2, active := true) -> Dictionary:
	var v: Dictionary = Definitions.VESSELS[vessel_id]
	return {
		"id": id, "team": 0 if id == 1 else 1, "vessel_id": vessel_id, "position": pos,
		"heading": 0.0, "speed": 0.0, "reefed": false,
		"hull": v["hull"], "sails": v["sails"], "crew": v["crew"], "active": active,
	}


func _sim_with(list: Array, reverse := false):
	var sim = NavalSimulation.new()
	sim.reset("practice", "sloop")
	sim.ships = {}
	sim.result = {"marker": 1}
	var order := list.duplicate()
	if reverse:
		order.reverse()
	for s in order:
		sim.ships[s["id"]] = s.duplicate(true)
	return sim


func _radius(ship: Dictionary) -> float:
	return Definitions.VESSELS[ship["vessel_id"]]["radius"]


func _bounds(vessel_id: String) -> Rect2:
	return Definitions.safe_bounds(Definitions.VESSELS[vessel_id]["radius"])


## Point on the safe-bounds edge (d = wall direction) or corner (d = diagonal) for a vessel.
func _edge(vessel_id: String, d: Vector2) -> Vector2:
	var b := _bounds(vessel_id)
	return b.get_center() + d * b.size / 2.0


func _in_bounds(ship: Dictionary) -> bool:
	var p: Vector2 = ship["position"]
	var b := Definitions.safe_bounds(_radius(ship))
	return p.is_finite() and p.x >= b.position.x - 1e-3 and p.x <= b.end.x + 1e-3 \
		and p.y >= b.position.y - 1e-3 and p.y <= b.end.y + 1e-3


func _worst_penetration(active: Array) -> float:
	var worst := 0.0
	for i in active.size():
		for j in range(i + 1, active.size()):
			var d: float = (active[i]["position"] as Vector2).distance_to(active[j]["position"])
			worst = maxf(worst, _radius(active[i]) + _radius(active[j]) - d)
	return worst


func _active(sim) -> Array:
	return sim.ships.values().filter(func(s): return s["active"])


func _tracks(ship: Dictionary) -> Array:
	return [ship["hull"], ship["sails"], ship["crew"], ship["active"]]


func _without_position(ship: Dictionary) -> Dictionary:
	var d := ship.duplicate(true)
	d.erase("position")
	return d


## Resolves the fixture directly, in both insertion orders, and checks the full contract.
func _resolve(t, list: Array, label: String):
	var sim = _sim_with(list)
	var rev = _sim_with(list, true)
	sim.resolve_contacts()
	rev.resolve_contacts()
	var ok_bounds := true
	var ok_fields := true
	var ok_inactive := true
	var same := true
	for s in list:
		var now: Dictionary = sim.ships[s["id"]]
		same = same and now["position"] == rev.ships[s["id"]]["position"]
		if s["active"]:
			ok_bounds = ok_bounds and _in_bounds(now)
			ok_fields = ok_fields and _without_position(now) == _without_position(s)
		else:
			ok_inactive = ok_inactive and now == s
	var worst := _worst_penetration(_active(sim))
	max_penetration = maxf(max_penetration, worst)
	t.check(ok_bounds, "%s: bounded finite centers" % label)
	t.check(worst <= TOL, "%s: separated (worst penetration %s)" % [label, worst])
	t.check(ok_fields, "%s: only positions change" % label)
	t.check(ok_inactive, "%s: inactive ships untouched" % label)
	t.check(sim.result == {"marker": 1}, "%s: result unchanged" % label)
	t.check(same, "%s: insertion-order independent" % label)
	return sim


# --- direct resolver fixtures -------------------------------------------------

func _test_projection(t) -> void:
	var sim = _resolve(t, [_ship(1, "sloop", Vector2(-100, 5000)), _ship(2, "brig", Vector2(3000, 100))], "projection")
	t.check(sim.ships[1]["position"] == Vector2(182, 4018), "sloop projected to SW safe corner")
	t.check(sim.ships[2]["position"] == Vector2(3000, 188), "brig projected to north safe edge")


func _test_unequal_radii(t) -> void:
	var sim = _resolve(t, [_ship(1, "sloop", Vector2(3000, 2000)), _ship(2, "frigate", Vector2(3030, 2000))], "unequal pair")
	t.near(sim.ships[1]["position"].x, 2987.0, 1e-3, "sloop takes half of 26 overlap")
	t.near(sim.ships[2]["position"].x, 3043.0, 1e-3, "frigate takes half of 26 overlap")
	_resolve(t, [_ship(1, "sloop", Vector2(3000, 2000)), _ship(2, "brig", Vector2(3020, 2010)), _ship(3, "frigate", Vector2(3035, 1995))], "unequal trio")


func _test_equal_split(t) -> void:
	var sim = _resolve(t, [_ship(1, "brig", Vector2(3000, 2000)), _ship(2, "brig", Vector2(3000, 2040))], "equal split")
	t.check(sim.ships[1]["position"] == Vector2(3000, 1992) and sim.ships[2]["position"] == Vector2(3000, 2048), "equal ships split 16 overlap 8/8")


func _test_stationary_contact(t) -> void:
	var sim = _resolve(t, [_ship(1, "sloop", Vector2(3000, 2000)), _ship(2, "sloop", Vector2(3044, 2000))], "touching pair")
	t.check(sim.ships[1]["position"] == Vector2(3000, 2000) and sim.ships[2]["position"] == Vector2(3044, 2000), "exact touching contact does not move")
	var wall := _edge("sloop", Vector2.LEFT)
	sim = _resolve(t, [_ship(1, "sloop", wall), _ship(2, "sloop", wall + Vector2(44, 0))], "touching at wall")
	t.check(sim.ships[1]["position"] == wall and sim.ships[2]["position"] == wall + Vector2(44, 0), "touching at wall does not move")


func _test_coincident(t) -> void:
	var sim = _resolve(t, [_ship(1, "sloop", Vector2(3000, 2000)), _ship(2, "frigate", Vector2(3000, 2000))], "coincident unequal")
	t.check(sim.ships[1]["position"] == Vector2(2972, 2000) and sim.ships[2]["position"] == Vector2(3028, 2000), "coincident: lower id -X, higher id +X")
	var east := _edge("sloop", Vector2.RIGHT)
	sim = _resolve(t, [_ship(1, "sloop", east), _ship(2, "sloop", east)], "coincident at east wall")
	t.check(sim.ships[2]["position"] == east, "coincident at east wall: blocked higher id stays on bound")
	t.near(sim.ships[1]["position"].x, east.x - 44.0, 1e-3, "coincident at east wall: free partner takes the whole correction inward")
	_resolve(t, [_ship(4, "brig", Vector2(3000, 2000)), _ship(2, "brig", Vector2(3000, 2000)), _ship(9, "brig", Vector2(3000, 2000))], "coincident trio")
	for d in WALLS + CORNERS:
		var p := _edge("brig", d)
		_resolve(t, [_ship(1, "brig", p), _ship(2, "brig", p)], "coincident at %s" % d)
		_resolve(t, [_ship(1, "sloop", p), _ship(2, "sloop", p), _ship(3, "sloop", p)], "coincident trio at %s" % d)


func _test_walls(t) -> void:
	for d in WALLS:
		var p := _edge("sloop", d)
		var along := Vector2(d.y, d.x)
		var pair = _resolve(t, [_ship(1, "sloop", p), _ship(2, "sloop", p - d * 20.0)], "equal pair at wall %s" % d)
		t.check(pair.ships[1]["position"] == p, "wall %s: blocked ship stays on bound" % d)
		t.check((pair.ships[2]["position"] - (p - d * 44.0)).length() <= 1e-3, "wall %s: partner takes the blocked half (at %s)" % [d, pair.ships[2]["position"]])
		_resolve(t, [_ship(1, "sloop", p), _ship(2, "brig", p - d * 20.0)], "pair at wall %s" % d)
		_resolve(t, [_ship(2, "sloop", p), _ship(1, "frigate", p - d * 20.0)], "pair at wall %s (ids swapped)" % d)
		_resolve(t, [_ship(1, "sloop", p), _ship(2, "sloop", p - d * 15.0), _ship(3, "sloop", p - d * 30.0)], "chain at wall %s" % d)
		_resolve(t, [_ship(3, "sloop", p), _ship(2, "brig", p - d * 15.0), _ship(1, "frigate", p - d * 30.0)], "mixed reverse chain at wall %s" % d)
		_resolve(t, [_ship(1, "sloop", p), _ship(2, "sloop", p + along * 10.0), _ship(3, "sloop", p - along * 10.0)], "chain along wall %s" % d)


func _test_corners(t) -> void:
	for d in CORNERS:
		var p := _edge("sloop", d)
		_resolve(t, [_ship(1, "sloop", p), _ship(2, "brig", p - Vector2(d.x * 12.0, 0)), _ship(3, "frigate", p - Vector2(0, d.y * 12.0))], "fan at corner %s" % d)
		_resolve(t, [_ship(1, "sloop", p), _ship(2, "sloop", p - d * 8.0), _ship(3, "sloop", p - d * 16.0)], "diagonal chain at corner %s" % d)


func _test_inactive(t) -> void:
	var sim = _resolve(t, [_ship(1, "sloop", Vector2(3000, 2000)), _ship(2, "frigate", Vector2(3010, 2000), false), _ship(3, "brig", Vector2(-50, -50), false)], "inactive overlap")
	t.check(sim.ships[1]["position"] == Vector2(3000, 2000), "inactive ship does not obstruct")
	t.check(sim.ships[3]["position"] == Vector2(-50, -50), "inactive ship is not projected")
	_resolve(t, [_ship(1, "sloop", Vector2(3000, 2000)), _ship(2, "frigate", Vector2(3020, 2000), false), _ship(3, "sloop", Vector2(3030, 2000))], "active pair around inactive")


# --- through step() -------------------------------------------------------------

func _test_through_step(t) -> void:
	var a := _ship(1, "sloop", Vector2(3000, 2000))
	var b := _ship(2, "sloop", Vector2(3040, 2000))
	b["heading"] = PI
	var c := _ship(3, "brig", Vector2(3020, 2000), false)
	for reverse in [false, true]:
		var sim = _sim_with([a, b, c], reverse)
		sim.step(DT, {})
		t.near(sim.ships[1]["speed"], 144.0, 1e-4, "step: contact keeps requested downwind speed (reverse=%s)" % reverse)
		t.near(sim.ships[2]["speed"], 21.6, 1e-4, "step: contact keeps requested upwind speed (reverse=%s)" % reverse)
		t.check(sim.ships[1]["heading"] == 0.0 and absf(sim.ships[2]["heading"]) == PI, "step: contact keeps headings (reverse=%s)" % reverse)
		t.check(_worst_penetration(_active(sim)) <= TOL, "step: resolved contact (reverse=%s)" % reverse)
		t.check(sim.ships[3] == c and sim.result == {"marker": 1}, "step: inactive/result untouched (reverse=%s)" % reverse)
	var out = _sim_with([_ship(1, "sloop", _edge("sloop", Vector2.RIGHT))])
	out.step(DT, {})
	t.check(out.ships[1]["position"] == _edge("sloop", Vector2.RIGHT), "step: ship sailing into wall stays on safe bound")
	t.near(out.ships[1]["speed"], 144.0, 1e-4, "step: wall-blocked ship keeps requested speed")


## Ship at the west bound facing out (west): turn inward 180 ticks, neutral 420 ticks.
func _recover(vessel_id: String, blocker_offset: Vector2):
	var start := _edge(vessel_id, Vector2.LEFT)
	var ship := _ship(1, vessel_id, start)
	ship["heading"] = PI
	var list := [ship]
	if blocker_offset != Vector2.ZERO:
		var blocker := _ship(2, "brig", start + blocker_offset)
		blocker["sails"] = 0.0  # stationary obstacle
		list.append(blocker)
	var sim = _sim_with(list)
	var ok := true
	for i in 600:
		sim.step(DT, {1: {"turn": 1.0 if i < 180 else 0.0}})
		ok = ok and _worst_penetration(_active(sim)) <= TOL
		for s in list:
			ok = ok and _in_bounds(sim.ships[s["id"]]) and _tracks(sim.ships[s["id"]]) == _tracks(s)
	return [sim, ok, start]


func _test_wall_recovery(t) -> void:
	for vessel_id in VESSEL_IDS:
		var r: float = Definitions.VESSELS[vessel_id]["radius"]
		for offset in [Vector2.ZERO, Vector2(r + 29.0, 0), Vector2(0, -(r + 29.0)), Vector2(r + 10.0, -(r + 10.0))]:
			var res: Array = _recover(vessel_id, offset)
			var label := "%s recovers from west wall (blocker %s)" % [vessel_id, offset]
			t.check(res[1], "%s: bounded, separated, no damage every tick" % label)
			t.check(res[0].ships[1]["position"].x >= res[2].x + 100.0, "%s: >=100 units into water (x %s)" % [label, res[0].ships[1]["position"].x])


func _test_soak(t) -> void:
	for vessel_id in VESSEL_IDS:
		var r: float = Definitions.VESSELS[vessel_id]["radius"]
		var a := _ship(1, vessel_id, _edge(vessel_id, Vector2.LEFT) + Vector2(5, 0))
		a["heading"] = PI
		var b := _ship(2, vessel_id, a["position"] + Vector2(2.0 * r + 4.0, 0))
		var sim = _sim_with([a, b])
		var bounded := true
		var healthy := true
		var separated := true
		for i in 3600:
			var turns := [1.0, -1.0, 0.0, 0.5, -0.3]
			sim.step(DT, {
				1: {"turn": turns[(i / 240) % 5], "toggle_sails": i % 450 == 0},
				2: {"turn": -turns[(i / 310) % 5], "toggle_sails": i % 700 == 0},
			})
			for s in [a, b]:
				bounded = bounded and _in_bounds(sim.ships[s["id"]])
				healthy = healthy and _tracks(sim.ships[s["id"]]) == _tracks(s)
			separated = separated and _worst_penetration(_active(sim)) <= TOL
		t.check(bounded, "%s soak: bounded finite every tick" % vessel_id)
		t.check(healthy, "%s soak: no health loss" % vessel_id)
		t.check(separated, "%s soak: separated every tick" % vessel_id)
