extends RefCounted
## Arena view tests: real main scene, physics disabled, view.sync() called directly.
## Headless: proves node/transform state, not what is visually rendered.

const Definitions := preload("res://sim/definitions.gd")

var main
var view


func run(t) -> bool:
	_test_textures(t)
	main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	view = main.arena_view
	view.set_process(false)
	_test_camera_config(t)
	for vessel_id in Definitions.VESSELS:
		_test_vessel(t, vessel_id)
	_test_restart_snaps_camera(t)
	_test_return_and_switch(t)
	_test_wind_arrow(t)
	_test_cue_lifecycle(t)
	_test_target_marker(t)
	_test_condition_visuals(t)
	main.free()
	return true


func _ship_nodes() -> Array:
	return view.get_children().filter(func(n): return n is Sprite2D)


## The view keys sprites by stable ship id; practice also has the target (id 2).
func _player_node() -> Sprite2D:
	return view._ships[main.sim.PLAYER_ID]


func _snapshot() -> Dictionary:
	var sim = main.sim
	return {"ships": sim.ships.duplicate(true), "projectiles": sim.projectiles.duplicate(true),
		"events": sim.events.duplicate(true), "elapsed": sim.elapsed, "wind_heading": sim.wind_heading,
		"selected_vessel_id": sim.selected_vessel_id, "result": sim.result.duplicate(true)}


func _test_textures(t) -> void:
	var widths := {"sloop": 64, "brig": 80, "frigate": 96}
	for id in widths:
		var tex = load("res://assets/ships/%s.svg" % id)
		t.check(tex is Texture2D, "%s.svg loads as Texture2D" % id)
		t.check(tex is Texture2D and tex.get_width() == widths[id] and tex.get_height() == widths[id] / 2,
			"%s.svg is %dx%d" % [id, widths[id], widths[id] / 2])


func _test_camera_config(t) -> void:
	var cam: Camera2D = view.camera
	t.check([cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom] == [0, 0, 6000, 4200],
		"camera limits 0/0/6000/4200")
	t.check(cam.zoom == Vector2.ONE, "camera zoom 1")
	t.check(cam.position_smoothing_enabled and cam.position_smoothing_speed == 5.0, "camera smoothing speed 5")
	t.check(cam.ignore_rotation, "camera ignores rotation")
	t.check(not (cam.get_parent() is CanvasLayer) and main.hud.get_parent() is CanvasLayer, "UI on CanvasLayer, camera in world")


func _test_vessel(t, vessel_id: String) -> void:
	main.start_practice(vessel_id)
	main._input(_key(KEY_D, true))
	for i in 20:
		main.advance_tick()
	main._input(_key(KEY_D, false))
	var snap := _snapshot()
	view.sync(main.sim)
	t.check(_snapshot() == snap, "%s: view sync does not mutate sim" % vessel_id)
	var active: Array = main.sim.ships.keys().filter(func(id): return main.sim.ships[id]["active"])
	var nodes := _ship_nodes()
	t.check(nodes.size() == active.size() and nodes.size() == 2, "%s: one ship node per active ship (player + target)" % vessel_id)
	var ship: Dictionary = main.sim.ships[main.sim.PLAYER_ID]
	var node: Sprite2D = _player_node()
	t.check(node.position == ship["position"], "%s: node position matches sim" % vessel_id)
	t.near(node.rotation, ship["heading"], 1e-5, "%s: rotation equals heading" % vessel_id)
	t.check(absf(ship["heading"]) > 0.01, "%s: heading actually changed during test" % vessel_id)
	var radius: float = Definitions.VESSELS[vessel_id]["radius"]
	t.near(node.texture.get_width() * node.scale.x, 2.0 * radius, 0.5, "%s: displayed length = diameter" % vessel_id)
	t.near(node.texture.get_height() * node.scale.y, radius, 0.5, "%s: displayed beam = radius" % vessel_id)
	var patch: Node2D = node.get_node("Sails").get_child(0)
	var full := patch.scale
	main._input(_key(KEY_W, true))
	main._input(_key(KEY_W, false))
	main.advance_tick()
	view.sync(main.sim)
	t.check(main.sim.ships[1]["reefed"] and patch.scale.x < full.x and patch.scale.y < full.y,
		"%s: reefed sail patch smaller than full" % vessel_id)
	t.check(view.camera.position == main.sim.ships[1]["position"], "%s: camera targets player" % vessel_id)


func _test_restart_snaps_camera(t) -> void:
	for i in 30:
		main.advance_tick()
	main.restart_practice()
	var spawn: Vector2 = Definitions.PRESETS["practice"]["player_position"]
	t.check(view.camera.position == spawn, "restart: camera target at spawn")
	t.check(view.camera.get_screen_center_position().distance_to(spawn) < 1.0, "restart: smoothing reset to spawn")
	t.check(_player_node().position == spawn, "restart: player ship node at spawn")


func _test_return_and_switch(t) -> void:
	main.start_practice("frigate")
	view.sync(main.sim)
	var count := _count(main)
	main.return_to_selection()
	view.sync(main.sim)
	t.check(_ship_nodes().is_empty(), "selection: no ship nodes")
	main.start_practice("sloop")
	view.sync(main.sim)
	var nodes := _ship_nodes()
	t.check(nodes.size() == 2 and _player_node().get_meta("vessel_id") == "sloop" and view._ships[2].get_meta("vessel_id") == "brig",
		"switch vessel: player sloop node plus brig target node")
	for i in 10:
		main.return_to_selection()
		main.start_practice("frigate")
		view.sync(main.sim)
	t.check(_count(main) == count, "no leaked nodes after 10 return/start cycles")


func _test_wind_arrow(t) -> void:
	var arrow: Control = main.hud.wind_arrow
	t.check(arrow.draw.get_connections().size() == 1, "wind arrow draws via its draw signal")
	t.near(main.hud.wind_heading, main.sim.wind_heading, 1e-9, "wind arrow heading reads sim")


func _test_cue_lifecycle(t) -> void:
	main.start_practice("sloop")
	main.sim.ships[1]["heading"] = -PI / 2.0  # port points west; starboard points at brig
	main._input(_key(KEY_E, true))
	main._input(_key(KEY_E, false))
	main.advance_tick()
	t.check(view._cues.size() == 4 and view._cues[0]["type"] == "shot", "volley produces transient muzzle cues")
	t.check(main.sim.projectiles.size() == 4, "projectile travel represented by live sim state")
	var life: int = view._cues[0]["ticks"]
	main.set_paused(true)
	for i in 12:
		main.advance_tick()
	t.check(view._cues[0]["ticks"] == life, "pause freezes effect lifetime")
	main.set_paused(false)
	main.advance_tick()
	t.check(view._cues[0]["ticks"] == life - 1, "one resumed tick ages cues once")
	view.consume_events([{"type": "hit", "position": Vector2(1, 2), "track": "crew", "damage": 5}])
	t.check(view._cues.any(func(c): return c["type"] == "hit" and c["track"] == "crew"), "crew hit has a cue")
	main.restart_practice()
	t.check(view._cues.is_empty() and main.sim.projectiles.is_empty(), "reset clears cues and in-flight shots")


func _test_target_marker(t) -> void:
	main.start_practice("sloop")
	var center: Vector2 = main.sim.ships[1]["position"]
	var target: Vector2 = main.sim.ships[2]["position"]
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var off: Dictionary = view.target_marker(center, target + Vector2(1200, 0), screen)
	t.check(off["offscreen"] and off["position"].x <= 1280 and off["position"].x > 640,
		"distant target marker clamps to right edge toward target")
	var on: Dictionary = view.target_marker(center, target, screen)
	t.check(not on["offscreen"] and on["position"].distance_to(Vector2(1140, 360)) < 1.0,
		"near target marker lies at projected screen position")
	main.sim.ships[2]["position"] = center + Vector2(-1200, -900)
	var upper_left: Dictionary = view.target_marker(center, main.sim.ships[2]["position"], screen)
	t.check(upper_left["offscreen"] and upper_left["position"].x < 640 and upper_left["position"].y < 360,
		"offscreen marker points toward upper-left target")


func _test_condition_visuals(t) -> void:
	main.start_practice("brig")
	main.sim.ships[2]["hull"] = 80.0
	main.sim.ships[2]["sails"] = 25.0
	view.sync(main.sim)
	var target: Sprite2D = view._ships[2]
	t.check(target.modulate != Color.WHITE, "damaged hull changes sprite appearance")
	t.check(target.get_node("Sails").get_child(0).color != Color(0.96, 0.93, 0.84, 0.95),
		"damaged sails change canvas appearance")


func _count(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _count(child)
	return n


func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = pressed
	return ev
