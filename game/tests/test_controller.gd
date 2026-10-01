extends RefCounted
## Controller/UI tests: the real main scene in the runner's SceneTree, physics disabled,
## ticks driven manually. Injected events do not prove OS focus/key delivery.

const Bindings := preload("res://input_bindings.gd")
const Definitions := preload("res://sim/definitions.gd")

const DT := 1.0 / 60.0
const GUIDANCE := "Full sails: faster · Reefed: tighter turns · Into the wind is slow, but you can still turn."
const BANNER := "TARGET · Brig"

var main


func run(t) -> bool:
	_test_bindings(t)
	main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	_test_initial_selection(t)
	_test_start_via_menu(t)
	_test_toggle_input(t)
	_test_turn_input(t)
	_test_pause_discards_input(t)
	_test_held_across_transition(t)
	_test_focus_loss(t)
	_test_restart_and_return(t)
	_test_hud(t)
	_test_weapon_hud(t)
	_test_event_handoff(t)
	_test_fire_edges(t)
	_test_cycle_edges(t)
	_test_reset_key(t)
	_test_pause_discards_edges(t)
	_test_repeat_cycles(t)
	_test_reset_ignored_in_selection(t)
	_test_duel_encounter_wiring(t)
	_test_duel_selection_and_result(t)
	main.free()
	return true


# --- helpers ---

func _key(keycode: Key, pressed: bool, echo := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = pressed
	ev.echo = echo
	return ev


## Routed through the viewport so GUI focus / set_input_as_handled dispatch order is exercised.
func _send(keycode: Key, pressed: bool, echo := false) -> void:
	main.get_viewport().push_input(_key(keycode, pressed, echo))


func _tap(keycode: Key) -> void:
	_send(keycode, true)
	_send(keycode, false)


func _ship() -> Dictionary:
	return main.sim.ships[1]


func _snapshot() -> Dictionary:
	var sim = main.sim
	return {
		"ships": sim.ships.duplicate(true),
		"projectiles": sim.projectiles.duplicate(true),
		"events": sim.events.duplicate(true),
		"elapsed": sim.elapsed,
		"preset_id": sim.preset_id,
		"selected_vessel_id": sim.selected_vessel_id,
		"wind_heading": sim.wind_heading,
		"result": sim.result.duplicate(true),
		"next_projectile_id": sim.next_projectile_id,
	}


func _events(type: String, side := "") -> Array:
	return main.sim.events.filter(func(e): return e["type"] == type and (side == "" or e["side"] == side))


## Snapshot of a freshly reset sim for the given vessel (same fields as _snapshot()).
func _fresh(vessel_id: String) -> Dictionary:
	var saved = main.sim
	main.sim = saved.get_script().new()
	main.sim.reset("practice", vessel_id)
	var snap := _snapshot()
	main.sim = saved
	return snap


func _count_nodes(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _count_nodes(child)
	return n


func _connection_counts() -> Array:
	return [
		main.selection.get_signal_connection_list("start_requested").size(),
		main.selection.get_signal_connection_list("quit_requested").size(),
		main.pause_menu.get_signal_connection_list("resume_requested").size(),
		main.pause_menu.get_signal_connection_list("restart_requested").size(),
		main.pause_menu.get_signal_connection_list("return_requested").size(),
		main.selection.start_button.get_signal_connection_list("pressed").size(),
		main.pause_menu.resume_button.get_signal_connection_list("pressed").size(),
	]


# --- tests ---

func _test_bindings(t) -> void:
	Bindings.install_defaults()
	Bindings.install_defaults()
	var expected := {
		"turn_left": KEY_A, "turn_right": KEY_D, "toggle_sails": KEY_W,
		"fire_port": KEY_Q, "fire_starboard": KEY_E, "cycle_port": KEY_Z,
		"cycle_starboard": KEY_C, "reset_practice": KEY_R, "pause": KEY_ESCAPE,
	}
	for action in expected:
		var events := InputMap.action_get_events(action)
		t.check(events.size() == 1, "%s has exactly one event after two installs" % action)
		t.check(events.size() == 1 and events[0] is InputEventKey and events[0].keycode == expected[action],
			"%s default keycode" % action)
	t.check(Bindings.binding_label("turn_left") == "A", "turn_left label is A")
	t.check(Bindings.binding_label("pause") == "Escape", "pause label is Escape")
	# Labels read the live InputMap.
	InputMap.action_erase_events("turn_left")
	InputMap.action_add_event("turn_left", _key(KEY_J, false))
	t.check(Bindings.binding_label("turn_left") == "J", "label follows live remap")
	InputMap.action_erase_events("turn_left")
	Bindings.install_defaults()
	t.check(Bindings.binding_label("turn_left") == "A", "defaults restored into empty action")


func _test_initial_selection(t) -> void:
	t.check(main.mode == "selection", "starts in selection")
	t.check(main.selection.visible and not main.hud.visible and not main.pause_menu.visible,
		"only selection visible at start")
	t.check(main.selection.sailing_button.text == "Target practice", "mode button reads Target practice")
	t.check(main.selection.sailing_button.has_focus(), "Target practice button focused initially")
	for i in 10:
		main.advance_tick()
	t.check(main.sim.ships.is_empty() and main.sim.elapsed == 0.0, "selection ticks do not advance")
	_tap(KEY_W)
	_send(KEY_D, true)
	_send(KEY_ESCAPE, true)
	t.check(main.mode == "selection", "gameplay/pause keys ignored in selection")
	_send(KEY_D, false)
	_send(KEY_ESCAPE, false)
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.check(main.mode == "selection" and main.sim.ships.is_empty(), "selection focus loss creates no encounter")


func _test_start_via_menu(t) -> void:
	var sel = main.selection
	sel.sailing_button.pressed.emit()
	t.check(sel.vessel_buttons["sloop"].has_focus(), "vessel screen focuses selected vessel")
	sel.back_button.pressed.emit()
	t.check(sel.sailing_button.has_focus(), "Back returns to mode select")
	sel.sailing_button.pressed.emit()
	sel.vessel_buttons["brig"].button_pressed = true
	sel.start_button.pressed.emit()
	t.check(main.mode == "sailing", "Start enters sailing")
	t.check(_ship()["vessel_id"] == "brig", "Start uses chosen vessel")
	t.check(main.hud.visible and not sel.visible, "HUD shown, selection hidden while sailing")
	t.check(main.get_viewport().gui_get_focus_owner() == null, "no menu focus while sailing")
	main.advance_tick()
	t.near(main.sim.elapsed, DT, 1e-9, "sailing tick advances one fixed step")


func _test_toggle_input(t) -> void:
	var reefed: bool = _ship()["reefed"]
	_send(KEY_W, true)
	for i in 5:
		_send(KEY_W, true, true)
	main.advance_tick()
	t.check(_ship()["reefed"] != reefed, "W press + echoes toggles once")
	main.advance_tick()
	t.check(_ship()["reefed"] != reefed, "queued toggle cleared after consumption")
	_send(KEY_W, false)
	_tap(KEY_W)
	_tap(KEY_W)
	main.advance_tick()
	t.check(_ship()["reefed"] != reefed, "two presses in one tick cancel")
	_tap(KEY_W)
	_tap(KEY_W)
	_tap(KEY_W)
	main.advance_tick()
	t.check(_ship()["reefed"] == reefed, "three presses in one tick toggle once")


func _test_turn_input(t) -> void:
	_send(KEY_D, true)
	for i in 3:
		var heading: float = _ship()["heading"]
		main.advance_tick()
		t.check(_ship()["heading"] > heading, "held D turns starboard on tick %d" % i)
	_send(KEY_A, true)
	var before: float = _ship()["heading"]
	main.advance_tick()
	t.near(_ship()["heading"], before, 1e-9, "A+D cancel")
	_send(KEY_D, false)
	before = _ship()["heading"]
	main.advance_tick()
	t.check(_ship()["heading"] < before, "held A alone turns port")
	_send(KEY_A, false)
	before = _ship()["heading"]
	main.advance_tick()
	t.near(_ship()["heading"], before, 1e-9, "released keys stop turning")
	var pos: Vector2 = _ship()["position"]
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	main.get_viewport().push_input(mouse)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(300, 0)
	main.get_viewport().push_input(motion)
	before = _ship()["heading"]
	main.advance_tick()
	t.near(_ship()["heading"], before, 1e-9, "mouse does not steer")
	t.check(_ship()["position"] != pos, "ship keeps sailing")


func _test_pause_discards_input(t) -> void:
	_send(KEY_W, true)
	_send(KEY_D, true)
	_send(KEY_ESCAPE, true)
	_send(KEY_ESCAPE, false)
	t.check(main.mode == "paused", "Escape pauses")
	t.check(main.pause_menu.visible and main.pause_menu.resume_button.has_focus(), "pause menu shown with Resume focused")
	var snap := _snapshot()
	for i in 120:
		main.advance_tick()
	t.check(_snapshot() == snap, "120 paused ticks preserve deep snapshot")
	_send(KEY_W, false)
	_send(KEY_D, false)
	_send(KEY_ESCAPE, true)
	_send(KEY_ESCAPE, false)
	t.check(main.mode == "sailing", "Escape explicitly resumes")
	main.advance_tick()
	t.near(main.sim.elapsed, snap["elapsed"] + DT, 1e-9, "resume advances exactly one tick, no catch-up")
	t.near(_ship()["heading"], snap["ships"][1]["heading"], 1e-9, "no stale turn after resume")
	t.check(_ship()["reefed"] == snap["ships"][1]["reefed"], "no stale toggle after resume")


func _test_held_across_transition(t) -> void:
	_send(KEY_D, true)
	main.set_paused(true)
	main.set_paused(false)
	var heading: float = _ship()["heading"]
	main.advance_tick()
	t.near(_ship()["heading"], heading, 1e-9, "key held across pause does nothing")
	_send(KEY_D, true, true)
	main.advance_tick()
	t.near(_ship()["heading"], heading, 1e-9, "echo of stale held key does nothing")
	_send(KEY_D, false)
	_send(KEY_D, true)
	main.advance_tick()
	t.check(_ship()["heading"] > heading, "fresh press after release turns")
	_send(KEY_D, false)


func _test_focus_loss(t) -> void:
	_send(KEY_D, true)
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.check(main.mode == "paused", "focus loss pauses sailing")
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.check(main.mode == "paused", "focus-in does not resume")
	var snap := _snapshot()
	for i in 5:
		main.advance_tick()
	t.check(_snapshot() == snap, "stays frozen after focus-in")
	main.pause_menu.resume_button.pressed.emit()
	t.check(main.mode == "sailing", "Resume button resumes")
	main.advance_tick()
	t.near(_ship()["heading"], snap["ships"][1]["heading"], 1e-9, "no stale turn after focus loss")
	_send(KEY_D, false)


func _test_restart_and_return(t) -> void:
	var preset: Dictionary = Definitions.PRESETS["practice"]
	main.set_paused(true)
	main.pause_menu.restart_button.pressed.emit()
	t.check(main.mode == "sailing", "restart resumes sailing")
	t.check(_ship()["vessel_id"] == "brig", "restart keeps vessel")
	t.check(_ship()["position"] == preset["player_position"] and main.sim.elapsed == 0.0, "restart at fresh spawn")
	main.set_paused(true)
	main.pause_menu.return_button.pressed.emit()
	t.check(main.mode == "selection", "return enters selection")
	t.check(main.sim.ships.is_empty(), "return discards encounter state")
	t.check(main.selection.visible and not main.hud.visible and not main.pause_menu.visible, "return shows only selection")
	t.check(main.selection.sailing_button.has_focus(), "return focuses Target practice")
	main.advance_tick()
	t.check(main.sim.elapsed == 0.0, "selection after return does not tick")


func _test_hud(t) -> void:
	main.start_practice("sloop")
	var hud = main.hud
	var vessel: Dictionary = Definitions.VESSELS["sloop"]
	var snap := _snapshot()
	hud.refresh(main.sim)
	t.check(_snapshot() == snap, "HUD refresh does not mutate sim")
	var text := _all_text(hud)
	t.check(vessel["display_name"] in text, "HUD shows vessel name")
	var stats: Dictionary = hud.ship_stats
	t.check(stats["hull"][1].text == "100/100" and stats["sails"][1].text == "70/70" and stats["crew"][1].text == "60/60"
		and stats["hull"][0].value == 100.0 and stats["hull"][0].max_value == 100.0,
		"HUD shows condition bars and current/max")
	for icon in hud.find_children("*", "TextureRect", true, false):
		t.check(icon.texture != null, "HUD icon has a texture")
	t.check(hud.find_children("*", "TextureRect", true, false).size() >= 7, "HUD labels carry icons")
	t.check("FULL SAILS" in text, "HUD shows full sails")
	t.check("Wind E" in text, "HUD shows wind direction text")
	t.check(BANNER in text, "HUD target banner exact")
	t.check(GUIDANCE not in text and "steer" not in text, "help text is not on the in-play HUD")
	main.set_paused(true)
	var help := _all_text(main.pause_menu)
	var binds := "%s/%s steer · %s sails · %s pause" % [Bindings.binding_label("turn_left"),
		Bindings.binding_label("turn_right"), Bindings.binding_label("toggle_sails"), Bindings.binding_label("pause")]
	t.check(GUIDANCE in help and binds in help, "pause menu shows guidance and bindings from binding_label")
	var pause_size: Vector2 = main.pause_menu.get_child(1).get_combined_minimum_size()
	t.check(pause_size.x <= 1280 and pause_size.y <= 720, "pause menu with help fits 1280x720 (%s)" % pause_size)
	main.set_paused(false)
	var arrow: Control = hud.find_child("WindArrow", true, false)
	t.check(arrow != null and arrow.custom_minimum_size.x >= 32, "WindArrow placeholder present")
	main.advance_tick()
	t.check(hud.speed_label.text == "%d" % roundi(_ship()["speed"]), "HUD speed follows sim each tick")
	_tap(KEY_W)
	main.advance_tick()
	t.check("REEFED" in _all_text(hud), "HUD shows reefed")
	for control in [hud.name_label, hud.side_labels["port"], main.pause_menu.bindings_label,
			main.selection.sailing_button, main.pause_menu.resume_button]:
		t.check(control.get_theme_font_size("font_size") >= 18, "font size >= 18 for %s" % control.name)
	# Frigate has the widest broadside panels; corners must stay compact and off the centre.
	main.start_practice("frigate")
	var view := Rect2(0, 0, 1280, 720)
	var centre := Rect2(320, 180, 640, 360)
	var area := 0.0
	for panel in hud.panels:
		var sz: Vector2 = panel.get_combined_minimum_size()
		var anchor := Vector2(0.0 if panel.anchor_left == 0.0 else 1.0, 0.0 if panel.anchor_top == 0.0 else 1.0)
		var rect := Rect2(view.size * anchor + Vector2(12, 12) * (Vector2.ONE - anchor * 2.0) - sz * anchor, sz)
		area += sz.x * sz.y
		t.check(view.encloses(rect) and not rect.intersects(centre),
			"HUD corner %s (%s) stays on screen and off the centre" % [panel.get_index(), sz])
	t.check(area <= 0.28 * view.get_area(), "HUD panels cover <= 28%% of 1280x720 (%.1f%%)" % (100.0 * area / view.get_area()))


func _all_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	for child in node.get_children():
		out += _all_text(child)
	return out


func _test_weapon_hud(t) -> void:
	main.start_practice("sloop")
	var hud = main.hud
	var text := _all_text(hud)
	t.check("Port · Round · 4/4 ready" in text and "Starboard · Round · 4/4 ready" in text,
		"HUD shows independently loaded broadsides")
	var panel_of := func(label: Node) -> Node: return label.get_parent().get_parent().get_parent()
	t.check(panel_of.call(hud.side_labels["port"]) != hud.name_label.get_parent().get_parent()
		and panel_of.call(hud.side_labels["starboard"]) != hud.target_label.get_parent().get_parent()
		and panel_of.call(hud.side_labels["port"]) != panel_of.call(hud.side_labels["starboard"]),
		"each broadside occupies its own panel apart from ship conditions")
	t.check("OUTSIDE ARC" in text and "900" in text, "initial target is outside arc; range still shown")
	var visible_bars := func(side: String) -> Array:
		return hud.gun_bars[side].filter(func(bar): return bar.visible).map(func(bar): return bar.value)
	t.check(visible_bars.call("port") == [100.0, 100.0, 100.0, 100.0], "sloop shows four loaded port gun bars")
	main.set_paused(true)
	t.check("Round: hull / Chain: sails / Grape: crew" in _all_text(main.pause_menu)
		and "restarts that side" in _all_text(main.pause_menu), "ammo tracks and cycle reload cost explained on pause")
	main.set_paused(false)
	main.sim.ships[1]["weapons"]["port"]["ammo"] = "grape"
	main.sim.ships[1]["weapons"]["port"]["loads"] = [1.0, 0.5, 0.0, 0.25]
	hud.refresh(main.sim)
	t.check("Port · Grape · 1/4 ready" in _all_text(hud) and visible_bars.call("port")[1] == 50.0
		and "Starboard · Round · 4/4 ready" in _all_text(hud) and "Range 300" in _all_text(hud),
		"one side changes ammo/range/progress without affecting opposite broadside")
	main.sim.ships[1]["weapons"]["port"]["loads"] = [0.999, 0.0, 0.0, 0.0]
	hud.refresh(main.sim)
	t.check("Port · Grape · 0/4 ready" in hud.side_labels["port"].text
		and visible_bars.call("port")[0] == 99.0
		and visible_bars.call("starboard")[0] == 100.0,
		"near-ready gun displays below 100%; fully loaded opposite side shows 100%")
	# Leave enough headroom that this tick's reload cannot complete the gun before fire.
	main.sim.ships[1]["weapons"]["port"]["loads"][0] = 0.99
	_tap(KEY_Q)
	main.advance_tick()
	t.check(_events("fire_rejected", "port").size() == 1 and _events("shot", "port").is_empty(),
		"incomplete gun still cannot fire after a tick of reload")
	main.start_practice("sloop")
	for action in ["fire_port", "fire_starboard", "cycle_port", "cycle_starboard", "reset_practice"]:
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, _key(KEY_J, false))
	main.set_paused(true)
	var help := _all_text(main.pause_menu)
	t.check("J fire" in help and "J cycle" in help and "J reset" in help, "weapon prompts use live bindings")
	main.set_paused(false)
	for action in ["fire_port", "fire_starboard", "cycle_port", "cycle_starboard", "reset_practice"]:
		InputMap.action_erase_events(action)
	Bindings.install_defaults()
	main.sim.ships[2]["active"] = false
	main.sim.ships[2]["defeat_reasons"] = ["sails", "crew"]
	hud.refresh(main.sim)
	t.check("SAILS · CREW" in _all_text(hud) and "NO ACTIVE TARGET" in _all_text(hud),
		"defeated target reasons and inactive aim are visible")
	main.start_practice("sloop")


func _test_event_handoff(t) -> void:
	main.start_practice("sloop")
	_tap(KEY_Q)
	main.advance_tick()
	t.check(main.arena_view._cues.size() == 4, "one volley forwarded to view in same tick")
	t.check(main.hud._feedback.is_empty(), "successful fire does not report rejection")
	main.sim.events[0]["position"] = Vector2(-100, -100)
	t.check(main.arena_view._cues[0]["position"] != Vector2(-100, -100),
		"view owns event snapshot rather than aliasing sim event")
	_tap(KEY_Q)
	main.advance_tick()
	t.check("no loaded guns" in main.hud.feedback_labels["port"].text
		and "NO LOADED GUNS" in main.hud.aim_labels["port"].text,
		"rejected fire feedback and overriding status occupy separate labels")
	main.set_paused(true)
	var remaining: int = main.hud._feedback["port"]
	for i in 10:
		main.advance_tick()
	t.check(main.hud._feedback["port"] == remaining, "paused fire feedback does not expire")
	main.set_paused(false)
	for i in remaining:
		main.advance_tick()
	t.check(main.hud._feedback.is_empty() and "no loaded guns" not in _all_text(main.hud),
		"fire rejection expires after sailing ticks")


func _test_repeat_cycles(t) -> void:
	main.return_to_selection()
	var nodes := _count_nodes(main)
	var connections := _connection_counts()
	for i in 20:
		main.start_practice("frigate")
		main.set_paused(true)
		main.restart_practice()
		main.set_paused(true)
		main.return_to_selection()
	t.check(_count_nodes(main) == nodes, "20 cycles keep node count (%d)" % nodes)
	t.check(_connection_counts() == connections, "20 cycles keep signal connection counts")
	t.check(main.mode == "selection" and main.sim.ships.is_empty(), "cycles end cleanly in selection")


func _test_fire_edges(t) -> void:
	main.start_practice("sloop")
	_send(KEY_D, true)
	_send(KEY_Q, true)
	var heading: float = _ship()["heading"]
	main.advance_tick()
	t.check(_events("shot", "port").size() == 4 and _events("shot", "starboard").is_empty(), "Q press fires one port volley")
	t.check(_ship()["heading"] > heading, "steering held alongside fire still turns")
	_send(KEY_Q, true, true)
	var quiet := true
	for i in 300:  # past sloop gun 0's 4.55 s reload: a held key must not auto-fire
		main.advance_tick()
		quiet = quiet and _events("shot").is_empty() and _events("fire_rejected").is_empty()  # splashes are fine
	t.check(quiet, "held/echoed Q never refires, even after reload")
	_send(KEY_Q, false)
	_send(KEY_D, false)
	_tap(KEY_Q)
	_tap(KEY_Q)
	main.advance_tick()
	t.check(_events("shot", "port").size() == 1, "two presses before one tick fire once (only the reloaded gun)")
	main.advance_tick()
	t.check(_events("shot").is_empty() and _events("fire_rejected").is_empty(), "queued fire consumed and cleared")
	_tap(KEY_Q)
	main.advance_tick()
	t.check(_events("fire_rejected", "port").size() == 1 and _events("shot").is_empty(), "fresh Q with no loaded guns: rejection feedback")
	_tap(KEY_E)
	main.advance_tick()
	t.check(_events("shot", "starboard").size() == 4 and _events("shot", "port").is_empty(), "E fires one starboard volley")


func _test_cycle_edges(t) -> void:
	main.start_practice("brig")
	_send(KEY_Z, true)
	main.advance_tick()
	var port: Dictionary = _ship()["weapons"]["port"]
	t.check(port["ammo"] == "chain" and port["loads"].all(func(l): return l < 0.01), "Z cycles port to chain and restarts reload")
	t.check(_ship()["weapons"]["starboard"]["ammo"] == "round", "Z leaves starboard")
	_send(KEY_Z, true, true)
	for i in 5:
		main.advance_tick()
	t.check(_ship()["weapons"]["port"]["ammo"] == "chain", "held/echoed Z cycles only once")
	_send(KEY_Z, false)
	_tap(KEY_C)
	main.advance_tick()
	t.check(_ship()["weapons"]["starboard"]["ammo"] == "chain", "C cycles starboard")


func _test_reset_key(t) -> void:
	main.start_practice("frigate")
	var fresh := _fresh("frigate")
	var starts := [0]
	var on_start := func(): starts[0] += 1
	main.practice_started.connect(on_start)
	_send(KEY_D, true)
	_tap(KEY_Q)
	_tap(KEY_C)
	_tap(KEY_W)
	for i in 30:
		main.advance_tick()
	t.check(main.sim.next_projectile_id > 1 and not main.sim.projectiles.is_empty(), "dirty frigate practice with shots in flight")
	_tap(KEY_E)
	_tap(KEY_Z)
	_send(KEY_R, true)
	main.advance_tick()
	t.check(_snapshot() == fresh, "R resets to exact fresh state; fire/cycle in the same tick discarded")
	t.check(main.mode == "sailing" and _ship()["vessel_id"] == "frigate", "reset keeps sailing and the vessel")
	t.check(starts[0] == 1, "reset emits practice_started once (view resync)")
	_send(KEY_R, true, true)
	main.advance_tick()
	t.near(main.sim.elapsed, DT, 1e-12, "held/echoed R does not reset again; next tick advances")
	t.check(main.sim.events.is_empty() and main.sim.next_projectile_id == 1, "no stale fire after reset")
	t.near(_ship()["heading"], 0.0, 1e-12, "held D cleared by reset until pressed again")
	_send(KEY_R, false)
	_send(KEY_D, false)
	main.practice_started.disconnect(on_start)


func _test_pause_discards_edges(t) -> void:
	main.start_practice("sloop")
	_tap(KEY_Q)
	_tap(KEY_Z)
	_tap(KEY_R)
	main.set_paused(true)
	var snap := _snapshot()
	_tap(KEY_Q)
	_tap(KEY_C)
	_tap(KEY_R)
	for i in 5:
		main.advance_tick()
	t.check(main.mode == "paused" and _snapshot() == snap, "R/Q/C while paused change nothing")
	main.set_paused(false)
	main.advance_tick()
	var ship := _ship()
	t.near(main.sim.elapsed, snap["elapsed"] + DT, 1e-12, "resume: one tick, no deferred reset")
	t.check(main.sim.events.is_empty() and ship["weapons"]["port"]["ammo"] == "round"
		and ship["weapons"]["starboard"]["ammo"] == "round", "resume: no deferred fire/cycle")


func _test_reset_ignored_in_selection(t) -> void:
	main.return_to_selection()
	_tap(KEY_R)
	_tap(KEY_Q)
	main.advance_tick()
	t.check(main.mode == "selection" and main.sim.ships.is_empty(), "R/Q ignored in selection")
	main.start_practice("sloop")
	main.advance_tick()
	t.check(main.sim.events.is_empty() and main.sim.elapsed == DT, "selection presses not deferred into practice")
	main.return_to_selection()


## Plan 03: duels run the AI alongside player commands in the same fixed step.
func _test_duel_encounter_wiring(t) -> void:
	main.start_encounter("duel_sloop", "sloop")
	t.check(main.mode == "sailing" and main.sim.preset_id == "duel_sloop", "start_encounter enters sailing duel")
	t.check(_ship()["vessel_id"] == "sloop" and main.sim.ships[2]["vessel_id"] == "sloop", "duel spawns both sloops")
	var enemy_spawn: Vector2 = main.sim.ships[2]["position"]
	main.advance_tick()
	t.near(main.sim.elapsed, DT, 1e-9, "duel tick advances one fixed step")
	t.check(main.sim.ships[2]["position"] != enemy_spawn, "enemy sails under AI alongside player")
	# Player commands still honored in the merged command dictionary.
	_send(KEY_D, true)
	var heading: float = _ship()["heading"]
	main.advance_tick()
	t.check(_ship()["heading"] > heading, "player steering honored in duel")
	_send(KEY_D, false)
	# Restart keeps the duel (not practice) and resets the AI with the sim.
	for i in 30:
		main.advance_tick()
	main.restart_practice()
	t.check(main.sim.preset_id == "duel_sloop" and main.sim.elapsed == 0.0
		and main.sim.ships[2]["position"] == enemy_spawn, "restart returns the same duel to fresh spawn")
	# A resolved result freezes stepping (guard until plan 03 task 5 wires the menu).
	main.sim.result = {"outcome": "victory"}
	main.advance_tick()
	t.near(main.sim.elapsed, 0.0, 1e-9, "resolved result stops further stepping")
	main.sim.result = {}
	# Practice keeps its single-command path: the target never moves.
	main.start_practice("sloop")
	var target_spawn: Vector2 = main.sim.ships[2]["position"]
	for i in 60:
		main.advance_tick()
	t.check(main.sim.ships[2]["position"] == target_spawn, "practice target still never moves (no AI)")
	main.return_to_selection()


## Plan 03 task 5: duel menu entries, result overlay, replay and return flows.
func _test_duel_selection_and_result(t) -> void:
	main.return_to_selection()
	var sel = main.selection
	t.check(sel.duel_buttons["duel_sloop"].text == "Sloop duel"
		and sel.duel_buttons["duel_brig"].text == "Brig duel"
		and sel.duel_buttons["duel_frigate"].text == "Frigate duel", "selection offers the three duel labels")
	t.check("Sink the enemy" in _all_text(sel), "selection shows duel guidance")
	# Start a brig duel by keyboard-style button activation.
	sel.duel_buttons["duel_brig"].pressed.emit()
	sel.vessel_buttons["frigate"].button_pressed = true
	sel.start_button.pressed.emit()
	t.check(main.mode == "sailing" and main.sim.preset_id == "duel_brig"
		and main.sim.selected_vessel_id == "frigate", "duel started with chosen preset and vessel")
	# Resolve a victory via a lethal shot on the next tick.
	main.sim.ships[2]["hull"] = 3.0
	main.sim.projectiles.append({"id": main.sim.next_projectile_id, "owner_id": 1, "ammo": "round",
		"position": main.sim.ships[2]["position"] - Vector2(0, 10), "direction": Vector2.DOWN,
		"remaining_range": 900.0, "owner_cleared": true})
	main.sim.next_projectile_id += 1
	var shown := [0]
	main.mode_changed.connect(func(_m): shown[0] += 1)
	main.advance_tick()
	t.check(main.mode == "result" and main.result_menu.visible, "resolved duel enters result mode")
	t.check(main.result_menu.replay_button.has_focus(), "Replay button focused initially")
	t.check("Victory" in _all_text(main.result_menu) and "sunk" in _all_text(main.result_menu)
		and "Time" in _all_text(main.result_menu), "result shows outcome, reason and time")
	# Frozen while the menu is up; repeated frames do not re-show or resume stepping.
	var elapsed: float = main.sim.elapsed
	for i in 30:
		main.advance_tick()
	t.check(main.mode == "result" and main.sim.elapsed == elapsed, "result menu freezes the simulation")
	t.check(shown[0] == 1, "result mode entered exactly once over repeated frames")
	# Held gameplay keys do not fire from menu activation.
	_send(KEY_Q, true)
	main.result_menu.replay_button.pressed.emit()
	_send(KEY_Q, false)
	t.check(main.mode == "sailing" and main.sim.elapsed == 0.0
		and main.sim.ships[2]["hull"] > 0.0, "Replay restarts the duel fresh")
	main.advance_tick()
	t.check(main.sim.events.is_empty() and main.sim.projectiles.is_empty(),
		"menu activation admits no stale volley")
	# Restart with pending shot/cycle/recovery state also lands fresh.
	_send(KEY_E, true)
	main.advance_tick()
	t.check(not main.sim.projectiles.is_empty(), "shot in flight before restart")
	main.set_paused(true)
	main.pause_menu.restart_button.pressed.emit()
	t.check(main.mode == "sailing" and main.sim.elapsed == 0.0
		and main.sim.projectiles.is_empty() and main.sim.ships[2]["position"] == Definitions.PRESETS["duel_brig"]["opposition"][0]["position"],
		"pause Restart returns the same duel to fresh spawn")
	# Return to selection and change preset/vessel.
	main.set_paused(true)
	main.pause_menu.return_button.pressed.emit()
	t.check(main.mode == "selection" and main.sim.ships.is_empty(), "result/pause return stops the encounter")
	sel.duel_buttons["duel_frigate"].pressed.emit()
	sel.vessel_buttons["sloop"].button_pressed = true
	sel.start_button.pressed.emit()
	t.check(main.sim.preset_id == "duel_frigate" and main.sim.selected_vessel_id == "sloop",
		"return then start changes preset and vessel")
	main.return_to_selection()
