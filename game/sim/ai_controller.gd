extends RefCounted
## Deterministic opposition AI. Maps a copied observation to ordinary commands;
## never touches the simulation, nodes, physics or input. Plan 03 fills steering,
## ammunition and recovery decisions; this skeleton owns the command contract.

const NavalSimulation := preload("res://sim/naval_simulation.gd")


## Reset clears every side goal/timer, target sample and recovery memory.
func reset() -> void:
	pass


## Commands keyed by ship ID. Only turn/toggle_sails/fire_*/cycle_* are ever set,
## booleans are edges for this tick alone, turn is clamped to [-1, 1].
func commands_for_tick(observation: Dictionary, _dt: float) -> Dictionary:
	var commands := {}
	var ids: Array = observation.get("ships", {}).keys()
	ids.sort()
	for id in ids:
		var ship: Dictionary = observation["ships"][id]
		if not ship.get("active", false) or ship.get("team") != NavalSimulation.TEAM_OPPOSITION:
			continue
		if not _has_target(observation, ship):
			continue  # no target or inactive opposition: no command
		commands[id] = _neutral_command()
	return commands


func _neutral_command() -> Dictionary:
	return {"turn": 0.0, "toggle_sails": false, "fire_port": false,
		"fire_starboard": false, "cycle_port": false, "cycle_starboard": false}


## True when any active ship on another team exists (this slice: the living player).
func _has_target(observation: Dictionary, ship: Dictionary) -> bool:
	for other_id in observation["ships"]:
		var other: Dictionary = observation["ships"][other_id]
		if other["active"] and other["team"] != ship["team"]:
			return true
	return false
