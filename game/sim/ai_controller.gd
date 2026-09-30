extends RefCounted
## Deterministic opposition AI. Maps a copied observation to ordinary commands;
## never touches the simulation, nodes, physics or input. Steering pursues a
## broadside orbit of the living player; ammunition changes pass through the
## same cycle commands a player would issue, with hysteresis to avoid
## reload-cancel churn. All tuning lives in Definitions.AI.

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
			continue
		var target := _target_for(observation, ship)
		if target.is_empty():
			_memory.erase(id)  # no target or inactive opposition: no command
			continue
		if not _memory.has(id):
			_memory[id] = ShipMemory.new()
		var memory: ShipMemory = _memory[id]
		var command := _steer(observation, ship, target, memory)
		_select_ammo(command, observation, ship, target, memory, dt)
		commands[id] = command
	return commands


## The single active enemy of this ship's team (this slice: the living player).
func _target_for(observation: Dictionary, ship: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for other_id in observation["ships"]:
		var other: Dictionary = observation["ships"][other_id]
		if other["active"] and other["team"] != ship["team"]:
			if best.is_empty() or other["id"] < best["id"]:
				best = other
	return best


## Broadside-orbit steering. Returns a neutral command with turn/sails decided.
func _steer(observation: Dictionary, ship: Dictionary, target: Dictionary, memory: ShipMemory) -> Dictionary:
	var command := _neutral_command()
	var u: Vector2 = target["position"] - ship["position"]
	var distance := u.length()
	if distance < 1e-6:
		return command  # coincident positions: recovery (plan 03 task 4) owns this
	u /= distance
	var bearing := u.angle()
	if memory.target_id != target["id"]:
		memory.target_id = target["id"]
		memory.side = _choose_side(bearing, ship["heading"])
	# Keep the preferred side until recovery ends or the target changes (plan 03 task 4
	# may clear it; side survives across ticks here).
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
		var ammo_range: float = Definitions.AMMO[observed["ammo"]]["range"]
		var bearing_error := absf(Definitions.wrap_angle(target_bearing - broadsides[side]))
		if observed["ready"] >= 1 and distance <= ammo_range \
				and bearing_error <= Definitions.AI["fire_bearing"]:
			command["fire_" + side] = true


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
