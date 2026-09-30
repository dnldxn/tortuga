extends RefCounted
## Real-scene water wiring/lifecycle tests. Headless does not prove rendered pixels.

const Definitions := preload("res://sim/definitions.gd")


func run(t) -> bool:
	var main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	var view = main.arena_view
	view.set_process(false)
	var water = view.get_node_or_null("ReefGlass")
	t.check(water != null, "Reef Glass is installed in the real arena")
	if water == null:
		main.free()
		return true
	t.check(water.show_behind_parent, "water draws behind coast, combat cues and ships")
	t.check(water.material is ShaderMaterial, "water uses a shader material")
	t.check(water.material.shader.resource_path == "res://view/reef_glass.gdshader",
		"refined Reef Glass shader is bound")
	t.check(water.material.get_shader_parameter("arena_size") == Definitions.ARENA_SIZE,
		"water covers the world arena")
	main.advance_tick()
	t.near(water.animation_time, 0.0, 1e-9, "selection water stays still")
	main.start_practice("sloop")
	for i in 120:
		main.advance_tick()
	t.near(water.animation_time, 2.0 * Definitions.WATER["animation_speed"], 1e-6,
		"water follows fixed simulation ticks at the approved preview speed")
	var east_drift: Vector2 = water.drift
	t.near(east_drift.x, water.animation_time * Definitions.WATER["drift_speed"], 1e-6,
		"east wind drives waves east")
	t.near(east_drift.y, 0.0, 1e-9, "east wind has no north/south drift")
	var ships: Dictionary = main.sim.ships.duplicate(true)
	var elapsed: float = main.sim.elapsed
	view.sync(main.sim)
	view.camera.position += Vector2(300, 100)
	view.camera.zoom = Vector2.ONE * 0.65
	t.check(water.global_position == Vector2.ZERO and water.scale == Vector2.ONE,
		"camera movement and zoom do not move or rescale the world-anchored seabed")
	t.check(main.sim.ships == ships and main.sim.elapsed == elapsed,
		"water presentation does not mutate simulation")
	main.set_paused(true)
	var stopped: float = water.animation_time
	for i in 10:
		main.advance_tick()
		view._process(0.1)
	t.near(water.animation_time, stopped, 1e-9, "pause freezes water despite render frames")
	t.check(water.drift == east_drift, "pause freezes water drift")
	main.set_paused(false)
	main.advance_tick()
	t.check(water.animation_time > stopped, "resume advances water")
	main.restart_practice()
	t.near(water.animation_time, 0.0, 1e-9, "restart resets whitecap clock")
	t.check(water.drift == Vector2.ZERO, "restart resets surface drift")
	main.start_encounter("duel_frigate", "sloop")
	var wind := Vector2.from_angle(Definitions.PRESETS["duel_frigate"]["wind_heading"])
	t.check(water.material.get_shader_parameter("wind_direction").is_equal_approx(wind),
		"diagonal preset wind reaches shader with the HUD heading convention")
	main.advance_tick()
	t.check(water.drift.x > 0.0 and water.drift.y > 0.0,
		"southeast wind moves waves down and right")
	t.near(water.drift.x, water.drift.y, 1e-6, "45-degree wind has equal drift components")
	main.sim.wind_heading = PI / 2.0
	var before_turn: Vector2 = water.drift
	main.advance_tick()
	t.near(water.drift.x, before_turn.x, 1e-6, "wind change preserves accumulated east drift")
	t.check(water.drift.y > before_turn.y, "wind change continues drift south")
	main.sim.ships[2]["hull"] = 3.0
	main.sim.projectiles.append({"id": main.sim.next_projectile_id, "owner_id": 1, "ammo": "round",
		"position": main.sim.ships[2]["position"] - Vector2(0, 10), "direction": Vector2.DOWN,
		"remaining_range": 900.0, "owner_cleared": true})
	main.sim.next_projectile_id += 1
	main.advance_tick()
	t.check(main.mode == "result", "defeated opponent enters the real result flow")
	stopped = water.animation_time
	main.advance_tick()
	view._process(1.0)
	t.near(water.animation_time, stopped, 1e-9, "result screen freezes water")
	var previous_sim = main.sim
	main.return_to_selection()
	t.check(main.sim != previous_sim, "return replaces simulation")
	t.check(water.animation_time == 0.0 and water.drift == Vector2.ZERO,
		"return clears water clock and drift")
	t.check(water.material.get_shader_parameter("wind_direction") == Vector2.RIGHT,
		"water reads the replacement simulation wind")
	main.start_practice("brig")
	t.check(view.get_node("ReefGlass") == water, "replay reuses the water node/material")
	main.free()
	return true
