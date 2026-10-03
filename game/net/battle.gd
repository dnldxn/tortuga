extends RefCounted
## One server-side battle (Phase 3 plan 02): a battle-mode NavalSimulation plus its AI. No
## networking and no wall time. Membership guards here keep every queued op valid, because the
## sim push_errors on an invalid one. A captain gets one ship per battle, ever.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const AIController := preload("res://sim/ai_controller.gd")

var battle_id: int
var preset_id: String
var sim                # NavalSimulation (battle mode)
var ai
var tick := 0          # completed steps
var ship_of := {}      # captain_id -> ship_id (one per captain per battle, ever)
var captain_of := {}   # ship_id -> captain_id
var names := {}        # ship_id -> {"name", "slot"} (updated on reclaim)
var barred := {}       # captain_id -> true: defeated/escaped/abandoned here
var lingering := {}    # ship_id -> true from the queued linger until reclaim/removal/defeat
var pending_ops := []  # contract-A ops for the next step
var record_tape := false
var tape := []         # [{"commands", "ops"}] per step

var _next_ship_id := NavalSimulation.FIRST_CAPTAIN_SHIP_ID
var _reported := {}    # ship_id -> true once its outcome has been returned by advance()


func _init(id: int, preset: String) -> void:
	battle_id = id
	preset_id = preset
	sim = NavalSimulation.new()
	sim.reset_battle(preset)
	ai = AIController.new()


## Queues the join and returns the new ship id, or -1 (push_error) for a repeat captain or bad vessel.
func add_captain(captain_id: String, captain_name: String, slot: int, vessel_id: String) -> int:
	if ship_of.has(captain_id) or not Definitions.VESSELS.has(vessel_id):
		push_error("Battle.add_captain: rejected captain '%s' vessel '%s'" % [captain_id, vessel_id])
		return -1
	var ship_id := _next_ship_id
	_next_ship_id += 1
	ship_of[captain_id] = ship_id
	captain_of[ship_id] = captain_id
	names[ship_id] = {"name": captain_name, "slot": slot}
	pending_ops.append({"op": "add_captain", "ship_id": ship_id, "vessel_id": vessel_id})
	return ship_id


func linger(captain_id: String) -> void:
	if not has_active_ship(captain_id) or is_lingering(captain_id):
		return
	var ship_id: int = ship_of[captain_id]
	lingering[ship_id] = true
	pending_ops.append({"op": "linger", "ship_id": ship_id})


func reclaim(captain_id: String, captain_name: String, slot: int) -> void:
	if not is_lingering(captain_id):
		return
	var ship_id: int = ship_of[captain_id]
	lingering.erase(ship_id)
	names[ship_id] = {"name": captain_name, "slot": slot}
	pending_ops.append({"op": "reclaim", "ship_id": ship_id})


## Bars the captain at once; the sim removes the ship (outcome abandoned) on the next step.
func abandon(captain_id: String) -> void:
	if not has_active_ship(captain_id):
		return
	var ship_id: int = ship_of[captain_id]
	barred[captain_id] = true
	lingering.erase(ship_id)
	pending_ops.append({"op": "abandon", "ship_id": ship_id})


## Not barred, and either the join is still queued or the ship is present and active.
func has_active_ship(captain_id: String) -> bool:
	if barred.has(captain_id) or not ship_of.has(captain_id):
		return false
	var ship_id: int = ship_of[captain_id]
	return not sim.ships.has(ship_id) or sim.ships[ship_id]["active"]


func is_lingering(captain_id: String) -> bool:
	return ship_of.has(captain_id) and lingering.has(ship_of[captain_id]) and has_active_ship(captain_id)


## One fixed step. `captain_commands` (ship id -> command) overrides the AI's. Returns the
## outcomes first seen this step, sorted by ship id, with the post-step elapsed.
func advance(dt: float, captain_commands: Dictionary) -> Array:
	var commands: Dictionary = ai.commands_for_tick(sim.ai_observation(), dt)
	for id in captain_commands:
		commands[id] = captain_commands[id]
	var ops := pending_ops
	pending_ops = []
	if record_tape:
		tape.append({"commands": commands.duplicate(true), "ops": ops.duplicate(true)})
	sim.step(dt, commands, ops)
	tick += 1
	for ship_id in lingering.keys():
		if not sim.ships.has(ship_id) or not sim.ships[ship_id]["active"]:
			lingering.erase(ship_id)
	var fresh := []
	var ids: Array = sim.outcomes.keys()
	ids.sort()
	for ship_id in ids:
		if _reported.has(ship_id):
			continue
		_reported[ship_id] = true
		var outcome: Dictionary = sim.outcomes[ship_id]
		var captain_id: String = captain_of.get(ship_id, "")
		if outcome["outcome"] != "victory" and captain_id != "":
			barred[captain_id] = true
		fresh.append({"ship_id": ship_id, "captain_id": captain_id, "outcome": outcome["outcome"],
			"elapsed": outcome["elapsed"]})
	return fresh


func ai_left() -> int:
	var count := 0
	for id in sim.ships:
		var ship: Dictionary = sim.ships[id]
		if ship["team"] == NavalSimulation.TEAM_OPPOSITION and ship["active"]:
			count += 1
	return count


## Names of present, active captain ships (lingering included), by ship id.
func captain_names() -> Array:
	var ids := captain_of.keys().filter(func(id): return sim.ships.has(id) and sim.ships[id]["active"])
	ids.sort()
	return ids.map(func(id): return names[id]["name"])
