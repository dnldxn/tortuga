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
	_test_two_sloop_ui(t)
	_test_result_and_replay(t)
	_test_input_isolation(t)
	test_disabled_text(t)
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
	var stats: Dictionary = hud.target_stats
	t.check(stats["hull"][1].text == "160/160" and stats["sails"][1].text == "100/100" and stats["crew"][1].text == "90/90",
		"enemy block shows condition current/max")
	var distance := roundi(main.sim.ships[2]["position"].distance_to(main.sim.ships[1]["position"]))
	t.check(hud.target_state_label.text == "%d · Active" % distance, "enemy block shows distance and Active")
	main.set_paused(true)
	t.check("Sink the enemy" in _all_text(main.pause_menu), "duel guidance replaces practice guidance")
	main.set_paused(false)
	# Damage updates the final values.
	main.sim.ships[2]["hull"] = 80.0
	main.sim.ships[2]["sails"] = 50.0
	hud.refresh(main.sim)
	t.check(stats["hull"][1].text == "80/160" and stats["sails"][1].text == "50/100"
		and stats["hull"][0].value == 80.0 and stats["hull"][0].max_value == 160.0, "enemy condition follows sim damage")
	main.sim.ships[2]["active"] = false
	main.sim.ships[2]["defeat_reasons"] = ["sails"]
	hud.refresh(main.sim)
	t.check("SAILS" in _all_text(hud), "defeat reason replaces Active")
	main.start_encounter("duel_brig", "sloop")


func _test_two_sloop_ui(t) -> void:
	var sel = main.selection
	t.check(sel.duel_buttons.has("two_sloops"), "selection offers two-sloop preset")
	if not sel.duel_buttons.has("two_sloops"):
		return
	t.check(sel.duel_buttons["duel_frigate"].focus_neighbor_bottom == sel.duel_buttons["duel_frigate"].get_path_to(sel.duel_buttons["two_sloops"])
		and sel.duel_buttons["two_sloops"].focus_neighbor_bottom == sel.duel_buttons["two_sloops"].get_path_to(sel.multiplayer_button)
		and sel.multiplayer_button.focus_neighbor_bottom == sel.multiplayer_button.get_path_to(sel.settings_button)
		and sel.settings_button.focus_neighbor_bottom == sel.settings_button.get_path_to(sel.quit_button),
		"keyboard focus reaches fourth preset, Multiplayer, Settings, then Quit in visual order")
	sel.duel_buttons["two_sloops"].pressed.emit()
	sel.vessel_buttons["frigate"].button_pressed = true
	sel.start_button.pressed.emit()
	t.check(main.sim.preset_id == "two_sloops" and _ship()["vessel_id"] == "frigate"
		and main.sim.ships.size() == 3, "fourth preset starts with selected vessel and both opponents")
	var hud = main.hud
	hud.refresh(main.sim)
	var text := _all_text(hud)
	t.check("Sloop A" in text and "Sloop B" in text, "HUD names both stable sloop identities")
	for id in [2, 3]:
		var stats: Dictionary = hud.target_stats if id == 2 else hud.second_target_stats
		t.check(stats["hull"][1].text == "100/100" and stats["sails"][1].text == "70/70"
			and stats["crew"][1].text == "60/60", "Sloop %s has all current/max tracks" % ("A" if id == 2 else "B"))
	main.sim.ships[1]["position"] = Vector2(3000, 2100)
	main.sim.ships[1]["heading"] = 0.0
	main.sim.ships[2]["position"] = Vector2(3000, 2400)
	main.sim.ships[3]["position"] = Vector2(3000, 2600)
	hud.refresh(main.sim)
	main.sim.ships[2]["active"] = false
	main.sim.ships[2]["defeat_reasons"] = ["sails", "crew"]
	main.sim.ships[3]["hull"] = 40.0
	hud.refresh(main.sim)
	t.check("SAILS" in _all_text(hud) and "CREW" in _all_text(hud)
		and "1 of 2 enemies defeated" in _all_text(hud), "HUD retains both defeat reasons and combat notice")
	t.check("DISABLED" in hud.target_state_label.text and hud.second_target_stats["hull"][1].text == "40/100",
		"disabled status and surviving enemy damage stay in separate rows")
	main.sim.result = {"outcome": "victory", "elapsed": 12.0,
		"defeated": [{"ship_id": 2, "reason": "disabled", "disabled_by": ["sails", "crew"]},
			{"ship_id": 3, "reason": "sunk", "disabled_by": []}]}
	main.result_menu.show_result(main.sim)
	t.check("Sloop A" in main.result_menu.detail_label.text and "Sloop B" in main.result_menu.detail_label.text
		and "sails and crew" in main.result_menu.detail_label.text,
		"result reports both opponents and combined disable reasons")
	main.sim.result = {"outcome": "defeat", "elapsed": 13.0,
		"defeated": [{"ship_id": 1, "reason": "sunk", "disabled_by": []},
			{"ship_id": 2, "reason": "disabled", "disabled_by": ["sails", "crew"]}]}
	main.result_menu.show_result(main.sim)
	t.check("Sloop B" in main.result_menu.detail_label.text and "Active" in main.result_menu.detail_label.text,
		"result still identifies undefeated second opponent")
	main.result_menu.replay_button.pressed.emit()
	t.check(main.mode == "sailing" and main.sim.preset_id == "two_sloops" and main.sim.ships.size() == 3
		and main.sim.result.is_empty() and main.sim.events.is_empty() and main.sim.projectiles.is_empty()
		and main.sim.elapsed == 0.0 and not main.sim.escape_armed and main.sim.escape_clear_ticks == 0,
		"one-action replay resets both enemies and escape state")
	main.start_encounter("duel_sloop", "sloop")
	hud.refresh(main.sim)
	t.check(not hud.second_target_block.visible and "Sloop B" not in _all_text(hud)
		and "1 of 2 enemies defeated" not in _all_text(hud), "duel has no second-enemy residue")


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


## Disabled reasons read naturally in the result text.
func test_disabled_text(t) -> void:
	main.start_encounter("duel_brig", "sloop")
	main.sim.ships[2]["sails"] = 3.0
	main.sim.ships[2]["crew"] = 3.0
	for ammo in ["chain", "grape"]:
		main.sim.projectiles.append({"id": main.sim.next_projectile_id, "owner_id": 1, "ammo": ammo,
			"position": main.sim.ships[2]["position"] - Vector2(0, 10), "direction": Vector2.DOWN,
			"remaining_range": 300.0, "owner_cleared": true})
		main.sim.next_projectile_id += 1
	main.advance_tick()
	t.check("Enemy A (Brig) disabled: sails and crew exhausted." in main.result_menu.detail_label.text,
		"disabled result names both exhausted tracks")
	main.return_to_selection()
