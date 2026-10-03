extends RefCounted
## Phase 3 plan 03 task 4: snapshot ordering, interpolation, resync and once-only event release
## of the client-side battle mirror.

const SnapshotBuffer := preload("res://net/snapshot_buffer.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const DT := 1.0 / 60.0
const FIRST := NavalSimulation.FIRST_CAPTAIN_SHIP_ID


func run(t) -> bool:
	for test in [_test_interpolate, _test_reject, _test_hold, _test_resync, _test_events, _test_appear_disappear]:
		t.check(test.call(t) == true, "snapshot buffer: %s completed" % test.get_method())
	return true


func _ship(id: int, position: Vector2, heading := 0.0, hull := 100.0) -> Dictionary:
	var ship := NavalSimulation.make_ship(id, 0, "sloop", position, heading)
	ship["hull"] = hull
	return ship


func _snap(tick: int, ships: Array, projectiles := []) -> Dictionary:
	var by_id := {}
	for ship in ships:
		by_id[ship["id"]] = ship
	return {"battle_id": 7, "tick": tick, "elapsed": tick * DT, "wind_heading": 0.0, "preset_id": "duel_brig",
		"ships": by_id, "projectiles": projectiles}


func _proj(id: int, owner: int, position: Vector2) -> Dictionary:
	return {"id": id, "owner_id": owner, "ammo": "round", "position": position}


func _two_snapshots() -> Object:
	var buffer := SnapshotBuffer.new(7)
	buffer.push_snapshot(_snap(30, [_ship(FIRST, Vector2(0, 0), 3.0, 100.0)], [_proj(9, FIRST, Vector2(100, 0))]))
	buffer.push_snapshot(_snap(33, [_ship(FIRST, Vector2(30, 0), -3.0, 80.0)],
		[_proj(9, FIRST, Vector2(130, 0)), _proj(10, FIRST, Vector2(0, 50))]))
	return buffer


func _test_interpolate(t) -> bool:
	var buffer := SnapshotBuffer.new(7)
	t.check(buffer.mirror.battle_mode and buffer.battle_id == 7 and buffer.newest_tick == -1,
		"snapshot buffer: starts empty in battle mode")
	t.check(buffer.advance() == [], "snapshot buffer: advance before any snapshot is empty")
	buffer = _two_snapshots()
	buffer.sample(31.0)
	var ship: Dictionary = buffer.mirror.ships[FIRST]
	t.near(ship["position"].x, 10.0, 1e-4, "snapshot buffer: ship x interpolated")
	t.near(ship["position"].y, 0.0, 1e-4, "snapshot buffer: ship y interpolated")
	t.near(ship["heading"], lerp_angle(3.0, -3.0, 1.0 / 3.0), 1e-5, "snapshot buffer: heading takes the short way")
	t.near(ship["hull"], 100.0, 1e-6, "snapshot buffer: discrete fields come from the earlier snapshot")
	t.check(buffer.mirror.projectiles.size() == 1, "snapshot buffer: projectile not yet in snapshot a is absent")
	var p: Dictionary = buffer.mirror.projectiles[0]
	t.check(p["id"] == 9 and p["owner_id"] == FIRST and p["ammo"] == "round", "snapshot buffer: projectile identity kept")
	t.near(p["position"].x, 110.0, 1e-4, "snapshot buffer: projectile interpolated")
	t.check(p["direction"].is_equal_approx(Vector2(1, 0)), "snapshot buffer: direction from the two samples")
	t.near(buffer.mirror.elapsed, 30 * DT, 1e-6, "snapshot buffer: elapsed from a")
	t.check(buffer.mirror.preset_id == "duel_brig", "snapshot buffer: preset id mirrored")
	buffer.sample(33.0)
	t.near(buffer.mirror.ships[FIRST]["hull"], 80.0, 1e-6, "snapshot buffer: tick 33 shows the later snapshot")
	t.check(buffer.mirror.projectiles.size() == 2, "snapshot buffer: projectile 10 present at tick 33")
	buffer.sample(20.0)
	t.near(buffer.mirror.ships[FIRST]["position"].x, 0.0, 1e-4, "snapshot buffer: before the oldest holds the oldest")
	return true


func _test_reject(t) -> bool:
	var buffer := _two_snapshots()
	buffer.sample(33.0)
	var before: Dictionary = buffer.mirror.ships.duplicate(true)
	t.check(buffer.push_snapshot(_snap(31, [_ship(FIRST, Vector2(999, 0))])) == false, "snapshot buffer: older tick rejected")
	t.check(buffer.push_snapshot(_snap(33, [_ship(FIRST, Vector2(999, 0))])) == false, "snapshot buffer: duplicate tick rejected")
	var other := _snap(40, [_ship(FIRST, Vector2(999, 0))])
	other["battle_id"] = 8
	t.check(buffer.push_snapshot(other) == false, "snapshot buffer: other battle rejected")
	t.check(buffer.newest_tick == 33, "snapshot buffer: rejects leave newest_tick")
	buffer.sample(33.0)
	t.check(buffer.mirror.ships == before, "snapshot buffer: rejects leave the mirror")
	return true


func _test_hold(t) -> bool:
	var buffer := _two_snapshots()
	buffer.sample(33.0)
	var pose: Dictionary = buffer.mirror.ships.duplicate(true)
	buffer.sample(50.0)
	t.check(buffer.mirror.ships == pose, "snapshot buffer: past the newest holds the newest pose")
	var past := true
	for i in 40:
		buffer.advance()
		past = past and buffer.render_tick <= buffer.newest_tick
	t.check(past and buffer.render_tick == 33.0, "snapshot buffer: advance never passes newest_tick")
	t.check(buffer.mirror.ships == pose, "snapshot buffer: held mirror equals the newest pose")
	return true


func _test_resync(t) -> bool:
	var buffer := _two_snapshots()
	for i in 60:
		buffer.advance()
	t.check(buffer.render_tick == 33.0, "snapshot buffer: stalled render holds at newest")
	buffer.push_snapshot(_snap(buffer.newest_tick + 60, [_ship(FIRST, Vector2(5, 5))]))
	buffer.advance()
	t.check(buffer.render_tick == buffer.newest_tick - SnapshotBuffer.DELAY_TICKS, "snapshot buffer: large lag resyncs to newest - delay")
	# Normal catch-up: the first snapshot sets the delay, then one tick per advance.
	var fresh := SnapshotBuffer.new(7)
	fresh.push_snapshot(_snap(60, [_ship(FIRST, Vector2.ZERO)]))
	t.check(fresh.render_tick == 54.0, "snapshot buffer: first snapshot sets render_tick to tick - delay")
	fresh.advance()
	t.check(fresh.render_tick == 55.0, "snapshot buffer: render advances one tick per advance")
	return true


func _ev(tick: int, type: String, extra := {}) -> Dictionary:
	return {"tick": tick, "type": type}.merged(extra)


func _test_events(t) -> bool:
	var buffer := SnapshotBuffer.new(7)
	buffer.push_events([_ev(35, "splash", {"projectile_id": 1})])
	buffer.push_events([_ev(34, "a"), _ev(34, "b")])
	t.check(buffer.advance() == [], "snapshot buffer: nothing released before the first snapshot")
	buffer.push_snapshot(_snap(40, [_ship(FIRST, Vector2.ZERO)]))  # render_tick = 34
	var got := []
	for i in 4:
		got.append_array(buffer.advance())
	t.check(got.size() == 2 and got[0].size() == 2 and got[0][0]["type"] == "a" and got[0][1]["type"] == "b"
		and got[1].size() == 1 and got[1][0]["type"] == "splash", "snapshot buffer: batches ascending, in arrival order")
	t.check(buffer.advance() == [] and buffer.advance() == [], "snapshot buffer: events released once")
	# A late event comes out on the next advance.
	buffer.push_events([_ev(30, "late")])
	var late: Array = buffer.advance()
	t.check(late.size() == 1 and late[0][0]["type"] == "late", "snapshot buffer: late event released next advance")
	# Events are not released ahead of the render tick.
	buffer.push_events([_ev(40, "future")])
	t.check(buffer.render_tick == 40.0, "snapshot buffer: render held at the newest")
	buffer = SnapshotBuffer.new(7)
	buffer.push_snapshot(_snap(40, [_ship(FIRST, Vector2.ZERO)]))  # render_tick = 34
	buffer.push_events([_ev(38, "future")])
	var released := []
	var held := true
	for i in 3:  # render 35, 36, 37
		released.append_array(buffer.advance())
		held = held and released.is_empty() and floori(buffer.render_tick) < 38
	t.check(held, "snapshot buffer: an event ahead of floor(render_tick) is not released")
	released = buffer.advance()  # render 38
	t.check(buffer.render_tick == 38.0 and released.size() == 1 and released[0][0]["type"] == "future",
		"snapshot buffer: the event is released once render_tick reaches it")
	# Owner on hits; entries are consumed.
	buffer = SnapshotBuffer.new(7)
	buffer.push_snapshot(_snap(40, [_ship(FIRST, Vector2.ZERO)]))
	buffer.push_events([_ev(35, "shot", {"projectile_id": 9, "ship_id": FIRST, "direction": Vector2(0, 1)})])
	buffer.push_events([_ev(36, "hit", {"projectile_id": 9, "victim_id": 2}), _ev(36, "hit", {"projectile_id": 77, "victim_id": 2})])
	buffer.push_events([_ev(37, "splash", {"projectile_id": 9})])
	var all := []
	for i in 6:
		all.append_array(buffer.advance())
	t.check(all.size() == 3 and all[0][0]["type"] == "shot" and not all[0][0].has("owner_id"),
		"snapshot buffer: shot released unchanged")
	t.check(all[1][0].get("owner_id") == FIRST, "snapshot buffer: hit gets the shooter as owner_id")
	t.check(not all[1][1].has("owner_id"), "snapshot buffer: hit on an unknown projectile has no owner")
	t.check(not buffer._shots.has(9), "snapshot buffer: released hit/splash erases the shot")
	# Shot direction is the fallback for a projectile seen in one snapshot only.
	buffer = SnapshotBuffer.new(7)
	buffer.push_snapshot(_snap(30, [_ship(FIRST, Vector2.ZERO)], [_proj(9, FIRST, Vector2(5, 5))]))
	buffer.push_events([_ev(30, "shot", {"projectile_id": 9, "ship_id": FIRST, "direction": Vector2(0, 1)})])
	buffer.sample(30.0)
	t.check(buffer.mirror.projectiles[0]["direction"] == Vector2(0, 1), "snapshot buffer: shot direction used when alone")
	buffer = SnapshotBuffer.new(7)
	buffer.push_snapshot(_snap(30, [_ship(FIRST, Vector2.ZERO)], [_proj(9, FIRST, Vector2(5, 5))]))
	buffer.sample(30.0)
	t.check(buffer.mirror.projectiles[0]["direction"] == Vector2.ZERO, "snapshot buffer: unknown direction is zero")
	# Pushed events are copies.
	var source := _ev(50, "x", {"nested": [1]})
	buffer.push_events([source])
	source["nested"].append(2)
	t.check(buffer._pending[50][0]["nested"] == [1], "snapshot buffer: events are deep copies")
	return true


func _test_appear_disappear(t) -> bool:
	var buffer := SnapshotBuffer.new(7)
	buffer.push_snapshot(_snap(30, [_ship(FIRST, Vector2(0, 0)), _ship(FIRST + 1, Vector2(50, 0))]))
	buffer.push_snapshot(_snap(33, [_ship(FIRST, Vector2(30, 0)), _ship(FIRST + 2, Vector2(70, 0))]))
	buffer.sample(32.0)
	t.check(buffer.mirror.ships.has(FIRST + 1) and not buffer.mirror.ships.has(FIRST + 2),
		"snapshot buffer: leaving ship stays, joining ship waits")
	t.near(buffer.mirror.ships[FIRST + 1]["position"].x, 50.0, 1e-4, "snapshot buffer: leaving ship holds its last pose")
	buffer.sample(33.0)
	t.check(not buffer.mirror.ships.has(FIRST + 1) and buffer.mirror.ships.has(FIRST + 2),
		"snapshot buffer: ship leaves and appears at render 33")
	# advance prunes old snapshots but keeps the one at or before render_tick.
	buffer = _two_snapshots()  # render_tick starts at 24
	for i in 7:
		buffer.advance()  # render 31
	t.check(buffer._snapshots.size() == 2 and buffer._snapshots[0]["tick"] == 30, "snapshot buffer: keeps the snapshot at or before render")
	for i in 3:
		buffer.advance()
	t.check(buffer._snapshots.size() == 1 and buffer._snapshots[0]["tick"] == 33, "snapshot buffer: prunes older snapshots")
	return true
