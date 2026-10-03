extends RefCounted
## Deterministic opposition AI. Maps a copied observation to ordinary commands;
## never touches the simulation, nodes, physics or input. Steering pursues a
## broadside orbit of the nearest active enemy, sticky; ammunition changes
## pass through the same cycle commands a player would issue, with hysteresis
## to avoid reload-cancel churn. All tuning lives in Definitions.AI.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")

## Per commanded ship: preferred broadside, per-side ammo state and recovery memory.
class ShipMemory:
	var side := "port"
	var goal := {"port": "round", "starboard": "round"}  # committed ammo goal per side
	var cycling := {"port": false, "starboard": false}
	var candidate := {"port": "round", "starboard": "round"}
	var candidate_age := {"port": 0.0, "starboard": 0.0}
	var last_change := {"port": 0.0, "starboard": 0.0}  # sim-time of last completed change
	var target_id := -1
	# Recovery (plan 03 task 4): one shared avoidance/recovery path, also used by plan 05.
	var recovering := false
	var recovery_heading := 0.0
	var recovery_started := 0.0
	var last_position := Vector2.ZERO
	var last_progress := 0.0  # sim-time of the last displacement sample
	var recovery_obstacle := -1  # ship id that set the latched heading (-1: boundary/stuck)


var _clock := 0.0  # sim seconds; the only time source
var _memory := {}  # ship id -> ShipMemory


## Reset clears every side goal/timer, target sample and recovery memory.
func reset() -> void:
	_clock = 0.0
	_memory = {}


## Commands keyed by ship ID. Only turn/toggle_sails/fire_*/cycle_* are ever set,
## booleans are edges for this tick alone, turn is clamped to [-1, 1].
func commands_for_tick(observation: Dictionary, dt: float) -> Dictionary:
	_clock += dt
	var commands := {}
	var ids: Array = observation.get("ships", {}).keys()
	ids.sort()
	for id in ids:
		var ship: Dictionary = observation["ships"][id]
		if not ship.get("active", false) or ship.get("team") != NavalSimulation.TEAM_OPPOSITION:
			_memory.erase(id)
			continue
		var target := _target_for(observation, ship, _memory[id].target_id if _memory.has(id) else -1)
		if target.is_empty():
			_memory.erase(id)  # no target or inactive opposition: no command
			continue
		if not _memory.has(id):
			_memory[id] = _fresh_memory(ship)
		var memory: ShipMemory = _memory[id]
		var command := _steer(observation, ship, target, memory)
		_select_ammo(command, observation, ship, target, memory, dt)
		_track_progress(memory, ship)
		commands[id] = command
	return commands


func _fresh_memory(ship: Dictionary) -> ShipMemory:
	var memory := ShipMemory.new()
	memory.last_position = ship["position"]
	memory.last_progress = _clock
	return memory


## Stuck detection: displacement below the threshold over the progress window.
func _track_progress(memory: ShipMemory, ship: Dictionary) -> void:
	if _clock - memory.last_progress >= Definitions.AI["progress_window_s"]:
		if memory.last_position.distance_to(ship["position"]) < Definitions.AI["stuck_displacement"] \
				and ship["speed"] > Definitions.AI["stuck_min_speed"] and not memory.recovering:
			memory.recovering = true
			memory.recovery_started = _clock
			memory.recovery_heading = _inward_heading(ship)
			memory.recovery_obstacle = -1
		memory.last_position = ship["position"]
		memory.last_progress = _clock


## The nearest active enemy, sticky: ties go to the lowest id. A current target that is still an
## active enemy is kept unless the nearest enemy is closer than AI.retarget_ratio x its distance.
## Returns {} when no enemy is active.
func _target_for(observation: Dictionary, ship: Dictionary, current_id := -1) -> Dictionary:
	var ids: Array = observation["ships"].keys()
	ids.sort()
	var nearest: Dictionary = {}
	var nearest_d2 := INF
	for other_id in ids:
		var other: Dictionary = observation["ships"][other_id]
		if not other["active"] or other["team"] == ship["team"]:
			continue
		var d2: float = ship["position"].distance_squared_to(other["position"])
		if d2 < nearest_d2:
			nearest = other
			nearest_d2 = d2
	if nearest.is_empty() or not observation["ships"].has(current_id):
		return nearest
	var current: Dictionary = observation["ships"][current_id]
	if not current["active"] or current["team"] == ship["team"]:
		return nearest
	var ratio: float = Definitions.AI["retarget_ratio"]
	if nearest_d2 < ratio * ratio * ship["position"].distance_squared_to(current["position"]):
		return nearest
	return current


## Steering: avoidance/recovery first (boundary danger wins), then the broadside orbit.
func _steer(observation: Dictionary, ship: Dictionary, target: Dictionary, memory: ShipMemory) -> Dictionary:
	var command := _neutral_command()
	var danger := _avoidance_heading(observation, ship, memory)
	if danger.is_empty():
		if memory.recovering:
			_exit_recovery_if_clear(observation, ship, memory)
		if not memory.recovering:
			return _orbit(command, ship, target, memory)
	# Recovery or predicted danger: steer the latched/avoidance heading, reefed.
	var error := Definitions.wrap_angle(_recovery_heading(ship, memory, danger) - ship["heading"])
	command["turn"] = 0.0 if absf(error) <= Definitions.AI["turn_dead"] \
		else clampf(error / Definitions.AI["turn_gain"], -1.0, 1.0)
	command["toggle_sails"] = not ship["reefed"]  # reef through ordinary commands
	return command


## Predicted collision or boundary danger; returns a heading to steer or {} when clear.
func _avoidance_heading(observation: Dictionary, ship: Dictionary, memory: ShipMemory) -> Dictionary:
	var radius: float = Definitions.VESSELS[ship["vessel_id"]]["radius"]
	var bounds := Definitions.safe_bounds(radius).grow(-Definitions.AI["boundary_inset"])
	var velocity: Vector2 = Vector2.from_angle(ship["heading"]) * ship["speed"]
	var predicted_self: Vector2 = ship["position"] + velocity * Definitions.AI["look_ahead_s"]
	if not bounds.has_point(predicted_self):
		# Boundary danger wins: aim at the nearest point inside the deeper inset;
		# corners combine both inward axes.
		var deep := Definitions.safe_bounds(radius).grow(-Definitions.AI["recovery_inset"])
		var inward := Vector2(
			clampf(deep.get_center().x, deep.position.x, deep.end.x) - ship["position"].x,
			clampf(deep.get_center().y, deep.position.y, deep.end.y) - ship["position"].y)
		if inward == Vector2.ZERO:
			inward = Definitions.ARENA_SIZE / 2.0 - ship["position"]
		if inward == Vector2.ZERO:
			inward = Vector2.RIGHT
		return {"heading": inward.angle(), "kind": "boundary"}
	var ids: Array = observation["ships"].keys()
	ids.sort()
	for other_id in ids:
		if other_id == ship["id"]:
			continue
		var other: Dictionary = observation["ships"][other_id]
		if not other["active"]:
			continue
		var relative: Vector2 = other["position"] - ship["position"]
		if relative.length() < 1e-6:
			# Coincident centers: even ship ID heads east, odd west (chosen once by parity).
			return {"heading": 0.0 if int(ship["id"]) % 2 == 0 else PI, "kind": "ship", "id": other_id}
		var other_velocity: Vector2 = Vector2.from_angle(other["heading"]) * other["speed"]
		var closing: Vector2 = other_velocity - velocity
		var denom: float = closing.dot(closing)
		var t := 0.0 if denom < 0.001 else clampf(-relative.dot(closing) / denom, 0.0, Definitions.AI["look_ahead_s"])
		var other_radius: float = Definitions.VESSELS[other["vessel_id"]]["radius"]
		var predicted: Vector2 = relative + closing * t
		if predicted.length() < radius + other_radius + Definitions.AI["ship_clearance"] \
				or relative.length() <= radius + other_radius + Definitions.AI["contact_margin"]:
			# Steer away perpendicular, biased outward from the obstacle.
			var away: Vector2 = (ship["position"] - other["position"]).normalized()
			var perpendicular: Vector2 = away.orthogonal()
			var perpendicular_sign := 1.0 if int(ship["id"]) % 2 == 0 else -1.0
			var steer: Vector2 = (away + perpendicular * perpendicular_sign * Definitions.AI["avoid_bias"]).normalized()
			return {"heading": steer.angle(), "kind": "ship", "id": other_id}
	return {}


## Recovery heading latches; boundary danger or a newly threatening ship overrides it.
func _recovery_heading(ship: Dictionary, memory: ShipMemory, danger: Dictionary) -> float:
	if not memory.recovering:
		memory.recovering = true
		memory.recovery_started = _clock
		memory.recovery_heading = _inward_heading(ship)
		memory.recovery_obstacle = -1
	if not danger.is_empty():
		var obstacle: int = danger.get("id", -1)
		if danger["kind"] == "boundary" or obstacle != memory.recovery_obstacle:
			memory.recovery_heading = danger["heading"]
			memory.recovery_obstacle = obstacle
	return memory.recovery_heading


## Nearest safe heading pointing inside the deeper inset from the ship's position.
func _inward_heading(ship: Dictionary) -> float:
	var radius: float = Definitions.VESSELS[ship["vessel_id"]]["radius"]
	var deep := Definitions.safe_bounds(radius).grow(-Definitions.AI["recovery_inset"])
	var inward := Vector2(clampf(deep.get_center().x, deep.position.x, deep.end.x) - ship["position"].x,
		clampf(deep.get_center().y, deep.position.y, deep.end.y) - ship["position"].y)
	if inward == Vector2.ZERO:
		inward = Definitions.ARENA_SIZE / 2.0 - ship["position"]
	if inward == Vector2.ZERO:
		inward = Vector2.RIGHT
	return inward.angle()


## Exit only outside the boundary warning band, clear of every active ship and safe
## from newly predicted collisions; then reacquire the broadside side.
func _exit_recovery_if_clear(observation: Dictionary, ship: Dictionary, memory: ShipMemory) -> void:
	if _clock - memory.recovery_started < Definitions.AI["recovery_minimum_s"]:
		return
	var radius: float = Definitions.VESSELS[ship["vessel_id"]]["radius"]
	var warn := Definitions.safe_bounds(radius).grow(-Definitions.AI["boundary_inset"])
	if not warn.has_point(ship["position"]):
		return  # still inside the boundary warning band
	for other_id in observation["ships"]:
		var other: Dictionary = observation["ships"][other_id]
		if other_id == ship["id"] or not other["active"]:
			continue
		if ship["position"].distance_to(other["position"]) <= radius \
				+ Definitions.VESSELS[other["vessel_id"]]["radius"] + Definitions.AI["recovery_exit_separation"]:
			return
	if not _avoidance_heading(observation, ship, memory).is_empty():
		return  # a new obstacle threatens recovery: keep steering away
	memory.recovering = false
	memory.target_id = -1  # reacquire the broadside side against the live bearing


## Broadside-orbit steering. Returns the command with turn/sails decided.
func _orbit(command: Dictionary, ship: Dictionary, target: Dictionary, memory: ShipMemory) -> Dictionary:
	var u: Vector2 = target["position"] - ship["position"]
	var distance := u.length()
	if distance < 1e-6:
		return command  # coincident positions: stuck detection triggers recovery
	u /= distance
	var bearing := u.angle()
	if memory.target_id != target["id"]:
		memory.target_id = target["id"]
		memory.side = _choose_side(bearing, ship["heading"])
	# Keep the preferred side until recovery ends or the target changes.
	var tangent := Vector2(-u.y, u.x) if memory.side == "port" else Vector2(u.y, -u.x)
	var desired_radius: float = Definitions.AI["orbit_radius"][memory.goal[memory.side]]
	var radial: float = clampf((distance - desired_radius) / Definitions.AI["radial_gain"],
		-Definitions.AI["radial_clamp"], Definitions.AI["radial_clamp"])
	var desired_heading := (tangent + u * radial).angle()
	var error := Definitions.wrap_angle(desired_heading - ship["heading"])
	command["turn"] = 0.0 if absf(error) <= Definitions.AI["turn_dead"] \
		else clampf(error / Definitions.AI["turn_gain"], -1.0, 1.0)
	# Sail policy: reef on large errors, full sails when settled, otherwise retain.
	var want_reefed: bool = ship["reefed"]
	if absf(error) > Definitions.AI["reef_error"]:
		want_reefed = true
	elif absf(error) < Definitions.AI["full_sail_error"]:
		want_reefed = false
	command["toggle_sails"] = want_reefed != ship["reefed"]
	return command


## Port when turning to heading bearing+PI/2 is at least as close as bearing-PI/2.
func _choose_side(bearing: float, heading: float) -> String:
	var port_error := absf(Definitions.wrap_angle(bearing + PI / 2.0 - heading))
	var starboard_error := absf(Definitions.wrap_angle(bearing - PI / 2.0 - heading))
	return "port" if port_error <= starboard_error else "starboard"


## Per-side candidate ammo with hysteresis, cycle-command realization and fire gating.
func _select_ammo(command: Dictionary, observation: Dictionary, ship: Dictionary, target: Dictionary, memory: ShipMemory, dt: float) -> void:
	var distance: float = ship["position"].distance_to(target["position"])
	var target_vessel: Dictionary = Definitions.VESSELS[target["vessel_id"]]
	var own_vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
	var broadsides := {
		"port": ship["heading"] - PI / 2.0,
		"starboard": ship["heading"] + PI / 2.0,
	}
	var target_bearing: float = (target["position"] - ship["position"]).normalized().angle()
	for side in Definitions.SIDES:
		var observed: Dictionary = ship["sides"][side]
		var want := _candidate_ammo(distance, target, target_vessel, own_vessel)
		if memory.candidate[side] != want:
			memory.candidate[side] = want
			memory.candidate_age[side] = 0.0
		else:
			memory.candidate_age[side] += dt
		if memory.cycling[side]:
			# Finish the committed goal before reevaluation; suppress fire while cycling.
			if observed["ammo"] == memory.goal[side]:
				memory.cycling[side] = false
				memory.last_change[side] = _clock
			else:
				command["cycle_" + side] = true
				continue
		elif want != memory.goal[side] and memory.candidate_age[side] >= Definitions.AI["candidate_stable_s"] \
				and _clock - memory.last_change[side] >= Definitions.AI["switch_cooldown_s"]:
			memory.goal[side] = want
			memory.cycling[side] = true
			if observed["ammo"] != want:
				command["cycle_" + side] = true
				continue  # no fire on a cycling tick
		if observed["ammo"] != memory.goal[side]:
			continue  # drifted (e.g. reset by external cycling): re-sync before firing
		if memory.recovering:
			continue  # suppress firing during recovery
		var ammo_range: float = Definitions.AMMO[observed["ammo"]]["range"]
		var bearing_error := absf(Definitions.wrap_angle(target_bearing - broadsides[side]))
		if observed["ready"] >= 1 and distance <= ammo_range \
				and bearing_error <= Definitions.AI["fire_bearing"] \
				and not _ally_blocks_fire(observation, ship, target, side, ammo_range):
			command["fire_" + side] = true


## Shots fly straight off the beam, so the lane is the broadside from the current center
## (the gun spread stays inside the hull). Its pure swept-circle query checks only the
## current lane; allies that move after launch still take hits.
func _ally_blocks_fire(observation: Dictionary, ship: Dictionary, target: Dictionary, side: String, ammo_range: float) -> bool:
	var start: Vector2 = ship["position"]
	var broadside: float = ship["heading"] + (-PI / 2.0 if side == "port" else PI / 2.0)
	var end: Vector2 = start + Vector2.from_angle(broadside) * ammo_range
	var target_radius: float = Definitions.VESSELS[target["vessel_id"]]["radius"]
	var target_t := NavalSimulation.segment_circle(start, end, target["position"], target_radius)
	if target_t < 0.0:
		return false
	for other_id in observation["ships"]:
		var other: Dictionary = observation["ships"][other_id]
		if other_id == ship["id"] or not other["active"] or other["team"] != ship["team"]:
			continue
		var radius: float = Definitions.VESSELS[other["vessel_id"]]["radius"]
		var ally_t := NavalSimulation.segment_circle(start, end, other["position"], radius)
		if ally_t >= 0.0 and ally_t < target_t:
			return true
	return false


## Ordered candidate rules; distance alone never authorizes firing.
func _candidate_ammo(distance: float, target: Dictionary, target_vessel: Dictionary, own_vessel: Dictionary) -> String:
	if distance <= Definitions.AI["ammo_range_factor"] * Definitions.AMMO["grape"]["range"] \
			and (target["crew"] / target_vessel["crew"] <= Definitions.AI["grape_crew_fraction"]
				or target["crew"] / Definitions.AMMO["grape"]["damage"]
					<= target["hull"] / Definitions.AMMO["round"]["damage"]):
		return "grape"
	if distance <= Definitions.AI["ammo_range_factor"] * Definitions.AMMO["chain"]["range"] \
			and (target["sails"] / target_vessel["sails"] <= Definitions.AI["chain_sail_fraction"]
				or (target_vessel["full_speed"] > Definitions.AI["speed_ratio"] * own_vessel["full_speed"]
					and target["sails"] / target_vessel["sails"] > Definitions.AI["chain_healthy_sail_fraction"])):
		return "chain"
	return "round"


func _neutral_command() -> Dictionary:
	return {"turn": 0.0, "toggle_sails": false, "fire_port": false,
		"fire_starboard": false, "cycle_port": false, "cycle_starboard": false}
