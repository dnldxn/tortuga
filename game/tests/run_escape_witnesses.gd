extends SceneTree
## Test-only escape witness runner (plan 04). Replays stored player command traces
## against the real simulation and real AI from an ordinary reset, and requires every
## duel preset x vessel case to end in "escaped" with operational survivors.
## Usage: godot --headless --path game --script res://tests/run_escape_witnesses.gd

const NavalSimulation := preload("res://sim/naval_simulation.gd")
const AIController := preload("res://sim/ai_controller.gd")
const Definitions := preload("res://sim/definitions.gd")

const FIXTURE := "res://tests/fixtures/escape_witnesses.json"
const DT := 1.0 / 60.0
const MAX_TICKS := 36000  # experiment limit (10 simulated minutes), not a gameplay timer
const CASE_KEYS := ["commands", "max_ticks", "preset_id", "vessel_id"]
const BOOL_KEYS := ["toggle_sails", "fire_port", "fire_starboard", "cycle_port", "cycle_starboard"]

var failures := 0


func _initialize() -> void:
	var cases = _load_cases()
	if cases != null:
		var seen := {}
		for c in cases:
			seen["%s/%s" % [c["preset_id"], c["vessel_id"]]] = true
			var first := _run_case(c, true)
			var second := _run_case(c, false)
			_check(not first.is_empty() and first == second, "%s/%s: repeat from reset is identical" % [c["preset_id"], c["vessel_id"]])
		for key in _matrix():
			_check(seen.has(key), "matrix case present: %s" % key)
		print("Escape witnesses: %d cases, %d failures" % [cases.size(), failures])
	quit(1 if failures > 0 else 0)


## Every non-practice preset x every vessel (9 now; plan 05's preset extends it to 12).
func _matrix() -> Array:
	var keys := []
	for preset_id in Definitions.PRESETS:
		if preset_id != "practice":
			for vessel_id in Definitions.VESSELS:
				keys.append("%s/%s" % [preset_id, vessel_id])
	return keys


func _check(ok: bool, label: String) -> bool:
	if not ok:
		failures += 1
		print("  FAIL: %s" % label)
	return ok


## Returns the validated case array, or null (with failures recorded) when malformed.
func _load_cases():
	var text := FileAccess.get_file_as_string(FIXTURE)
	if not _check(text != "", "fixture readable: %s" % FIXTURE):
		return null
	var data = JSON.parse_string(text)
	if not _check(data is Array, "fixture is a JSON array"):
		return null
	var ok := _check(data.size() == _matrix().size(), "fixture has exactly %d cases (got %d)" % [_matrix().size(), data.size()])
	var seen := {}
	for c in data:
		if not _check(c is Dictionary and _sorted_keys(c) == CASE_KEYS, "case has exactly keys %s" % [CASE_KEYS]):
			ok = false
			continue
		var key := "%s/%s" % [c["preset_id"], c["vessel_id"]]
		ok = _check(key in _matrix(), "case is a duel matrix cell: %s" % key) and ok
		ok = _check(not seen.has(key), "case is unique: %s" % key) and ok
		seen[key] = true
		ok = _check(_is_int(c["max_ticks"]) and c["max_ticks"] > 0 and c["max_ticks"] <= MAX_TICKS,
			"%s: max_ticks integer in 1..%d" % [key, MAX_TICKS]) and ok
		ok = _valid_commands(key, c["commands"], c["max_ticks"]) and ok
	return data if ok else null


func _valid_commands(key: String, commands, max_ticks) -> bool:
	if not _check(commands is Array, "%s: commands is an array" % key):
		return false
	var last := -1
	for record in commands:
		if not _check(record is Dictionary and _sorted_keys(record) == ["command", "tick"], "%s: record keys are tick/command" % key):
			return false
		var tick = record["tick"]
		if not _check(_is_int(tick) and int(tick) > last and tick < max_ticks,
				"%s: ticks are ordered, unique, nonnegative integers below max_ticks (%s)" % [key, tick]):
			return false
		last = int(tick)
		var command = record["command"]
		if not _check(command is Dictionary and not command.is_empty(), "%s@%d: command is a non-empty object" % [key, last]):
			return false
		for k in command:
			var v = command[k]
			var valid: bool = (k == "turn" and (v is float or v is int) and absf(v) <= 1.0) or (k in BOOL_KEYS and v is bool)
			if not _check(valid, "%s@%d: valid command field %s=%s" % [key, last, k, v]):
				return false
	return true


func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


func _is_int(v) -> bool:
	return (v is int or v is float) and v >= 0 and float(v) == floorf(v)


## Replays one trace; returns its metrics, or {} on failure (already reported).
func _run_case(c: Dictionary, report: bool) -> Dictionary:
	var key := "%s/%s" % [c["preset_id"], c["vessel_id"]]
	var sim = NavalSimulation.new()
	sim.reset(c["preset_id"], c["vessel_id"])
	var ai = AIController.new()
	var required: int = NavalSimulation.escape_ticks_required(DT)
	var records: Array = c["commands"]
	var next_record := 0
	var turn := 0.0
	var armed_tick := -1
	var recent := []  # per-tick minimum enemy distance, last `required` ticks
	for tick in int(c["max_ticks"]):
		var command := {"turn": turn}
		if next_record < records.size() and int(records[next_record]["tick"]) == tick:
			var recorded: Dictionary = records[next_record]["command"]
			turn = float(recorded.get("turn", turn))
			command["turn"] = turn
			for k in BOOL_KEYS:
				command[k] = recorded.get(k, false)
			next_record += 1
		# Same pre-step AI call path as main.advance_tick().
		var commands: Dictionary = ai.commands_for_tick(sim.ai_observation(), DT)
		commands[NavalSimulation.PLAYER_ID] = command
		sim.step(DT, commands)
		if not _check(_state_valid(sim), "%s@%d: finite state within safe bounds and track limits" % [key, tick]):
			return {}
		if armed_tick < 0 and sim.escape_armed:
			armed_tick = tick
		recent.append(_nearest_enemy(sim))
		if recent.size() > required:
			recent.pop_front()
		if not sim.result.is_empty():
			return _finish(key, sim, tick, armed_tick, recent, required, report)
	_check(false, "%s: no result within %d ticks" % [key, c["max_ticks"]])
	return {}


func _finish(key: String, sim, tick: int, armed_tick: int, recent: Array, required: int, report: bool) -> Dictionary:
	var outcome: String = sim.result["outcome"]
	if not _check(outcome == "escaped", "%s: outcome escaped (got %s at tick %d)" % [key, outcome, tick]):
		return {}
	var player: Dictionary = sim.ships[NavalSimulation.PLAYER_ID]
	var live := 0
	var tracks := []
	var ids: Array = sim.ships.keys()
	ids.sort()
	for id in ids:
		var ship: Dictionary = sim.ships[id]
		live += 1 if ship["active"] and ship["team"] != player["team"] else 0
		tracks.append("%d:%s h%.0f s%.0f c%.0f" % [id, ship["vessel_id"], ship["hull"], ship["sails"], ship["crew"]])
	var interval_min: float = recent.min()
	var ok := _check(recent.size() == required and interval_min > Definitions.ESCAPE_DISTANCE,
		"%s: every sample of the final %d-tick interval > %s (min %.1f)" % [key, required, Definitions.ESCAPE_DISTANCE, interval_min])
	ok = _check(player["hull"] > 0 and player["sails"] > 0 and player["crew"] > 0, "%s: player tracks positive" % key) and ok
	ok = _check(live >= 1, "%s: at least one enemy operational" % key) and ok
	if report:
		print("%s: escaped at tick %d (%.2f s), armed at tick %d, live enemies %d, final-interval min distance %.1f, tracks [%s]" % [
			key, tick, sim.elapsed, armed_tick, live, interval_min, ", ".join(tracks)])
	if not ok:
		return {}
	return {"tick": tick, "result": sim.result.duplicate(true), "armed": armed_tick, "min": interval_min,
		"ships": sim.ships.duplicate(true)}


func _nearest_enemy(sim) -> float:
	var player: Dictionary = sim.ships[NavalSimulation.PLAYER_ID]
	var nearest := INF
	for id in sim.ships:
		var other: Dictionary = sim.ships[id]
		if other["active"] and other["team"] != player["team"]:
			nearest = minf(nearest, player["position"].distance_to(other["position"]))
	return nearest


func _state_valid(sim) -> bool:
	for id in sim.ships:
		var ship: Dictionary = sim.ships[id]
		var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
		var p: Vector2 = ship["position"]
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(ship["heading"])):
			return false
		if not Definitions.safe_bounds(vessel["radius"]).grow(0.01).has_point(p):
			return false
		for track in ["hull", "sails", "crew"]:
			if ship[track] < 0.0 or ship[track] > vessel[track]:
				return false
	return true
