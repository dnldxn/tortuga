extends RefCounted
## Pure naval simulation state. No SceneTree/node/physics/input/drawing/audio dependencies.
## Presentation reads these fields without mutating them.

const Definitions := preload("res://sim/definitions.gd")

const PLAYER_ID := 1  # opposition ships use ids >= 2
const TEAM_PLAYER := 0
const TEAM_OPPOSITION := 1
const CONTACT_PASSES := 32
const CONTACT_TOLERANCE := 0.01  # world units; Vector2 is 32-bit (~5e-4 precision near 6000)

var ships: Dictionary = {}  # int id -> ship Dictionary
var projectiles: Array = []
var events: Array = []  # current step only
var elapsed: float = 0.0
var preset_id: String = ""
var selected_vessel_id: String = ""
var wind_heading: float = 0.0
var result: Dictionary = {}
var next_projectile_id: int = 1


## Fresh ship record with full tracks and fully loaded round shot on both sides.
static func make_ship(id: int, team: int, vessel_id: String, position: Vector2, heading: float, role := "ship") -> Dictionary:
	var vessel: Dictionary = Definitions.VESSELS[vessel_id]
	var weapons := {}
	for side in Definitions.SIDES:
		var loads := []
		loads.resize(vessel["guns_per_side"])
		loads.fill(1.0)
		weapons[side] = {"ammo": Definitions.AMMO_CYCLE[0], "loads": loads}
	return {
		"id": id,
		"team": team,
		"role": role,
		"vessel_id": vessel_id,
		"position": position,
		"heading": heading,
		"speed": 0.0,
		"reefed": false,
		"hull": vessel["hull"],
		"sails": vessel["sails"],
		"crew": vessel["crew"],
		"active": true,
		"defeat_reasons": [],
		"weapons": weapons,
	}


## Seconds for gun i of n (0-based) to reload from empty at full crew.
static func reload_duration(i: int, n: int, base: float) -> float:
	return base * (0.65 + 0.35 * float(i) / float(n - 1))


static func reload_rate(crew: float, max_crew: float) -> float:
	return 0.25 + 0.75 * clampf(crew / max_crew, 0.0, 1.0)


## First contact parameter t in [0,1] of the point segment start->end with the circle, or -1.0.
## Computed component-wise in 64-bit floats (Vector2 is 32-bit).
static func segment_circle(start: Vector2, end: Vector2, center: Vector2, radius: float) -> float:
	var dx := float(end.x) - float(start.x)
	var dy := float(end.y) - float(start.y)
	var fx := float(start.x) - float(center.x)
	var fy := float(start.y) - float(center.y)
	var c := fx * fx + fy * fy - radius * radius
	if c <= 0.0:
		return 0.0  # starts inside or on the circle
	var a := dx * dx + dy * dy
	if a == 0.0:
		return -1.0  # zero-length segment outside the circle
	var b := 2.0 * (fx * dx + fy * dy)
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	# Start is outside (c > 0), so both roots share a sign: only the smaller can lie in [0,1].
	var t := (-b - sqrt(disc)) / (2.0 * a)
	return t if t >= 0.0 and t <= 1.0 else -1.0


func reset(new_preset_id: String, vessel_id: String) -> void:
	if not Definitions.PRESETS.has(new_preset_id):
		push_error("NavalSimulation.reset: unknown preset '%s'" % new_preset_id)
		return
	if not Definitions.VESSELS.has(vessel_id):
		push_error("NavalSimulation.reset: unknown vessel '%s'" % vessel_id)
		return
	var preset: Dictionary = Definitions.PRESETS[new_preset_id]
	preset_id = new_preset_id
	selected_vessel_id = vessel_id
	wind_heading = preset["wind_heading"]
	elapsed = 0.0
	projectiles = []
	events = []
	result = {}
	next_projectile_id = 1
	ships = {
		PLAYER_ID: make_ship(PLAYER_ID, TEAM_PLAYER, vessel_id, preset["player_position"], preset["player_heading"]),
	}
	for s in preset.get("opposition", []):
		ships[s["id"]] = make_ship(s["id"], s["team"], s["vessel_id"], s["position"], s["heading"], s["role"])


## Order: cycles, movement/contact, reload, fire, projectiles (damage accumulated),
## then damage applied and defeat classified. Every ship active at step start may act
## before any damage lands.
func step(dt: float, commands: Dictionary) -> void:
	if not result.is_empty():
		events.clear()  # terminal no-op: effects cannot repeat, result and final state stay
		return
	events.clear()
	var acting := []
	for id in ships:
		if ships[id]["active"]:
			acting.append(id)
	acting.sort()
	# A practice target never sails, cycles or fires, even if commands are injected for it.
	# It still reloads (a no-op, since it never empties), takes damage and is pushed by contact.
	var commanded := acting.filter(func(id): return ships[id]["role"] != "practice_target")
	for id in commanded:
		var command: Dictionary = commands.get(id, {})
		for side in Definitions.SIDES:
			if command.get("cycle_" + side, false):
				_cycle(ships[id]["weapons"][side])
	for id in commanded:
		_sail(ships[id], commands.get(id, {}), dt)
	resolve_contacts()
	for id in acting:
		_reload(ships[id], dt)
	for id in commanded:
		var command: Dictionary = commands.get(id, {})
		for side in Definitions.SIDES:
			if command.get("fire_" + side, false):
				_fire(ships[id], side)
	_apply_damage(_advance_projectiles(dt, acting))
	elapsed += dt
	_resolve_combat_result()


## Duel outcome after 02's damage/defeat pass. Practice and already-resolved matches
## stay empty; the player's team is counted, never a hardcoded enemy ID. Plan 04's
## escape resolution joins here.
func _resolve_combat_result() -> void:
	if preset_id == "practice" or not result.is_empty():
		return
	var player_active := false
	var opposition_active := 0
	var defeated := []
	var ids: Array = ships.keys()
	ids.sort()
	for id in ids:
		var ship: Dictionary = ships[id]
		if ship["team"] == TEAM_PLAYER:
			player_active = player_active or ship["active"]
		else:
			opposition_active += 1 if ship["active"] else 0
		if not ship["active"]:
			var reasons: Array = ship["defeat_reasons"]
			defeated.append({
				"ship_id": id,
				"reason": "sunk" if "sunk" in reasons else "disabled",
				"disabled_by": reasons.filter(func(r): return r != "sunk"),
			})
	var outcome := ""
	if player_active and opposition_active == 0:
		outcome = "victory"
	elif not player_active and opposition_active > 0:
		outcome = "defeat"
	elif not player_active and opposition_active == 0:
		outcome = "draw"
	if outcome == "":
		return
	result = {"outcome": outcome, "elapsed": elapsed, "defeated": defeated}


## Copied, non-aliasing view for the AI: contract fields only, no live nested
## arrays (loads are reduced to per-side ready counts), no predicted results.
func ai_observation() -> Dictionary:
	var observed := {}
	for id in ships:
		var ship: Dictionary = ships[id]
		var entry := {
			"id": ship["id"], "team": ship["team"], "vessel_id": ship["vessel_id"],
			"position": ship["position"], "heading": ship["heading"], "speed": ship["speed"],
			"reefed": ship["reefed"], "hull": ship["hull"], "sails": ship["sails"],
			"crew": ship["crew"], "active": ship["active"],
		}
		if ship["active"]:
			var sides := {}
			for side in Definitions.SIDES:
				var weapon: Dictionary = ship["weapons"][side]
				sides[side] = {
					"ammo": weapon["ammo"],
					"ready": weapon["loads"].filter(func(load): return load == 1.0).size(),
					"total": weapon["loads"].size(),
				}
			entry["sides"] = sides
		observed[id] = entry
	return {"ships": observed}


## Read-only aim assist shared by firing and HUD. Nearest active enemy center within the
## selected ammo range and ARC_HALF_ANGLE of the broadside; equal distances pick the lower ID.
## Otherwise direction is exactly perpendicular and reason explains why.
func aim_for(ship_id: int, side: String) -> Dictionary:
	var shooter: Dictionary = ships[ship_id]
	var ammo_range: float = Definitions.AMMO[shooter["weapons"][side]["ammo"]]["range"]
	var broadside: float = shooter["heading"] + (-PI / 2.0 if side == "port" else PI / 2.0)
	var aim := {"target_id": null, "direction": Vector2.from_angle(broadside), "range": ammo_range, "reason": "no_active_enemy"}
	var best := INF
	var ids := ships.keys()
	ids.sort()
	for id in ids:
		var other: Dictionary = ships[id]
		if not other["active"] or other["team"] == shooter["team"]:
			continue
		if aim["reason"] == "no_active_enemy":
			aim["reason"] = "outside_arc"
		var delta: Vector2 = other["position"] - shooter["position"]
		var distance := delta.length()
		if absf(Definitions.wrap_angle(delta.angle() - broadside)) > Definitions.ARC_HALF_ANGLE:
			continue
		if distance > ammo_range:
			if aim["target_id"] == null:
				aim["reason"] = "out_of_range"
		elif distance < best and distance > 0.0:
			best = distance
			aim["target_id"] = id
			aim["direction"] = delta / distance
			aim["reason"] = "assisted"
	return aim


func _cycle(weapon: Dictionary) -> void:
	var cycle := Definitions.AMMO_CYCLE
	weapon["ammo"] = cycle[(cycle.find(weapon["ammo"]) + 1) % cycle.size()]
	weapon["loads"].fill(0.0)


## Uses crew before this step's damage; clamps at 1 without rounding up.
func _reload(ship: Dictionary, dt: float) -> void:
	var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
	var n: int = vessel["guns_per_side"]
	var rate := reload_rate(ship["crew"], vessel["crew"])
	for side in Definitions.SIDES:
		var loads: Array = ship["weapons"][side]["loads"]
		for i in n:
			loads[i] = minf(1.0, loads[i] + dt * rate / reload_duration(i, n, vessel["base_reload"]))


## Every exactly-full gun fires one shot from the ship center along the shared aim direction.
func _fire(ship: Dictionary, side: String) -> void:
	var weapon: Dictionary = ship["weapons"][side]
	var loads: Array = weapon["loads"]
	if not loads.any(func(load): return load == 1.0):
		events.append({"type": "fire_rejected", "ship_id": ship["id"], "side": side, "reason": "no_loaded_guns"})
		return
	var direction: Vector2 = aim_for(ship["id"], side)["direction"]
	for i in loads.size():
		if loads[i] != 1.0:
			continue
		loads[i] = 0.0
		projectiles.append({
			"id": next_projectile_id, "owner_id": ship["id"], "ammo": weapon["ammo"],
			"position": ship["position"], "direction": direction,
			"remaining_range": Definitions.AMMO[weapon["ammo"]]["range"], "owner_cleared": false,
		})
		events.append({"type": "shot", "ship_id": ship["id"], "side": side, "gun_index": i,
			"projectile_id": next_projectile_id, "ammo": weapon["ammo"],
			"position": ship["position"], "direction": direction})
		next_projectile_id += 1


## Sweeps every shot (by ID, including this step's) against the active post-movement circles.
## Colliders are fixed for the whole phase, so a lethal hit cannot unblock later shots.
## Returns accumulated damage: {victim_id: {track: amount}}.
func _advance_projectiles(dt: float, colliders: Array) -> Dictionary:
	var damage := {}
	var remaining := []
	for shot in projectiles:
		var ammo: Dictionary = Definitions.AMMO[shot["ammo"]]
		var length := minf(ammo["speed"] * dt, shot["remaining_range"])
		var start: Vector2 = shot["position"]
		var end: Vector2 = start + shot["direction"] * length
		var hit_id = null
		var hit_t := INF
		for id in colliders:  # sorted, so strict < keeps the lowest ID on exact ties
			if id == shot["owner_id"] and not shot["owner_cleared"]:
				continue  # muzzle exception: only the owner, only while leaving its circle
			var t := segment_circle(start, end, ships[id]["position"], _radius(ships[id]))
			if t >= 0.0 and t < hit_t:
				hit_t = t
				hit_id = id
		if hit_id != null:
			var track: String = ammo["track"]
			var by_track: Dictionary = damage.get_or_add(hit_id, {})
			by_track[track] = by_track.get(track, 0.0) + ammo["damage"]
			events.append({"type": "hit", "projectile_id": shot["id"], "victim_id": hit_id, "ammo": shot["ammo"],
				"track": track, "damage": ammo["damage"], "position": start.lerp(end, hit_t)})
			continue
		shot["position"] = end
		shot["remaining_range"] -= length
		if not shot["owner_cleared"]:
			var owner: Dictionary = ships.get(shot["owner_id"], {})
			shot["owner_cleared"] = owner.is_empty() or not owner["active"] \
				or end.distance_to(owner["position"]) > _radius(owner)
		if shot["remaining_range"] <= 1e-9:  # ponytail: absorbs float residue of repeated speed*dt steps
			events.append({"type": "splash", "projectile_id": shot["id"], "position": end})
			continue
		remaining.append(shot)
	projectiles = remaining
	return damage


## Applies all accumulated damage at once, clamps tracks, then classifies defeat.
func _apply_damage(damage: Dictionary) -> void:
	var ids := damage.keys()
	ids.sort()
	for id in ids:
		var ship: Dictionary = ships[id]
		var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
		for track in damage[id]:
			ship[track] = clampf(ship[track] - damage[id][track], 0.0, vessel[track])
		var reasons := []
		if ship["hull"] <= 0.0:
			reasons = ["sunk"]
		else:
			for track in ["sails", "crew"]:
				if ship[track] <= 0.0:
					reasons.append(track)
		if reasons.is_empty():
			continue
		ship["defeat_reasons"] = reasons
		ship["active"] = false
		ship["speed"] = 0.0
		events.append({"type": "ship_defeated", "ship_id": id, "reasons": reasons.duplicate(), "position": ship["position"]})


## Keeps active ships inside their safe bounds and out of each other. Positions only:
## no damage, bounce, heading or speed changes. Bounded: at most CONTACT_PASSES sweeps.
func resolve_contacts() -> void:
	var ids := []
	for id in ships:
		if ships[id]["active"]:
			ids.append(id)
	ids.sort()  # (lower_id, higher_id) pair order makes results insertion-order independent
	for id in ids:
		ships[id]["position"] = _clamped(ships[id]["position"], _radius(ships[id]))
	for _sweep in CONTACT_PASSES:
		var worst := 0.0
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				worst = maxf(worst, _separate(ships[ids[i]], ships[ids[j]]))
		if worst <= CONTACT_TOLERANCE:
			break


## Splits the overlap half/half along the pair normal, then hands each ship's wall-blocked
## share to its partner. Returns the overlap found before correcting.
func _separate(a: Dictionary, b: Dictionary) -> float:
	var ra := _radius(a)
	var rb := _radius(b)
	var delta: Vector2 = b["position"] - a["position"]
	var overlap := ra + rb - delta.length()
	if overlap <= 0.0:
		return overlap
	# Coincident centers: lower id goes -X, higher id +X. The arena is far wider than any pair,
	# so at an east/west wall the transfer below pushes the free partner inward; at north/south
	# walls X is tangential and both move.
	var normal := delta.normalized() if delta.length() > 1e-6 else Vector2.RIGHT
	var want_a: Vector2 = a["position"] - normal * overlap * 0.5
	var want_b: Vector2 = b["position"] + normal * overlap * 0.5
	var new_a := _clamped(want_a, ra)
	var new_b := _clamped(want_b, rb)
	a["position"] = _clamped(new_a + (new_b - want_b), ra)
	b["position"] = _clamped(new_b + (new_a - want_a), rb)
	return overlap


func _radius(ship: Dictionary) -> float:
	return Definitions.VESSELS[ship["vessel_id"]]["radius"]


func _clamped(position: Vector2, radius: float) -> Vector2:
	var bounds := Definitions.safe_bounds(radius)
	return position.clamp(bounds.position, bounds.end)


## Missing command keys are neutral; only turn/toggle_sails act here.
func _sail(ship: Dictionary, command: Dictionary, dt: float) -> void:
	var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
	if command.get("toggle_sails", false):
		ship["reefed"] = not ship["reefed"]
	var turn := clampf(float(command.get("turn", 0.0)), -1.0, 1.0)
	var rate: float = vessel["turn_rate"] * (Definitions.REEF_TURN_FACTOR if ship["reefed"] else 1.0)
	ship["heading"] = Definitions.wrap_angle(ship["heading"] + turn * rate * dt)
	# Immediate target speed (no acceleration); requested speed even if later boundary-blocked.
	var fraction := clampf(float(ship["sails"]) / float(vessel["sails"]), 0.0, 1.0)
	var sail_factor := 0.3 + 0.7 * fraction
	var reef_factor := Definitions.REEF_SPEED_FACTOR if ship["reefed"] else 1.0
	ship["speed"] = vessel["full_speed"] * Definitions.wind_multiplier(ship["heading"], wind_heading) * sail_factor * reef_factor
	if ship["sails"] <= 0:
		ship["speed"] = 0.0
	ship["position"] += Vector2.from_angle(ship["heading"]) * ship["speed"] * dt
