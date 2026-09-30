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


func reset(new_preset_id: String, vessel_id: String) -> void:
	if not Definitions.PRESETS.has(new_preset_id):
		push_error("NavalSimulation.reset: unknown preset '%s'" % new_preset_id)
		return
	if not Definitions.VESSELS.has(vessel_id):
		push_error("NavalSimulation.reset: unknown vessel '%s'" % vessel_id)
		return
	var preset: Dictionary = Definitions.PRESETS[new_preset_id]
	var vessel: Dictionary = Definitions.VESSELS[vessel_id]
	preset_id = new_preset_id
	selected_vessel_id = vessel_id
	wind_heading = preset["wind_heading"]
	elapsed = 0.0
	projectiles = []
	events = []
	result = {}
	ships = {
		PLAYER_ID: {
			"id": PLAYER_ID,
			"team": TEAM_PLAYER,
			"vessel_id": vessel_id,
			"position": preset["player_position"],
			"heading": preset["player_heading"],
			"speed": 0.0,
			"reefed": false,
			"hull": vessel["hull"],
			"sails": vessel["sails"],
			"crew": vessel["crew"],
			"active": true,
		},
	}


func step(dt: float, commands: Dictionary) -> void:
	events.clear()
	var ids := ships.keys()
	ids.sort()
	for id in ids:
		var ship: Dictionary = ships[id]
		if ship["active"]:
			_sail(ship, commands.get(id, {}), dt)
	resolve_contacts()
	elapsed += dt


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
