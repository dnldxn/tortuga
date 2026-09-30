extends RefCounted
## Controller/UI tests: the real main scene in the runner's SceneTree, physics disabled,
## ticks driven manually. Injected events do not prove OS focus/key delivery.

const Bindings := preload("res://input_bindings.gd")
const Definitions := preload("res://sim/definitions.gd")

const DT := 1.0 / 60.0
const GUIDANCE := "Full sails: faster · Reefed: tighter turns · Into the wind is slow, but you can still turn."
const BANNER := "Sailing practice — no target yet."

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
	_test_repeat_cycles(t)
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
	}


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
	t.check(main.selection.sailing_button.has_focus(), "Sailing practice button focused initially")
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
	t.check(main.selection.sailing_button.has_focus(), "return focuses Sailing practice")
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
	t.check("Hull 100/100" in text and "Sails 70/70" in text and "Crew 60/60" in text, "HUD shows condition current/max")
	t.check("FULL SAILS" in text, "HUD shows full sails")
	t.check("Sailing speed" in text, "HUD shows speed label")
	t.check("Wind travels" in text and "east" in text, "HUD shows wind direction text")
	t.check(GUIDANCE in text and BANNER in text, "HUD guidance and banner exact")
	var binds := "%s/%s steer · %s sails · %s pause" % [Bindings.binding_label("turn_left"),
		Bindings.binding_label("turn_right"), Bindings.binding_label("toggle_sails"), Bindings.binding_label("pause")]
	t.check(binds in text, "HUD bindings built from binding_label")
	var arrow: Control = hud.find_child("WindArrow", true, false)
	t.check(arrow != null and arrow.custom_minimum_size.x >= 48, "WindArrow placeholder present")
	main.advance_tick()
	t.check(("Sailing speed %d" % roundi(_ship()["speed"])) in _all_text(hud), "HUD speed follows sim each tick")
	_tap(KEY_W)
	main.advance_tick()
	t.check("REEFED" in _all_text(hud), "HUD shows reefed")
	for control in [hud.bindings_label, main.selection.sailing_button, main.pause_menu.resume_button]:
		t.check(control.get_theme_font_size("font_size") >= 18, "font size >= 18 for %s" % control.name)


func _all_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	for child in node.get_children():
		out += _all_text(child)
	return out


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
