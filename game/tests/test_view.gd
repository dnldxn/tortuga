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
	main.free()
	return true


func _ship_nodes() -> Array:
	return view.get_children().filter(func(n): return n is Sprite2D)


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
	t.check(nodes.size() == active.size() and nodes.size() == 1, "%s: one ship node per active ship" % vessel_id)
	var ship: Dictionary = main.sim.ships[main.sim.PLAYER_ID]
	var node: Sprite2D = nodes[0]
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
	t.check(_ship_nodes()[0].position == spawn, "restart: ship node at spawn")


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
	t.check(nodes.size() == 1 and nodes[0].get_meta("vessel_id") == "sloop", "switch vessel: exactly one sloop node")
	for i in 10:
		main.return_to_selection()
		main.start_practice("frigate")
		view.sync(main.sim)
	t.check(_count(main) == count, "no leaked nodes after 10 return/start cycles")


func _test_wind_arrow(t) -> void:
	var arrow: Control = main.hud.wind_arrow
	t.check(arrow.draw.get_connections().size() == 1, "wind arrow draws via its draw signal")
	t.near(main.hud.wind_heading, main.sim.wind_heading, 1e-9, "wind arrow heading reads sim")


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
