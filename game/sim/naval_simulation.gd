extends RefCounted
## Pure naval simulation state. No SceneTree/node/physics/input/drawing/audio dependencies.
## Presentation reads these fields without mutating them.

const Definitions := preload("res://sim/definitions.gd")

const PLAYER_ID := 1  # opposition ships use ids >= 2
const FIRST_CAPTAIN_SHIP_ID := 100  # battle mode: captain ship ids start here
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
var escape_armed: bool = false
var escape_clear_ticks: int = 0  # consecutive qualifying fixed steps
var battle_mode: bool = false  # only via reset_battle(); captains join through step() ops
var outcomes: Dictionary = {}  # battle mode: ship id -> {"outcome", "elapsed"}
var _captain_ids: Dictionary = {}  # every captain id accepted this battle (reuse guard)
var _end_elapsed: float = 0.0  # this step's post-step elapsed: the time every outcome records


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
		"escape_armed": false,
		"escape_clear_ticks": 0,
		"lingering": false,
		"linger_ticks": 0,  # battle ticks spent lingering
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
	_reset_common(new_preset_id)
	selected_vessel_id = vessel_id
	var preset: Dictionary = Definitions.PRESETS[new_preset_id]
	ships[PLAYER_ID] = make_ship(PLAYER_ID, TEAM_PLAYER, vessel_id, preset["player_position"], preset["player_heading"])
	_add_opposition(preset)


## Battle mode: only the preset's AI fleet; captains join through add_captain ops.
func reset_battle(new_preset_id: String) -> void:
	if not new_preset_id in Definitions.BATTLE_PRESETS:
		push_error("NavalSimulation.reset_battle: unknown battle preset '%s'" % new_preset_id)
		return
	_reset_common(new_preset_id)
	selected_vessel_id = ""
	battle_mode = true
	_add_opposition(Definitions.PRESETS[new_preset_id])


func _reset_common(new_preset_id: String) -> void:
	preset_id = new_preset_id
	wind_heading = Definitions.PRESETS[new_preset_id]["wind_heading"]
	elapsed = 0.0
	projectiles = []
	events = []
	result = {}
	next_projectile_id = 1
	escape_armed = false
	escape_clear_ticks = 0
	battle_mode = false
	outcomes = {}
	_captain_ids = {}
	_end_elapsed = 0.0
	ships = {}


func _add_opposition(preset: Dictionary) -> void:
	for s in preset.get("opposition", []):
		ships[s["id"]] = make_ship(s["id"], s["team"], s["vessel_id"], s["position"], s["heading"], s["role"])


## One fixed step. Every ship active at step start may act before any damage lands.
## Intra-step order (battle mode; Plan 02 relies on it):
## 1. If `result` is set: clear `events` and return (ops and commands silently ignored).
## 2. Clear `events`, then apply `ops` in list order (each sees the state the previous left).
## 3. Acting = active ships, sorted. Lingering ships get `{}` as their command.
## 4. Cycles -> sail -> resolve_contacts() -> reload -> fire -> projectiles (damage
##    accumulated), then damage applied and defeat classified.
## 5. elapsed += dt.
## 6. Record defeat outcomes for newly inactive captain ships.
## 7. Linger countdown and expiry, by sorted id.
## 8. Per-captain escape by sorted id: lingering ships' escape keys are reset; otherwise the
##    pursuit-break rule on the ship's own keys, and completion removes it as `escaped`.
## 9. Battle result.
## Offline, ops are rejected (push_error) and steps 6-9 are _resolve_combat_result()
## then _update_escape(dt).
func step(dt: float, commands: Dictionary, ops: Array = []) -> void:
	if not result.is_empty():
		events.clear()  # terminal no-op: effects cannot repeat, result and final state stay
		return
	events.clear()
	_end_elapsed = elapsed + dt  # bit-identical to the elapsed += dt below
	if battle_mode:
		for op in ops:
			_apply_op(op)
	elif not ops.is_empty():
		push_error("NavalSimulation.step: ops are battle-mode only; ignored %d" % ops.size())
	var acting := []
	for id in ships:
		if ships[id]["active"]:
			acting.append(id)
	acting.sort()
	# A practice target never sails, cycles or fires, even if commands are injected for it.
	# It still reloads (a no-op, since it never empties), takes damage and is pushed by contact.
	var commanded := acting.filter(func(id): return ships[id]["role"] != "practice_target")
	for id in commanded:
		var command := _command(commands, id)
		for side in Definitions.SIDES:
			if command.get("cycle_" + side, false):
				_cycle(ships[id]["weapons"][side])
	for id in commanded:
		_sail(ships[id], _command(commands, id), dt)
	resolve_contacts()
	for id in acting:
		_reload(ships[id], dt)
	for id in commanded:
		var command := _command(commands, id)
		for side in Definitions.SIDES:
			if command.get("fire_" + side, false):
				_fire(ships[id], side)
	_apply_damage(_advance_projectiles(dt, acting))
	elapsed += dt
	if battle_mode:
		_record_captain_defeats()
		_expire_lingering(dt)
		_update_captain_escapes(dt)
		_resolve_battle_result()
		return
	_resolve_combat_result()  # combat outcomes take precedence over escape
	_update_escape(dt)


## A lingering ship's commands are replaced by {}: it holds heading, sails and reef.
func _command(commands: Dictionary, id: int) -> Dictionary:
	return {} if ships[id]["lingering"] else commands.get(id, {})


## True for an id accepted by add_captain this battle (the one captain-ship predicate).
func _is_captain(id) -> bool:
	return typeof(id) == TYPE_INT and _captain_ids.has(id)


## Sorted ids of present captain ships.
func _captain_ships() -> Array:
	var ids := ships.keys().filter(_is_captain)
	ids.sort()
	return ids


## Membership op dispatch; invalid ops are reported and skipped.
func _apply_op(op) -> void:
	if not op is Dictionary:
		push_error("NavalSimulation: op is not a Dictionary: %s" % [op])
		return
	match op.get("op"):
		"add_captain":
			_add_captain(op)
		"linger", "reclaim", "abandon":
			_captain_op(op)
		_:
			push_error("NavalSimulation: unknown op %s" % [op])


## linger / reclaim / abandon on a present, active captain ship. A second linger never
## extends the grace; reclaim needs a lingering ship.
func _captain_op(op: Dictionary) -> void:
	var kind: String = op["op"]
	var id = op.get("ship_id")
	var ship: Dictionary = ships.get(id, {}) if _is_captain(id) else {}
	if ship.is_empty() or not ship["active"] or (kind == "linger" and ship["lingering"]) \
			or (kind == "reclaim" and not ship["lingering"]):
		push_error("NavalSimulation: invalid %s %s" % [kind, op])
		return
	if kind == "abandon":
		_remove(id, "abandoned")
		return
	ship["lingering"] = kind == "linger"
	ship["linger_ticks"] = 0
	ship["escape_armed"] = false
	ship["escape_clear_ticks"] = 0
	events.append({"type": "ship_lingering" if kind == "linger" else "ship_reclaimed", "ship_id": id})


## Erases a captain ship now and records its outcome (escaped | abandoned) with its event.
func _remove(id: int, outcome: String) -> void:
	ships.erase(id)
	_record_outcome(id, outcome)
	events.append({"type": "ship_" + outcome, "ship_id": id})


func _record_outcome(id: int, outcome: String) -> void:
	outcomes[id] = {"outcome": outcome, "elapsed": _end_elapsed}


## Newly inactive captain ships: sunk | disabled ("sunk" wins); a defeated lingerer stays a wreck.
func _record_captain_defeats() -> void:
	for id in _captain_ships():
		var ship: Dictionary = ships[id]
		if ship["active"] or outcomes.has(id):
			continue
		_record_outcome(id, "sunk" if "sunk" in ship["defeat_reasons"] else "disabled")
		ship["lingering"] = false


## The op step is linger tick 1; at linger_ticks_required(dt) the ship is abandoned.
func _expire_lingering(dt: float) -> void:
	for id in _captain_ships():
		var ship: Dictionary = ships[id]
		if not ship["active"] or not ship["lingering"]:
			continue
		ship["linger_ticks"] += 1
		if ship["linger_ticks"] >= linger_ticks_required(dt):
			_remove(id, "abandoned")


## Phase 2 pursuit-break rule per active captain ship, on its own keys. Lingering ships cannot escape.
func _update_captain_escapes(dt: float) -> void:
	for id in _captain_ships():
		var ship: Dictionary = ships[id]
		if not ship["active"]:
			continue
		if ship["lingering"]:
			ship["escape_armed"] = false
			ship["escape_clear_ticks"] = 0
		elif _escape_progress(ship, dt):
			_remove(id, "escaped")


## Only once a captain has joined. victory: no active AI ship and >= 1 active captain ship
## (lingering counts; each gets outcome victory); lost: no active captain, >= 1 active AI;
## draw: neither side has an active ship.
func _resolve_battle_result() -> void:
	if _captain_ids.is_empty():
		return
	var captains := []
	var ai_active := false
	var ids: Array = ships.keys()
	ids.sort()
	for id in ids:
		if not ships[id]["active"]:
			continue
		if _is_captain(id):
			captains.append(id)
		else:
			ai_active = true
	var outcome := ""
	if not ai_active and not captains.is_empty():
		outcome = "victory"
		for id in captains:
			_record_outcome(id, "victory")
	elif captains.is_empty():
		outcome = "lost" if ai_active else "draw"
	if outcome == "":
		return
	result = {"outcome": outcome, "elapsed": elapsed, "defeated": _defeated(), "outcomes": outcomes.duplicate(true)}


func _add_captain(op: Dictionary) -> void:
	var id = op.get("ship_id")
	var vessel_id = op.get("vessel_id")
	if typeof(id) != TYPE_INT or id < FIRST_CAPTAIN_SHIP_ID or _captain_ids.has(id) or ships.has(id) \
			or typeof(vessel_id) != TYPE_STRING or not Definitions.VESSELS.has(vessel_id):
		push_error("NavalSimulation: invalid add_captain %s" % [op])
		return
	var position: Vector2
	var heading: float
	if _captain_ids.is_empty():
		var preset: Dictionary = Definitions.PRESETS[preset_id]
		position = preset["player_position"]
		heading = preset["player_heading"]
	else:
		position = _drop_in_point(vessel_id)
		heading = (Definitions.ARENA_SIZE / 2.0 - position).angle()
	_captain_ids[id] = true
	ships[id] = make_ship(id, TEAM_PLAYER, vessel_id, position, heading)
	events.append({"type": "captain_joined", "ship_id": id, "position": position, "heading": heading, "vessel_id": vessel_id})


## 16 drop-in points on the joining vessel's safe bounds: 4 per side at 1/8, 3/8, 5/8, 7/8.
static func drop_in_candidates(radius: float) -> Array:
	var b := Definitions.safe_bounds(radius)
	var corners := [b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]
	var points := []
	for side in 4:  # clockwise in screen axes from the top-left corner: top, right, bottom, left
		for k in 4:
			points.append(corners[side].lerp(corners[(side + 1) % 4], (k + 0.5) / 4.0))
	return points


## Qualifying candidates are beyond the longest gun range + DROP_IN.margin from every active AI
## ship; pick the one nearest the centroid of active captain ships (arena center if none).
## If none qualifies, the candidate farthest from its nearest active AI ship. Ties: lower index.
func _drop_in_point(vessel_id: String) -> Vector2:
	var threshold := 0.0
	for ammo in Definitions.AMMO.values():
		threshold = maxf(threshold, ammo["range"])
	threshold += Definitions.DROP_IN["margin"]
	var ids: Array = ships.keys()
	ids.sort()
	var ai_positions := []
	var centroid := Vector2.ZERO
	var captains := 0
	for id in ids:
		var ship: Dictionary = ships[id]
		if not ship["active"]:
			continue
		if _is_captain(id):
			centroid += ship["position"]
			captains += 1
		else:
			ai_positions.append(ship["position"])
	centroid = centroid / captains if captains > 0 else Definitions.ARENA_SIZE / 2.0
	var candidates := drop_in_candidates(Definitions.VESSELS[vessel_id]["radius"])
	var best := -1
	var best_d := INF
	var fallback := 0
	var fallback_d := -INF
	for i in candidates.size():
		var point: Vector2 = candidates[i]
		var nearest_ai := INF
		for p in ai_positions:
			nearest_ai = minf(nearest_ai, point.distance_to(p))
		if nearest_ai > threshold:
			var d := point.distance_to(centroid)
			if d < best_d:
				best_d = d
				best = i
		if nearest_ai > fallback_d:
			fallback_d = nearest_ai
			fallback = i
	return candidates[best if best >= 0 else fallback]


## Duel outcome after 02's damage/defeat pass. Practice and already-resolved matches
## stay empty; the player's team is counted, never a hardcoded enemy ID.
func _resolve_combat_result() -> void:
	if preset_id == "practice" or not result.is_empty():
		return
	var player_active := false
	var opposition_active := 0
	for id in ships:
		var ship: Dictionary = ships[id]
		if ship["team"] == TEAM_PLAYER:
			player_active = player_active or ship["active"]
		else:
			opposition_active += 1 if ship["active"] else 0
	var outcome := ""
	if player_active and opposition_active == 0:
		outcome = "victory"
	elif not player_active and opposition_active > 0:
		outcome = "defeat"
	elif not player_active and opposition_active == 0:
		outcome = "draw"
	if outcome == "":
		return
	result = {"outcome": outcome, "elapsed": elapsed, "defeated": _defeated()}


## Sorted-by-ID defeat records shared by every result outcome.
func _defeated() -> Array:
	var defeated := []
	var ids: Array = ships.keys()
	ids.sort()
	for id in ids:
		var reasons: Array = ships[id]["defeat_reasons"]
		if not ships[id]["active"]:
			defeated.append({
				"ship_id": id,
				"reason": "sunk" if "sunk" in reasons else "disabled",
				"disabled_by": reasons.filter(func(r): return r != "sunk"),
			})
	return defeated


## Plan 04 deliberate escape (offline), after combat resolution on resolved fixed-step positions.
## The top-level fields stay authoritative; ship 1's escape keys mirror them.
func _update_escape(dt: float) -> void:
	if preset_id == "practice":
		escape_armed = false
		escape_clear_ticks = 0
		return
	if not result.is_empty():
		return
	var player: Dictionary = ships.get(PLAYER_ID, {})
	if player.is_empty() or not player["active"]:
		return
	player["escape_armed"] = escape_armed
	player["escape_clear_ticks"] = escape_clear_ticks
	var done := _escape_progress(player, dt)
	escape_armed = player["escape_armed"]
	escape_clear_ticks = player["escape_clear_ticks"]
	if done:
		result = {"outcome": "escaped", "reason": "pursuit_broken", "elapsed": elapsed, "defeated": _defeated()}


## One step of the pursuit-break rule on the ship's own escape keys; true when it completes.
## Arms at <= ESCAPE_ARM_DISTANCE of any active enemy; completes after ESCAPE_SECONDS of
## consecutive steps with every active enemy strictly beyond ESCAPE_DISTANCE.
## Integer ticks assume the fixed 1/60 dt (no fractional accumulation).
func _escape_progress(ship: Dictionary, dt: float) -> bool:
	var d2 := INF
	for id in ships:
		var other: Dictionary = ships[id]
		if other["active"] and other["team"] != ship["team"]:
			d2 = minf(d2, ship["position"].distance_squared_to(other["position"]))
	if d2 == INF:
		return false  # no active enemy
	if d2 <= Definitions.ESCAPE_ARM_DISTANCE * Definitions.ESCAPE_ARM_DISTANCE:
		ship["escape_armed"] = true
	if not ship["escape_armed"] or d2 <= Definitions.ESCAPE_DISTANCE * Definitions.ESCAPE_DISTANCE:
		ship["escape_clear_ticks"] = 0
		return false
	ship["escape_clear_ticks"] += 1
	return ship["escape_clear_ticks"] >= escape_ticks_required(dt)


static func escape_ticks_required(dt: float) -> int:
	return roundi(Definitions.ESCAPE_SECONDS / dt)


## Battle ticks a lingering ship survives before it is removed as abandoned.
static func linger_ticks_required(dt: float) -> int:
	return roundi(Definitions.LINGER_SECONDS / dt)


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


## Signed distance of gun i of n (0-based) from the ship center along the heading:
## +GUN_SPREAD * radius at the bow (gun 0) to -GUN_SPREAD * radius at the stern.
static func gun_offset(i: int, n: int, radius: float) -> float:
	return radius * Definitions.GUN_SPREAD * (1.0 - 2.0 * float(i) / float(n - 1))


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


## Every exactly-full gun fires one shot from its own place along the keel (gun_offset),
## straight off the beam: there is no aim assist.
func _fire(ship: Dictionary, side: String) -> void:
	var weapon: Dictionary = ship["weapons"][side]
	var loads: Array = weapon["loads"]
	if not loads.any(func(load): return load == 1.0):
		events.append({"type": "fire_rejected", "ship_id": ship["id"], "side": side, "reason": "no_loaded_guns"})
		return
	var direction := Vector2.from_angle(ship["heading"] + (-PI / 2.0 if side == "port" else PI / 2.0))
	var keel := Vector2.from_angle(ship["heading"])
	for i in loads.size():
		if loads[i] != 1.0:
			continue
		loads[i] = 0.0
		var muzzle: Vector2 = ship["position"] + keel * gun_offset(i, loads.size(), _radius(ship))
		projectiles.append({
			"id": next_projectile_id, "owner_id": ship["id"], "ammo": weapon["ammo"],
			"position": muzzle, "direction": direction,
			"remaining_range": Definitions.AMMO[weapon["ammo"]]["range"], "owner_cleared": false,
		})
		events.append({"type": "shot", "ship_id": ship["id"], "side": side, "gun_index": i,
			"projectile_id": next_projectile_id, "ammo": weapon["ammo"],
			"position": muzzle, "direction": direction})
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
