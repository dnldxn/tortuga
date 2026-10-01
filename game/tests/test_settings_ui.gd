extends RefCounted
## Settings menu on the real main scene: draft/apply/back, key capture, pause interaction.
## Input is injected with viewport.push_input (synchronous, same path as test_controller);
## Input.parse_input_event is queued/flushed across frames and this runner is synchronous.
## Synthetic events are not native/rendered evidence of OS key delivery or layout.
## Always deletes user://settings.cfg and restores InputMap gameplay events and the bus layout.

const Bindings := preload("res://input_bindings.gd")
const Settings := preload("res://settings.gd")
const Menu := preload("res://ui/settings_menu.gd")

const DT := 1.0 / 60.0
const CFG := "user://settings.cfg"

var t
var main
var menu


func run(runner) -> bool:
	t = runner
	_remove_cfg()
	Bindings.install_defaults()
	var saved_events := {}
	for action in Bindings.DEFAULTS:
		saved_events[action] = InputMap.action_get_events(action)
	var saved_layout := AudioServer.generate_bus_layout()

	main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	menu = main.settings_menu
	_test_startup()
	_test_selection_back()
	_test_keyboard_activation()
	_test_draft_controls_and_focus()
	_test_pause_flow()
	_test_defaults()
	_test_save_failure()
	main.free()
	_test_load_notice()

	_remove_cfg()
	for action in saved_events:
		InputMap.action_erase_events(action)
		for event in saved_events[action]:
			InputMap.action_add_event(action, event)
	AudioServer.set_bus_layout(saved_layout)
	t.check(Bindings.snapshot_keycodes() == Bindings.default_keycodes(), "default bindings restored for later suites")
	return true


# --- helpers ---

func _remove_cfg() -> void:
	var path := ProjectSettings.globalize_path(CFG)
	if DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(CFG):
		DirAccess.remove_absolute(path)


func _event(code: int, pressed: bool, physical := 0, echo := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = physical
	ev.pressed = pressed
	ev.echo = echo
	return ev


func _push(ev: InputEvent) -> void:
	main.get_viewport().push_input(ev)


func _send(code: int, pressed: bool, echo := false) -> void:
	_push(_event(code, pressed, 0, echo))


## Pressed then released, logical keycode only (physical_keycode = 0).
func press_key(code: int, physical := 0) -> void:
	_push(_event(code, true, physical))
	_push(_event(code, false, physical))


func _focus() -> Control:
	return main.get_viewport().gui_get_focus_owner()


func _snapshot() -> Dictionary:
	var sim = main.sim
	return {"ships": sim.ships.duplicate(true), "projectiles": sim.projectiles.duplicate(true),
		"elapsed": sim.elapsed, "next_projectile_id": sim.next_projectile_id, "result": sim.result.duplicate(true)}


func _gains() -> Array:
	var out := []
	for i in AudioServer.get_bus_count():
		out.append([AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)])
	return out


func _open_from_selection() -> void:
	main.selection.settings_button.grab_focus()
	main.selection.settings_button.pressed.emit()


# --- tests ---

func _test_startup() -> void:
	t.check(main.settings.values == main.settings.defaults() and main.settings.notice == "",
		"no settings file: defaults active, no notice")
	t.check(not main.selection.notice_label.visible, "no startup notice without a file problem")
	t.check(not menu.visible, "settings hidden at startup")
	t.check(main.selection.quit_button.focus_previous == main.selection.quit_button.get_path_to(main.selection.settings_button),
		"selection Settings precedes Quit in focus chain")
	t.check(main.pause_menu.return_button.focus_previous == main.pause_menu.return_button.get_path_to(main.pause_menu.settings_button),
		"pause Settings in focus chain")


func _test_selection_back() -> void:
	_open_from_selection()
	t.check(menu.visible and not main.selection.visible and main.mode == "selection", "selection -> settings overlay")
	t.check(menu.binding_buttons["turn_left"].has_focus(), "first row focused on open")
	t.check(menu.draft == main.settings.values and not is_same(menu.draft, main.settings.values), "draft is a copy")
	menu.binding_buttons["turn_left"].pressed.emit()  # mouse-style activation: nothing to wait for
	t.check(menu.capturing_action == "turn_left" and not menu.waiting_for_activation_release, "click starts capture")
	t.check(menu.status_label.text == "Press a key for Turn left. Escape cancels.", "capture prompt")
	t.check(menu.binding_buttons["turn_left"].text == "Turn left — press a key… (click to cancel)", "capturing row hints click cancels")
	press_key(KEY_J)
	t.check(menu.draft["bindings"]["turn_left"] == KEY_J and menu.capturing_action == "", "J captured into draft")
	t.check(Bindings.binding_label("turn_left") == "A", "draft edit does not touch InputMap")
	menu.back_button.pressed.emit()
	t.check(not menu.visible and main.selection.visible, "Back shows selection")
	t.check(Bindings.snapshot_keycodes()["turn_left"] == KEY_A and main.settings.values["bindings"]["turn_left"] == KEY_A,
		"Back discards: A active")
	t.check(main.selection.settings_button.has_focus(), "focus restored to invoking Settings button")
	t.check(main.mode == "selection" and main.sim.ships.is_empty(), "no encounter created")
	t.check(not FileAccess.file_exists(CFG), "open/back writes no file")


func _test_keyboard_activation() -> void:
	_open_from_selection()
	_send(KEY_ENTER, true)
	_send(KEY_ENTER, false)
	t.check(menu.capturing_action == "turn_left", "Enter on focused row starts capture")
	t.check(menu.draft["bindings"]["turn_left"] == KEY_A, "Enter never bound")
	# Capture begun while a key is still down waits for that key's release.
	menu.cancel_capture()
	_send(KEY_SPACE, true)
	menu.begin_capture("turn_left")
	t.check(menu.waiting_for_activation_release, "activation key still down: waiting for release")
	_send(KEY_SPACE, true, true)
	_send(KEY_SPACE, false)
	t.check(not menu.waiting_for_activation_release and menu.capturing_action == "turn_left"
		and menu.draft["bindings"]["turn_left"] == KEY_A, "activation press/echo/release ignored; still listening")
	# Gamepad input is swallowed while capturing (a joypad ui_accept must not reach the GUI).
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	_push(pad)
	t.check(main.get_viewport().is_input_handled() and menu.capturing_action == "turn_left"
		and menu.draft == main.settings.values and menu.status_label.text == Bindings.UNSUPPORTED_MESSAGE,
		"joypad button consumed while capturing: unsupported, still listening, draft unchanged")
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	t.check(menu.handle_capture(stick) and menu.capturing_action == "turn_left", "joypad motion consumed while capturing")
	pad.pressed = false
	_push(pad)
	_send(KEY_ESCAPE, true)
	_send(KEY_ESCAPE, false)
	t.check(menu.visible and menu.capturing_action == "", "Escape cancels capture only")
	menu.back()


func _test_draft_controls_and_focus() -> void:
	_open_from_selection()
	var gains := _gains()
	menu.sliders["master"].value = 40
	t.check(menu.sliders["master"].max_value == 100 and menu.sliders["master"].step == 1, "slider 0-100 step 1")
	t.near(menu.draft["audio"]["master"], 0.4, 1e-9, "slider edits draft")
	t.check(menu.percent_labels["master"].text == "40%", "percent label follows slider")
	t.check(main.settings.values["audio"]["master"] == 1.0 and _gains() == gains, "slider does not touch active audio")
	t.check(menu.sliders["effects"].value == 80 and menu.sliders["ambient"].value == 35, "sliders show active volumes")
	menu.mode_option.select(1)
	menu.mode_option.item_selected.emit(1)
	t.check(menu.draft["display_mode"] == "fullscreen" and main.settings.values["display_mode"] == "windowed",
		"mode option edits draft only")
	for button in [menu.defaults_button, menu.apply_button, menu.back_button]:
		t.check(button.is_inside_tree() and button.is_visible_in_tree(), "footer %s present" % button.text)
	t.check(menu.scroll.follow_focus, "scroll follows focus")
	var size: Vector2 = menu.get_child(1).get_child(0).get_combined_minimum_size()
	t.check(size.x <= 1280 and size.y <= 720, "settings panel fits 1280x720 (%s)" % size)
	# Tab order: rows -> sliders -> mode -> footer, wrapping.
	var order: Array = menu.binding_buttons.values() + menu.sliders.values() \
		+ [menu.mode_option, menu.defaults_button, menu.apply_button, menu.back_button]
	menu.binding_buttons["turn_left"].grab_focus()
	var seen := [_focus()]
	for i in order.size():
		press_key(KEY_TAB)
		seen.append(_focus())
	t.check(seen == order + [order[0]], "Tab cycles rows, sliders, mode, footer")
	_push(_shift_tab())
	t.check(_focus() == menu.back_button, "Shift+Tab goes back")
	menu.sliders["ambient"].grab_focus()
	press_key(KEY_RIGHT)
	t.check(menu.draft["audio"]["ambient"] > 0.35, "arrow adjusts focused slider")
	menu.back()
	t.check(main.settings.values["audio"]["ambient"] == 0.35, "Back discards slider edits")


func _shift_tab() -> InputEventKey:
	var ev := _event(KEY_TAB, true)
	ev.shift_pressed = true
	return ev


func _test_pause_flow() -> void:
	main.start_practice("sloop")
	press_key(KEY_Q)
	for i in 10:
		main.advance_tick()
	main.sim.ships[1]["hull"] -= 20.0
	t.check(not main.sim.projectiles.is_empty(), "damaged practice with shots in flight")
	main.set_paused(true)
	main.pause_menu.settings_button.grab_focus()
	main.pause_menu.settings_button.pressed.emit()
	t.check(menu.visible and not main.pause_menu.visible and main.mode == "paused", "pause -> settings overlay")
	var snap := _snapshot()
	for code in [KEY_Q, KEY_E, KEY_Z, KEY_C, KEY_R, KEY_W]:
		press_key(code)
	_send(KEY_D, true)
	for i in 120:
		main.advance_tick()
	t.check(_snapshot() == snap and main.mode == "paused", "fire/cycle/reset/held turn + 120 ticks change nothing")
	_send(KEY_D, false)

	# Conflict keeps listening; logical J / physical Q captures J.
	menu.binding_buttons["turn_left"].pressed.emit()
	press_key(KEY_Q)
	t.check(menu.status_label.text == "Already used by Fire port. Choose another key." and menu.capturing_action == "turn_left",
		"conflict shown, still listening")
	t.check(menu.draft["bindings"]["fire_port"] == KEY_Q and menu.draft["bindings"]["turn_left"] == KEY_A,
		"conflict changes nothing")
	press_key(KEY_J, KEY_Q)
	t.check(menu.draft["bindings"]["turn_left"] == KEY_J and menu.capturing_action == "", "logical J captured (physical Q ignored)")

	# Logical zero / physical J is rejected.
	menu.binding_buttons["turn_right"].pressed.emit()
	press_key(0, KEY_J)
	t.check(menu.status_label.text == Bindings.UNSUPPORTED_MESSAGE and menu.capturing_action == "turn_right"
		and menu.draft["bindings"]["turn_right"] == KEY_D, "logical zero rejected; draft unchanged")

	# Release / echo / modifier / chord commit nothing.
	_send(KEY_K, false)
	_send(KEY_K, true, true)
	press_key(KEY_SHIFT)
	press_key(KEY_CTRL)
	var chord := _event(KEY_K, true)
	chord.ctrl_pressed = true
	_push(chord)
	t.check(menu.status_label.text == Bindings.SINGLE_KEY_MESSAGE, "chord rejected")
	t.check(menu.capturing_action == "turn_right" and menu.draft["bindings"]["turn_right"] == KEY_D,
		"release/echo/modifier/chord commit nothing")
	menu.cancel_capture()

	# Apply saves, applies, refreshes prompts, stays open.
	menu.apply_button.pressed.emit()
	t.check(menu.visible and menu.status_label.text == "Settings saved", "Apply stays open with feedback")
	t.check(Bindings.binding_label("turn_left") == "J" and Bindings.snapshot_keycodes()["fire_port"] == KEY_Q,
		"J active, Q unchanged")
	var event: InputEventKey = InputMap.action_get_events("turn_left")[0]
	t.check(event.keycode == KEY_J and event.physical_keycode == 0, "rebuilt mapping is logical only")
	t.check("J/D steer" in main.pause_menu.bindings_label.text, "pause prompts refreshed")
	var reloaded = Settings.new()
	t.check(reloaded.load_settings() == OK and reloaded.values["bindings"]["turn_left"] == KEY_J
		and reloaded.values == main.settings.values, "J persisted")
	t.check(_snapshot() == snap and main.mode == "paused", "Apply does not resume or reset")

	# Mouse: clicking the capturing row cancels; focus loss cancels without closing/resuming.
	menu.binding_buttons["turn_left"].pressed.emit()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = menu.binding_buttons["turn_left"].get_global_rect().get_center()
	t.check(menu.handle_capture(click) and menu.capturing_action == "", "click on capturing row cancels")
	menu.binding_buttons["turn_left"].pressed.emit()
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.check(menu.capturing_action == "" and menu.visible and main.mode == "paused"
		and menu.draft["bindings"]["turn_left"] == KEY_J, "focus loss cancels capture only")

	# Escape while capturing cancels; next Escape is Back to pause; never resumes.
	menu.binding_buttons["cycle_port"].pressed.emit()
	press_key(KEY_ESCAPE)
	t.check(menu.visible and menu.capturing_action == "" and main.mode == "paused", "Escape cancels capture only")
	_send(KEY_Q, true)  # held fire/sails/reset across close + resume
	_send(KEY_W, true)
	_send(KEY_R, true)
	var resets := [0]
	var on_reset := func(): resets[0] += 1
	main.practice_started.connect(on_reset)
	press_key(KEY_ESCAPE)
	t.check(not menu.visible and main.pause_menu.visible and main.mode == "paused", "next Escape returns to pause")
	t.check(main.pause_menu.settings_button.has_focus(), "focus restored to pause Settings button")
	for i in 5:
		main.advance_tick()
	t.check(_snapshot() == snap, "still paused until Resume")
	main.pause_menu.resume_button.pressed.emit()
	main.advance_tick()
	t.check(main.mode == "sailing" and main.sim.events.filter(func(e): return e["type"] in ["shot", "fire_rejected"]).is_empty()
		and main.sim.ships[1]["reefed"] == snap["ships"][1]["reefed"], "no queued volley/sail toggle/reset after resume")
	t.near(main.sim.elapsed, snap["elapsed"] + DT, 1e-12, "resume advances one tick")
	t.check(resets[0] == 0 and main.sim.ships[1]["hull"] == snap["ships"][1]["hull"]
		and main.sim.next_projectile_id == snap["next_projectile_id"], "held R across resume: no reset (damage and shot ids kept)")
	main.practice_started.disconnect(on_reset)
	_send(KEY_Q, false)
	_send(KEY_W, false)
	_send(KEY_R, false)
	press_key(KEY_E)
	main.advance_tick()
	t.check(not main.sim.events.filter(func(e): return e["type"] == "shot" and e["side"] == "starboard").is_empty(),
		"fresh press fires")
	main.return_to_selection()


func _test_defaults() -> void:
	_open_from_selection()
	menu.defaults_button.pressed.emit()
	t.check(menu.status_label.text == "Defaults ready — Apply to save" and menu.draft == main.settings.defaults(),
		"Defaults fills draft")
	t.check(Bindings.binding_label("turn_left") == "J", "Defaults does not apply")
	menu.back_button.pressed.emit()
	t.check(main.settings.values["bindings"]["turn_left"] == KEY_J, "Back discards defaults")
	_open_from_selection()
	menu.defaults_button.pressed.emit()
	menu.apply_button.pressed.emit()
	var reloaded = Settings.new()
	t.check(reloaded.load_settings() == OK and reloaded.values == reloaded.defaults(), "exact defaults persisted")
	t.check(Bindings.snapshot_keycodes() == Bindings.default_keycodes(), "defaults active")
	menu.back()


func _test_save_failure() -> void:
	_remove_cfg()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CFG))  # a directory: save fails
	var values: Dictionary = main.settings.values.duplicate(true)
	var gains := _gains()
	_open_from_selection()
	menu.binding_buttons["turn_left"].pressed.emit()
	press_key(KEY_K)
	menu.sliders["effects"].value = 10
	menu.mode_option.select(1)
	menu.mode_option.item_selected.emit(1)
	t.check(menu.draft["display_mode"] == "fullscreen" and values["display_mode"] == "windowed", "draft mode differs before failing Apply")
	menu.apply_button.pressed.emit()
	t.check(menu.status_label.text == "Could not save settings. Changes were not applied; retry Apply.", "save failure feedback")
	t.check(main.settings.values == values and _gains() == gains and Bindings.snapshot_keycodes() == Bindings.default_keycodes(),
		"failed save leaves bindings/audio/mode unchanged")
	t.check(main.settings.values["display_mode"] == "windowed", "failed save keeps previous display mode")
	t.check(menu.visible and menu.draft["bindings"]["turn_left"] == KEY_K, "draft kept for retry")
	t.check(menu.back_button.is_visible_in_tree(), "Back reachable")
	menu.back_button.pressed.emit()
	t.check(not menu.visible and main.selection.visible, "Back closes after failure")
	_remove_cfg()


func _test_load_notice() -> void:
	var file := FileAccess.open(CFG, FileAccess.WRITE)
	file.store_string("[audio\nmaster=")  # deliberately truncated: expect a parse ERROR line
	file.close()
	main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	menu = main.settings_menu
	t.check(main.selection.notice_label.visible and main.selection.notice_label.text == Settings.LOAD_NOTICE,
		"load-fallback notice visible at startup")
	_open_from_selection()
	t.check(menu.status_label.text == Settings.LOAD_NOTICE, "notice shown on settings open")
	menu.back()
	main.free()
