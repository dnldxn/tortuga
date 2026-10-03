extends RefCounted
## Client-side buffer for one remote battle: orders 20 Hz snapshots and events, renders a read-only
## NavalSimulation mirror slightly in the past (interpolated), and releases each event once at its tick.
## No nodes, no network; the owner feeds it and calls advance() once per 60 Hz tick.

const NavalSimulation := preload("res://sim/naval_simulation.gd")
const DT := 1.0 / 60.0
const DELAY_TICKS := 6.0  # ~100 ms behind the newest snapshot: two snapshot intervals
const MAX_LAG_TICKS := 15.0  # farther behind than this resyncs to newest - DELAY_TICKS

var battle_id: int
var mirror = NavalSimulation.new()  # read model for views; never stepped
var render_tick := 0.0
var newest_tick := -1
var _snapshots: Array = []  # ascending by tick
var _pending: Dictionary = {}  # tick -> events in arrival order, not yet released
var _shots: Dictionary = {}  # projectile id -> {"owner_id", "direction"} until its hit/splash is released


func _init(for_battle: int) -> void:
	battle_id = for_battle
	mirror.battle_mode = true


## False (ignored) for another battle or a tick that is not newer than the newest stored one.
func push_snapshot(s: Dictionary) -> bool:
	var tick := int(s.get("tick", -1))
	if int(s.get("battle_id", -1)) != battle_id or tick <= newest_tick:
		return false
	if _snapshots.is_empty():
		render_tick = tick - DELAY_TICKS
	_snapshots.append(s.duplicate(true))
	newest_tick = tick
	return true


func push_events(events: Array) -> void:
	for raw in events:
		var event: Dictionary = raw.duplicate(true)
		_pending.get_or_add(int(event.get("tick", 0)), []).append(event)
		if event.get("type") == "shot":
			_shots[event.get("projectile_id")] = {"owner_id": event.get("ship_id"), "direction": event.get("direction", Vector2.ZERO)}


## One render tick: moves the mirror and returns the event batches (one Array per tick) now due.
func advance() -> Array:
	if _snapshots.is_empty():
		return []
	render_tick += 1.0
	if newest_tick - render_tick > MAX_LAG_TICKS:  # recovering from a stall or drift
		render_tick = newest_tick - DELAY_TICKS
	render_tick = minf(render_tick, newest_tick)  # hold at the newest; never extrapolate
	var batches := _release(floori(render_tick))
	sample(render_tick)
	_prune()  # keep the latest snapshot <= render_tick and everything after
	return batches


## Fills the mirror from the snapshots around `at` (a = last with tick <= at, oldest if none; b = the next).
func sample(at: float) -> void:
	if _snapshots.is_empty():
		return
	var ai := 0
	for i in _snapshots.size():
		if _snapshots[i]["tick"] <= at:
			ai = i
	var a: Dictionary = _snapshots[ai]
	var b: Dictionary = _snapshots[ai + 1] if ai + 1 < _snapshots.size() else {}
	var alpha := 0.0
	if not b.is_empty():
		alpha = clampf((at - a["tick"]) / float(b["tick"] - a["tick"]), 0.0, 1.0)
	var ships: Dictionary = a["ships"].duplicate(true)
	for id in ships:
		if b.is_empty() or not b["ships"].has(id):
			continue
		var from: Dictionary = ships[id]
		var to: Dictionary = b["ships"][id]
		from["position"] = from["position"].lerp(to["position"], alpha)
		from["heading"] = lerp_angle(from["heading"], to["heading"], alpha)
		from["speed"] = lerpf(from["speed"], to["speed"], alpha)
	var next_by_id := {}
	if not b.is_empty():
		for p in b["projectiles"]:
			next_by_id[p["id"]] = p
	var projectiles: Array = a["projectiles"].duplicate(true)
	for p in projectiles:
		var direction := Vector2.ZERO
		if next_by_id.has(p["id"]):
			var target: Vector2 = next_by_id[p["id"]]["position"]
			direction = (target - p["position"]).normalized()
			p["position"] = p["position"].lerp(target, alpha)
		elif _shots.has(p["id"]):
			direction = _shots[p["id"]]["direction"]
		p["direction"] = direction
	mirror.ships = ships
	mirror.projectiles = projectiles
	mirror.elapsed = a["elapsed"]
	mirror.wind_heading = a["wind_heading"]
	mirror.preset_id = a["preset_id"]


func _release(upto: int) -> Array:
	var ticks: Array = []
	for tick in _pending:
		if tick <= upto:
			ticks.append(tick)
	ticks.sort()
	var batches := []
	for tick in ticks:
		var batch: Array = _pending[tick]
		_pending.erase(tick)
		for event in batch:
			var type = event.get("type")
			if type == "hit" and _shots.has(event.get("projectile_id")):
				event["owner_id"] = _shots[event["projectile_id"]]["owner_id"]
			if type == "hit" or type == "splash":
				_shots.erase(event.get("projectile_id"))
		batches.append(batch)
	return batches


func _prune() -> void:
	var keep := 0
	for i in _snapshots.size():
		if _snapshots[i]["tick"] <= render_tick:
			keep = i
	_snapshots = _snapshots.slice(keep)
