extends RefCounted

const Presentation := preload("res://view/combat_presentation.gd")
const Bindings := preload("res://input_bindings.gd")

func _layout(control: Node) -> void:
	if control is Container:
		control.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in control.get_children():
		_layout(child)

func run(t) -> bool:
	var main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	main.arena_view.set_process(false)
	var hud = main.hud
	t.check(hud.size == main.get_viewport().get_visible_rect().size and hud.size.x >= 1280,
		"production HUD root uses the logical viewport before test resize")
	main.start_encounter("two_sloops", "frigate")
	_layout(hud)
	_layout(hud)
	t.check(hud.roster_row.size.x >= 1256 and hud.panels[3].get_global_rect().end.y <= hud.size.y,
		"production roster fills screen and lower navigation remains onscreen")
	for preset in ["duel_brig", "two_sloops"]:
		main.start_encounter(preset, "frigate")
		for canvas in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1080), Vector2(1280, 1024)]:
			hud.size = canvas
			_layout(hud)
			_layout(hud)
			var safe := Presentation.gameplay_rect(canvas)
			t.check(safe.size.x >= 1168 and safe.size.y >= 352, "central combat rectangle at %s" % canvas)
			var width: float = hud.panels[0].size.x
			for id in main.sim.ships:
				var panel: Control = hud.roster_cards[id].panel
				t.near(panel.size.x, width, 1.0, "equal ship card width at %s" % canvas)
	
			for panel in hud.panels:
				if not panel.visible:
					continue
				var rect: Rect2 = panel.get_global_rect()
				t.check(Rect2(hud.global_position, canvas).encloses(rect) and not rect.intersects(Rect2(hud.global_position + safe.position, safe.size)),
					"HUD panel fits outside shared combat rectangle at %s: %s" % [canvas, rect])
		var before: Vector2 = hud.panels[1].size
		main.sim.ships[2]["active"] = false
		main.sim.ships[2]["defeat_reasons"] = ["sails", "crew"]
		hud.refresh(main.sim)
		_layout(hud)
		t.check(hud.panels[1].visible and hud.panels[1].size == before and "SAILS" in hud.target_state_label.text,
			"disabled ship retains card width and explicit reasons")
	main.start_encounter("two_sloops", "frigate")
	# Legal long remaps with simultaneous reset/empty/escape-reset notices.
	var saved_events := {}
	for action in Bindings.DEFAULTS:
		saved_events[action] = InputMap.action_get_events(action)
	var keys: Dictionary = Bindings.default_keycodes()
	keys.fire_port = KEY_BRACKETLEFT
	keys.fire_starboard = KEY_BRACKETRIGHT
	keys.cycle_port = KEY_BACKSLASH
	keys.cycle_starboard = KEY_SEMICOLON
	Bindings.apply_keycodes(keys)
	hud.size = Vector2(1280, 720)
	hud.refresh(main.sim)
	for side in ["port", "starboard"]:
		main.sim.ships[1].weapons[side].ammo = "chain"
		main.sim.ships[1].weapons[side].loads.fill(0.0)
	main.sim.ships[1].crew = 1.0
	main.sim.escape_armed = true
	main.sim.escape_clear_ticks = 100
	hud.refresh(main.sim)
	main.sim.escape_clear_ticks = 0
	hud.consume_events([{"type": "empty", "ship_id": 1, "side": "port"},
		{"type": "empty", "ship_id": 1, "side": "starboard"}])
	hud.refresh(main.sim)
	_layout(hud)
	_layout(hud)
	var safe_rect := Presentation.gameplay_rect(hud.size)
	for panel in hud.panels.slice(3):
		if panel.visible:
			# The synchronous runner cannot flush deferred wrapping/minimum-size updates.
			# Observe content minima and the bottom anchor configuration directly.
			var min_size: Vector2 = panel.get_combined_minimum_size()
			var footer: Control = panel if panel.anchor_bottom == 1.0 else panel.get_parent()
			t.check(footer.anchor_bottom == 1.0 and footer.offset_bottom == -12,
				"lower panel maintains the configured bottom anchor and margin")
			var bottom: float = hud.size.y * footer.anchor_bottom + footer.offset_bottom
			var rect := Rect2(panel.global_position.x, bottom - min_size.y, min_size.x, min_size.y)
			t.check(Rect2(hud.global_position, hud.size).encloses(rect)
				and not rect.intersects(Rect2(hud.global_position + safe_rect.position, safe_rect.size)),
				"long remaps with all notices fit outside combat rectangle: %s" % rect)
	for side in ["port", "starboard"]:
		t.check(hud.ammo_labels[side].text.contains("LOAD RESET") and hud.feedback_labels[side].visible
			and hud.ammo_labels[side].get_theme_font_size("font_size") >= 20,
			"long prompts retain reset/empty feedback and readable text")
	t.check(hud.escape_status_label.text.begins_with("Pursuit resumed — progress reset."),
		"worst-case fixture includes escape reset guidance")
	for action in saved_events:
		InputMap.action_erase_events(action)
		for event in saved_events[action]:
			InputMap.action_add_event(action, event)
	main.start_encounter("two_sloops", "frigate")
	var view = main.arena_view
	t.check(view.marker_layer.layer < main.get_node("UI").layer, "combat markers render below menu overlays")
	t.check(view.combat_indicators_visible(), "combat markers shown while sailing")
	main.set_paused(true)
	t.check(not view.combat_indicators_visible(), "pause suppresses combat markers and readiness drawing")
	main.open_settings()
	t.check(not view.combat_indicators_visible(), "settings suppresses combat indicators")
	main.close_settings()
	main.set_paused(false)
	var ship: Dictionary = main.sim.ships[1]
	ship["weapons"]["port"]["loads"] = [1.0, .999, .5, 0.0, 1.0, 1.0, 0.0, 1.0]
	var before_sim: Dictionary = main.sim.ships.duplicate(true)
	for heading in [0.0, PI / 2, PI, -PI / 2]:
		ship["heading"] = heading
		for zoom in [.75, 1.1]:
			view.camera.zoom = Vector2.ONE * zoom
			var strips: Dictionary = view.readiness_geometry(main.sim, ship.position, Rect2(0, 0, 1280, 720))
			var port: Dictionary = strips.port
			var starboard: Dictionary = strips.starboard
			var actual_port := Vector2.from_angle(heading - PI / 2)
			t.check((port.dots[0].position - starboard.dots[0].position).dot(actual_port) > 0,
				"readiness follows actual port side at heading %.2f" % heading)
			t.check((port.dots[0].position - port.dots[7].position).dot(Vector2.from_angle(heading)) > 0,
				"gun index follows bow-to-stern order")
			t.near(port.dots[0].position.distance_to(port.dots[1].position), 9, .001, "dot spacing stays legible through zoom")
			t.check(port.count == "4/8" and not port.dots[1].ready and not port.dots[2].ready,
				"only fireable guns count as ready")
	ship.heading = before_sim[1].heading
	t.check(main.sim.ships == before_sim, "geometry leaves sim state unchanged")
	main.sim.result = {"outcome": "victory"}
	t.check(view.readiness_geometry(main.sim, ship.position, Rect2(0, 0, 1280, 720)).is_empty(), "result suppresses readiness")
	main.sim.result.clear()
	ship.active = false
	t.check(view.readiness_geometry(main.sim, ship.position, Rect2(0, 0, 1280, 720)).is_empty(), "defeated player suppresses readiness")
	t.check(main.get_window().min_size == Vector2i(1280, 720), "runtime minimum window dimensions")
	main.queue_free()
	return true
