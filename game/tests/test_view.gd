extends RefCounted
## Arena view tests: real main scene, physics disabled, view.sync() called directly.
## Headless: proves node/transform state, not what is visually rendered.

const Definitions := preload("res://sim/definitions.gd")
const ShipView := preload("res://view/ship_3d_view.gd")
const Presentation := preload("res://view/combat_presentation.gd")

var main
var view


func run(t) -> bool:
	_test_models(t)
	main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	view = main.arena_view
	view.set_process(false)
	_test_camera_config(t)
	_test_distance_angles(t)
	for vessel_id in Definitions.VESSELS:
		_test_vessel(t, vessel_id)
	_test_restart_snaps_camera(t)
	_test_return_and_switch(t)
	_test_wind_arrow(t)
	_test_cue_lifecycle(t)
	_test_target_marker(t)
	_test_two_enemy_framing(t)
	_test_condition_visuals(t)
	main.free()
	return true


func _ship_nodes() -> Array:
	return view.get_children().filter(func(n): return n.get_meta("ship_3d_view", false))


## The view keys 3D adapters by stable ship id; practice also has the target (id 2).
func _player_node() -> Node2D:
	return view._ships[main.sim.PLAYER_ID]


func _snapshot() -> Dictionary:
	var sim = main.sim
	return {"ships": sim.ships.duplicate(true), "projectiles": sim.projectiles.duplicate(true),
		"events": sim.events.duplicate(true), "elapsed": sim.elapsed, "wind_heading": sim.wind_heading,
		"selected_vessel_id": sim.selected_vessel_id, "result": sim.result.duplicate(true)}


func _test_models(t) -> void:
	t.check(ShipView.MODEL_SCENES.size() == Definitions.VESSELS.size()
		and Definitions.VESSELS.keys().all(func(id): return ShipView.MODEL_SCENES.has(id)),
		"3D presentation map covers every simulation vessel class")
	for id in Definitions.VESSELS:
		var resource = load("res://assets/ships/3d/%s.glb" % id)
		t.check(resource is PackedScene, "%s.glb loads as PackedScene" % id)
		if resource is PackedScene:
			var instance: Node = resource.instantiate()
			var meshes := _descendants_of_type(instance, "MeshInstance3D")
			t.check(meshes.size() >= 20, "%s.glb retains detailed 3D geometry" % id)
			t.check(meshes.size() <= 64, "%s.glb is batched for bounded draw calls" % id)
			t.check(_descendants_named(instance, "SailPivot_").size() == ShipView.TRIM_FACTORS[id].size(),
				"%s.glb exposes every animated sail pivot" % id)
			t.check(not _descendants_named(instance, "SailSurface_").is_empty(),
				"%s.glb exposes reefable sail cloth" % id)
			instance.free()


func _test_camera_config(t) -> void:
	var cam: Camera2D = view.camera
	t.check([cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom] == [-240, -240, 6240, 4440],
		"camera limits include 240 world-unit decoration")
	t.check(cam.zoom == Vector2.ONE * 2.0, "default camera zoom doubled to 2")
	t.check(not cam.position_smoothing_enabled, "camera uses only exponential manual smoothing")
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
	var colored_surfaces := 0
	for mesh in _descendants_of_type(_player_node().model_instance, "MeshInstance3D"):
		for surface in mesh.mesh.get_surface_count():
			if mesh.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR:
				colored_surfaces += 1
				t.check(mesh.get_active_material(surface).vertex_color_use_as_albedo,
					"%s: procedural hull/deck colors enabled in Godot" % vessel_id)
	t.check(colored_surfaces >= 2, "%s: hull and deck retain colored planks" % vessel_id)
	var active: Array = main.sim.ships.keys().filter(func(id): return main.sim.ships[id]["active"])
	var nodes := _ship_nodes()
	t.check(nodes.size() == active.size() and nodes.size() == 2, "%s: one ship node per active ship (player + target)" % vessel_id)
	var ship: Dictionary = main.sim.ships[main.sim.PLAYER_ID]
	var node: Node2D = _player_node()
	t.check(node.position == ship["position"], "%s: node position matches sim" % vessel_id)
	t.near(node.rotation, 0.0, 1e-5, "%s: 2D adapter stays fixed while 3D hull turns" % vessel_id)
	t.near(node.heading_pivot.rotation.y, -node.visual_yaw_for_heading(ship["heading"]), 1e-5,
		"%s: 3D yaw follows heading through the current projection" % vessel_id)
	t.check(absf(ship["heading"]) > 0.01, "%s: heading actually changed during test" % vessel_id)
	var radius: float = Definitions.VESSELS[vessel_id]["radius"]
	t.near(ShipView.DISPLAY_REFERENCE_WIDTH * node.display_sprite.scale.x, 2.0 * radius, 0.5,
		"%s: rendered model scale follows collision diameter" % vessel_id)
	t.check(node.model_instance is Node3D and not node.sail_pivots.is_empty() and not node.sail_surfaces.is_empty(),
		"%s: adapter owns model, rig pivots, and sail surfaces" % vessel_id)
	var camera_target := Vector3(0.0, ShipView.CAMERA_TARGET_Y[vessel_id], 0.0)
	var camera_offset: Vector3 = node.model_camera.position - camera_target
	var camera_angle := rad_to_deg(atan2(camera_offset.y, camera_offset.z))
	t.near(camera_angle, 70.0, 0.1, "%s: focus ship is viewed 70 degrees above horizontal" % vessel_id)
	var every_heading_fits := true
	var projected_records := []
	for distance in [0.0, 400.0, 800.0]:
		node.set_view_distance(distance)
		var origin_pixel: Vector2 = node.model_camera.unproject_position(Vector3.ZERO)
		var origin_world: Vector2 = node.display_sprite.to_global(origin_pixel - Vector2(ShipView.VIEWPORT_SIZE) * 0.5)
		t.check(origin_world.distance_to(node.global_position) < 0.001, "%s: distance %.0f keeps hull origin on sim position" % [vessel_id, distance])
		for cardinal in [0.0, PI / 2.0, PI, -PI / 2.0]:
			for wind_offset in [0.0, PI / 2.0, -PI / 2.0]:
				node.set_ship_state(cardinal, cardinal + wind_offset, 0.0, false, 1.0, 1.0)
				var projected := _projected_model_bounds(node)
				projected_records.append(projected)
				every_heading_fits = (every_heading_fits and projected.position.x >= -1.0
					and projected.position.y >= -1.0 and projected.end.x <= ShipView.VIEWPORT_SIZE.x + 1.0
					and projected.end.y <= ShipView.VIEWPORT_SIZE.y + 1.0)
	t.check(every_heading_fits, "%s: complete rig stays in frame at all camera angles and cardinal turns %s"
		% [vessel_id, projected_records])
	view.sync(main.sim)
	var previous_trim: float = node.sail_pivots[0].rotation.y
	main.sim.wind_heading += PI / 2.0
	view.sync(main.sim)
	t.check(not is_equal_approx(node.sail_pivots[0].rotation.y, previous_trim)
		and not is_zero_approx(node.sail_trim), "%s: sail rig rotates when wind direction changes" % vessel_id)
	var full: Vector3 = node.sail_surfaces[0].scale
	var full_top: float = node.sail_surfaces[0].position.y + node._sail_top_local_y[0] * full.y
	main._input(_key(KEY_W, true))
	main._input(_key(KEY_W, false))
	main.advance_tick()
	view.sync(main.sim)
	t.check(main.sim.ships[1]["reefed"] and node.sail_surfaces[0].scale.x < full.x
		and node.sail_surfaces[0].scale.y < full.y, "%s: reefing shrinks the 3D sail cloth" % vessel_id)
	var reefed_top: float = node.sail_surfaces[0].position.y + node._sail_top_local_y[0] * node.sail_surfaces[0].scale.y
	t.near(reefed_top, full_top, 1e-5, "%s: reefed cloth stays attached at its upper spar" % vessel_id)
	var before_motion: Vector3 = node.motion_pivot.rotation
	node.advance_motion(0.5)
	t.check(node.motion_pivot.rotation != before_motion and absf(node.motion_pivot.rotation.x) < deg_to_rad(1.0),
		"%s: speed drives sub-degree rocking" % vessel_id)
	t.check(view.camera.position.distance_to(main.sim.ships[1]["position"]) <= 160.0, "%s: camera bias bounded from player" % vessel_id)


func _test_distance_angles(t) -> void:
	main.start_practice("galleon")
	var focus: Vector2 = main.sim.ships[1]["position"]
	var near_ship = view._ships[1]
	for distance in [-10.0, 0.0, 200.0, 400.0, 600.0, 800.0, 1600.0]:
		main.sim.ships[2]["position"] = focus + Vector2(maxf(distance, 0.0), 0)
		var before := _snapshot()
		view.sync(main.sim)
		t.check(_snapshot() == before, "distance camera leaves simulation unchanged")
		t.near(near_ship.elevation_degrees, 70.0, 0.001, "player always has the overhead camera")
		var far_ship = view._ships[2]
		var expected: float = 70.0 if distance <= 0.0 else (30.0 if distance >= 800.0 else 70.0 - 40.0 * smoothstep(0.0, 800.0, distance))
		t.near(far_ship.elevation_degrees, expected, 0.001, "distant ship camera angle at %.0f" % distance)
		for heading in [PI / 4.0, -PI / 3.0]:
			far_ship.set_ship_state(heading, 0.0, 0.0, false, 1.0, 1.0)
			var origin: Vector2 = far_ship.model_camera.unproject_position(Vector3.ZERO)
			var bow: Vector2 = far_ship.model_camera.unproject_position(far_ship.heading_pivot.to_global(Vector3.RIGHT))
			t.check((bow - origin).normalized().dot(Vector2.from_angle(heading)) > 0.99999, "distance camera preserves the projected heading")
	main.spectate_id = 2
	view.sync(main.sim)
	t.near(view._ships[2].elevation_degrees, 70.0, 0.001, "spectating moves the near-camera focus")
	main.return_to_selection()


func _test_restart_snaps_camera(t) -> void:
	for i in 30:
		main.advance_tick()
	main.restart_practice()
	var spawn: Vector2 = Definitions.PRESETS["practice"]["player_position"]
	t.check(view.camera.position.distance_to(spawn) <= 160.0, "restart: camera bias bounded at spawn")
	t.check(view.camera.get_screen_center_position().distance_to(view.camera.position) < 1.0, "restart: smoothing snapped to fresh center")
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
	view.consume_events([{"type": "hit", "projectile_id": 999, "position": Vector2(1, 2), "track": "crew", "damage": 5}])
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
	t.check(on["offscreen"] == not Presentation.gameplay_rect(screen.size).has_point(view.get_canvas_transform() * target),
		"marker uses active canvas transform")
	main.sim.ships[2]["position"] = center + Vector2(-1200, -900)
	var upper_left: Dictionary = view.target_marker(center, main.sim.ships[2]["position"], screen)
	t.check(upper_left["offscreen"] and upper_left["position"].x < 640 and upper_left["position"].y < 360,
		"offscreen marker points toward upper-left target")


func _test_condition_visuals(t) -> void:
	main.start_practice("brig")
	main.sim.ships[2]["hull"] = 80.0
	main.sim.ships[2]["sails"] = 25.0
	view.sync(main.sim)
	var target: Node2D = view._ships[2]
	t.check(target.display_sprite.modulate != Color.WHITE, "damaged hull changes rendered model appearance")
	t.check(target._sail_material.albedo_color != ShipView.SAIL_FULL,
		"damaged sails change 3D sail material")


func _test_two_enemy_framing(t) -> void:
	main.start_encounter("two_sloops", "sloop")
	var sim = main.sim
	view.sync(sim)
	t.check(view._ships.has(2) and view._ships.has(3), "view has distinct nodes for both sloops")
	t.check(view._desired_camera_center(sim).distance_to(sim.ships[1]["position"]) <= 160.0, "camera center bias limited to 160")
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var center: Vector2 = sim.ships[1]["position"]
	sim.ships[2]["position"] = center + Vector2(2500, 0)
	sim.ships[3]["position"] = center + Vector2(2600, 0)
	var markers: Dictionary = view.enemy_markers(sim, center, screen)
	t.check(markers.has(2) and markers.has(3), "both offscreen enemies have markers")
	if markers.has(2) and markers.has(3):
		var safe := Presentation.gameplay_rect(screen.size)
		t.check(markers[2].distance_to(markers[3]) >= 24.0 and markers[2] == markers[2].clamp(safe.position, safe.end)
			and markers[3] == markers[3].clamp(safe.position, safe.end), "colliding markers separate 24 px and stay visible")
		for positions in [[center + Vector2(2500, 0), center + Vector2(2600, 32)],
			[center + Vector2(-2500, 0), center + Vector2(-2600, 32)],
			[center + Vector2(0, -2500), center + Vector2(32, -2600)],
			[center + Vector2(0, 2500), center + Vector2(32, 2600)],
			[center + Vector2(2500, -2500), center + Vector2(2600, -2600)],
			[center + Vector2(-2500, 2500), center + Vector2(-2600, 2600)]]:
			sim.ships[2]["position"] = positions[0]
			sim.ships[3]["position"] = positions[1]
			markers = view.enemy_markers(sim, center, screen)
			var a: Rect2 = view.marker_label_rect(sim, 2, markers[2], center, screen)
			var b: Rect2 = view.marker_label_rect(sim, 3, markers[3], center, screen)
			t.check(not a.intersects(b) and safe.encloses(a) and safe.encloses(b)
				and markers[2].distance_to(markers[3]) >= 24.0,
				"crowded %s edge keeps both measured labels visible and separated" % positions[0])
	sim.ships[2]["active"] = false
	view.sync(sim)
	t.check(not view.enemy_markers(sim, center, screen).has(2)
		and view.enemy_markers(sim, center, screen).has(3), "defeated enemy no longer has edge marker")
	t.check(view._ships[2].visible and view._ships[2].modulate.a < 1.0,
		"defeated enemy remains a subdued silhouette")
	t.check(view._desired_camera_center(sim).distance_to(center) <= 160.0,
		"camera follows player when remaining opponent is remote")
	main.start_encounter("duel_sloop", "sloop")
	view.sync(main.sim)
	t.check(not view._ships.has(3) and not view.enemy_markers(main.sim, center, screen).has(3),
		"switch to duel removes second sprite and marker")


func _count(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _count(child)
	return n


func _descendants_of_type(node: Node, type_name: String) -> Array:
	var found := []
	if node.is_class(type_name):
		found.append(node)
	for child in node.get_children():
		found.append_array(_descendants_of_type(child, type_name))
	return found


func _descendants_named(node: Node, prefix: String) -> Array:
	var found := []
	if node.name.begins_with(prefix):
		found.append(node)
	for child in node.get_children():
		found.append_array(_descendants_named(child, prefix))
	return found


func _projected_model_bounds(ship_view: Node2D) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for mesh_node in _descendants_of_type(ship_view.model_instance, "MeshInstance3D"):
		var mesh_resource: Mesh = mesh_node.mesh
		for surface in mesh_resource.get_surface_count():
			var arrays: Array = mesh_resource.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for point in vertices:
				var projected: Vector2 = ship_view.model_camera.unproject_position(mesh_node.to_global(point))
				low = low.min(projected)
				high = high.max(projected)
	return Rect2(low, high - low)


func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = pressed
	return ev
