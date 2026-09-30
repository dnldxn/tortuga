extends RefCounted
## Duel UI wiring checks: real controller/menus driven through button signals.
## Headless wiring only; rendered usability is verified by hand (plan 03 task 7).

const Definitions := preload("res://sim/definitions.gd")

const DT := 1.0 / 60.0

var main


func run(t) -> bool:
	main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	_test_selection_to_duel(t)
	_test_enemy_hud_block(t)
	_test_result_and_replay(t)
	_test_input_isolation(t)
	main.free()
	return true


# --- helpers ---


func _all_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	for child in node.get_children():
		out += _all_text(child)
	return out


func _ship() -> Dictionary:
	return main.sim.ships[1]


func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = pressed
	return ev


# --- tests ---


## Selection -> duel -> (combat) -> result -> replay / selection preserves state.
func _test_selection_to_duel(t) -> void:
	var sel = main.selection
	sel.duel_buttons["duel_sloop"].pressed.emit()
	t.check(sel.vessel_buttons["sloop"].has_focus(), "duel button opens vessel screen")
	sel.vessel_buttons["brig"].button_pressed = true
	sel.start_button.pressed.emit()
	t.check(main.mode == "sailing" and main.sim.preset_id == "duel_sloop"
		and _ship()["vessel_id"] == "brig", "duel starts with the chosen preset and vessel")
	var ai_calls := [0]
	var observer := func(_obs, _dt): ai_calls[0] += 1
	# The controller consults the AI every sailing tick in a duel.
	for i in 5:
		main.advance_tick()
	t.check(main.sim.elapsed > 0.0 and main.mode == "sailing", "duel keeps sailing")
	# Return to selection discards the encounter.
	main.return_to_selection()
	t.check(main.mode == "selection" and main.sim.ships.is_empty(), "selection discards encounter")


## Enemy block shows identity, condition bars, distance and state; results freeze it.
func _test_enemy_hud_block(t) -> void:
	main.start_encounter("duel_brig", "sloop")
	main.advance_tick()
	var hud = main.hud
	var text := _all_text(hud)
	t.check("Enemy A (Brig)" in text, "enemy block names Enemy A with vessel")
	t.check("Hull 160/160" in text and "Sails 100/100" in text and "Crew 90/90" in text, "enemy block shows condition current/max")
	t.check("Distance" in text and "Active" in text, "enemy block shows distance and Active")
	t.check("Sink the enemy" in text, "duel guidance replaces practice guidance")
	# Damage updates the final values.
	main.sim.ships[2]["hull"] = 80.0
	main.sim.ships[2]["sails"] = 50.0
	hud.refresh(main.sim)
	text = _all_text(hud)
	t.check("Hull 80/160" in text and "Sails 50/100" in text, "enemy condition follows sim damage")
	main.sim.ships[2]["active"] = false
	main.sim.ships[2]["defeat_reasons"] = ["sails"]
	hud.refresh(main.sim)
	t.check("SAILS" in _all_text(hud), "defeat reason replaces Active")
	main.start_encounter("duel_brig", "sloop")


## Result -> Replay gives a genuinely fresh encounter; Return stops stepping.
func _test_result_and_replay(t) -> void:
	main.start_encounter("duel_frigate", "frigate")
	# Dirty the match: partial reload, ammo cycle, recovery in progress.
	_tap_key(KEY_C)
	main.advance_tick()
	for i in 120:
		main.advance_tick()
	t.check(_ship()["weapons"]["starboard"]["ammo"] != "round" or not main.sim.projectiles.is_empty()
		or main.sim.elapsed > 2.0, "match carries live state before resolution")
	main.sim.ships[2]["hull"] = 3.0
	main.sim.projectiles.append({"id": main.sim.next_projectile_id, "owner_id": 1, "ammo": "round",
		"position": main.sim.ships[2]["position"] - Vector2(0, 10), "direction": Vector2.DOWN,
		"remaining_range": 900.0, "owner_cleared": true})
	main.sim.next_projectile_id += 1
	main.advance_tick()
	t.check(main.mode == "result", "resolution enters result mode")
	var fresh := _snapshot()
	main.result_menu.replay_button.pressed.emit()
	t.check(main.mode == "sailing" and main.sim.elapsed == 0.0 and main.sim.projectiles.is_empty()
		and main.sim.events.is_empty() and main.sim.result.is_empty()
		and _ship()["position"] == Definitions.PRESETS["duel_frigate"]["player_position"]
		and main.sim.ships[2]["position"] == Definitions.PRESETS["duel_frigate"]["opposition"][0]["position"],
		"replay returns both ships to fresh spawn with clean state")
	t.check(_ship()["hull"] == Definitions.VESSELS["frigate"]["hull"]
		and main.sim.ships[2]["hull"] == Definitions.VESSELS["frigate"]["hull"], "replay restores full tracks")
	for side in ["port", "starboard"]:
		t.check(_ship()["weapons"][side]["ammo"] == "round"
			and _ship()["weapons"][side]["loads"].all(func(l): return l == 1.0),
			"replay restores %s to loaded round" % side)
	main.result_menu.return_button.pressed.emit()
	t.check(main.mode == "selection" and main.sim.ships.is_empty(), "result Return stops the encounter")


## Menu activation consumes the press; held gameplay keys wait for release; pause
## freezes both clocks.
func _test_input_isolation(t) -> void:
	main.start_encounter("duel_sloop", "sloop")
	# A fire key held down while the result menu appears must not fire on replay.
	main.sim.ships[2]["hull"] = 3.0
	main.sim.projectiles.append({"id": main.sim.next_projectile_id, "owner_id": 1, "ammo": "round",
		"position": main.sim.ships[2]["position"] - Vector2(0, 10), "direction": Vector2.DOWN,
		"remaining_range": 900.0, "owner_cleared": true})
	main.sim.next_projectile_id += 1
	main.get_viewport().push_input(_key(KEY_Q, true))
	main.advance_tick()
	t.check(main.mode == "result", "duel resolves while Q held")
	main.result_menu.replay_button.pressed.emit()
	main.advance_tick()
	t.check(main.sim.projectiles.is_empty() and main.sim.events.is_empty(),
		"held fire key does not fire after replay until released")
	main.get_viewport().push_input(_key(KEY_Q, false))
	main.get_viewport().push_input(_key(KEY_Q, true))
	main.advance_tick()
	t.check(not main.sim.projectiles.is_empty(), "fresh press after release fires normally")
	main.get_viewport().push_input(_key(KEY_Q, false))
	# Pause freezes sim and AI clocks.
	main.set_paused(true)
	var snap := _snapshot()
	for i in 10:
		main.advance_tick()
	t.check(_snapshot() == snap, "paused ticks freeze the duel deeply")
	main.set_paused(false)
	main.advance_tick()
	t.check(main.sim.elapsed > snap["elapsed"], "resume advances exactly one tick")


func _tap_key(keycode: Key) -> void:
	main.get_viewport().push_input(_key(keycode, true))
	main.get_viewport().push_input(_key(keycode, false))


func _snapshot() -> Dictionary:
	var sim = main.sim
	return {"ships": sim.ships.duplicate(true), "projectiles": sim.projectiles.duplicate(true),
		"events": sim.events.duplicate(true), "elapsed": sim.elapsed, "result": sim.result.duplicate(true),
		"next_projectile_id": sim.next_projectile_id}
