extends RefCounted
## Plan 04 deliberate escape: strict arming/countdown rules, combat precedence,
## reset lifecycle and pause/focus freezing. Isolated rule fixtures call
## _update_escape(DT) directly; fixture edits prove semantics, not reachability.

const NavalSimulation := preload("res://sim/naval_simulation.gd")
const Definitions := preload("res://sim/definitions.gd")

const DT := 1.0 / 60.0
const DUELS := ["duel_sloop", "duel_brig", "duel_frigate"]
const VESSELS := ["sloop", "brig", "frigate"]
const PLAYER_AT := Vector2(1000, 2100)

var required: int = NavalSimulation.escape_ticks_required(DT)


func run(t) -> bool:
	_test_constants(t)
	_test_unarmed_start(t)
	_test_arm_boundary(t)
	_test_clear_boundary(t)
	_test_countdown(t)
	_test_interrupt(t)
	_test_multi_enemy(t)
	_test_inactive(t)
	_test_practice(t)
	_test_precedence(t)
	_test_freeze(t)
	_test_three_ship_progress(t)
	_test_reset_lifecycle(t)
	_test_pause_focus(t)
	_test_ui(t)
	return true


# --- helpers ---


## Fresh duel with the player at PLAYER_AT and enemy 2 `distance` due east.
func _fixture(distance: float, preset_id := "duel_sloop"):
	var sim = NavalSimulation.new()
	sim.reset(preset_id, "sloop")
	sim.ships[1]["position"] = PLAYER_AT
	sim.ships[2]["position"] = PLAYER_AT + Vector2(distance, 0)
	return sim


func _add_enemy(sim, id: int, distance: float, active := true) -> void:
	sim.ships[id] = NavalSimulation.make_ship(id, NavalSimulation.TEAM_OPPOSITION, "sloop",
		PLAYER_AT + Vector2(distance, 0), 0.0)
	sim.ships[id]["active"] = active


func _ticks(sim, n: int) -> void:
	for i in n:
		sim._update_escape(DT)


## Separated duel: player heading west, enemy heading east, both idle (no commands).
func _separated(preset_id: String, vessel_id: String):
	var sim = NavalSimulation.new()
	sim.reset(preset_id, vessel_id)
	sim.ships[1]["position"] = PLAYER_AT
	sim.ships[1]["heading"] = PI
	sim.ships[2]["position"] = Vector2(3000, 2100)
	sim.ships[2]["heading"] = 0.0
	return sim


## Projectile already overlapping the victim: it hits on the next step.
func _lethal(sim, owner_id: int, victim_id: int, ammo: String) -> void:
	sim.projectiles.append({"id": sim.next_projectile_id, "owner_id": owner_id, "ammo": ammo,
		"position": sim.ships[victim_id]["position"] - Vector2(0, 10), "direction": Vector2.DOWN,
		"remaining_range": Definitions.AMMO[ammo]["range"], "owner_cleared": true})
	sim.next_projectile_id += 1


func _state(sim) -> Dictionary:
	return {"ships": sim.ships.duplicate(true), "projectiles": sim.projectiles.duplicate(true),
		"events": sim.events.duplicate(true), "elapsed": sim.elapsed, "result": sim.result.duplicate(true),
		"preset": sim.preset_id, "vessel": sim.selected_vessel_id, "wind": sim.wind_heading,
		"next_projectile_id": sim.next_projectile_id, "armed": sim.escape_armed,
		"clear_ticks": sim.escape_clear_ticks}


# --- rule fixtures ---


func _test_constants(t) -> void:
	var longest := 0.0
	for ammo in Definitions.AMMO.values():
		longest = maxf(longest, ammo["range"])
	t.check(Definitions.ESCAPE_DISTANCE > longest, "escape distance exceeds every weapon range")
	t.check(Definitions.ESCAPE_ARM_DISTANCE < Definitions.ESCAPE_DISTANCE, "arming is inside the escape distance")
	t.check(required == 480, "8 s at 1/60 is 480 qualifying ticks")
	var fresh = NavalSimulation.new()
	fresh.reset("duel_sloop", "sloop")
	t.check(not fresh.escape_armed and fresh.escape_clear_ticks == 0, "reset starts unarmed with zero progress")


func _test_unarmed_start(t) -> void:
	var sim = _fixture(1500)
	_ticks(sim, 600)
	t.check(not sim.escape_armed and sim.escape_clear_ticks == 0 and sim.result.is_empty(),
		"never approached: unarmed, no progress, no result after 600 ticks")


func _test_arm_boundary(t) -> void:
	for c in [[900.001, false], [900.0, true], [899.999, true]]:
		var sim = _fixture(c[0])
		_ticks(sim, 1)
		t.check(sim.escape_armed == c[1] and sim.escape_clear_ticks == 0,
			"distance %s arms=%s without a hit or shot" % [c[0], c[1]])


func _test_clear_boundary(t) -> void:
	for c in [[1399.999, 0], [1400.0, 0], [1400.001, 6]]:
		var sim = _fixture(c[0])
		sim.escape_armed = true
		sim.escape_clear_ticks = 5
		_ticks(sim, 1)
		t.check(sim.escape_clear_ticks == c[1], "armed at %s: clear ticks %d" % [c[0], c[1]])


func _test_countdown(t) -> void:
	var sim = _fixture(1500)
	sim.escape_armed = true
	_ticks(sim, required - 1)
	t.check(sim.result.is_empty() and sim.escape_clear_ticks == required - 1, "no result at 479 ticks")
	_ticks(sim, 1)
	t.check(sim.result.get("outcome") == "escaped" and sim.result.get("reason") == "pursuit_broken",
		"escaped at 480 ticks")
	t.check(sim.result.get("defeated") == [] and sim.result.has("elapsed"), "escape keeps elapsed and empty defeated list")


func _test_interrupt(t) -> void:
	var sim = _fixture(1500)
	sim.escape_armed = true
	_ticks(sim, 300)
	sim.ships[2]["position"] = PLAYER_AT + Vector2(1400, 0)
	_ticks(sim, 1)
	t.check(sim.escape_clear_ticks == 0 and sim.escape_armed, "one tick at 1400 resets progress, stays armed")
	sim.ships[2]["position"] = PLAYER_AT + Vector2(1500, 0)
	_ticks(sim, required - 1)
	t.check(sim.result.is_empty(), "interrupted countdown needs a fresh full interval")
	_ticks(sim, 1)
	t.check(sim.result.get("outcome") == "escaped", "full interval after reset escapes")


func _test_multi_enemy(t) -> void:
	var sim = _fixture(1600)
	_add_enemy(sim, 3, 850)
	_ticks(sim, 1)
	t.check(sim.escape_armed, "any nearby active enemy arms")
	for order in [[2, 3], [3, 2]]:
		var m = _fixture(0)
		m.ships.clear()
		m.ships[1] = NavalSimulation.make_ship(1, NavalSimulation.TEAM_PLAYER, "sloop", PLAYER_AT, 0.0)
		for id in order:
			_add_enemy(m, id, 1500 if id == 2 else 1400)
		m.escape_armed = true
		_ticks(m, 5)
		t.check(m.escape_clear_ticks == 0, "one enemy at 1400 blocks progress (order %s)" % [order])
		m.ships[3]["position"] = PLAYER_AT + Vector2(1450, 0)
		_ticks(m, 5)
		t.check(m.escape_clear_ticks == 5, "every enemy beyond 1400 allows progress (order %s)" % [order])


func _test_inactive(t) -> void:
	var sim = _fixture(1500)
	_add_enemy(sim, 3, 100, false)
	_ticks(sim, 10)
	t.check(not sim.escape_armed, "inactive proximity alone cannot arm")
	sim.escape_armed = true
	_ticks(sim, 10)
	t.check(sim.escape_clear_ticks == 10, "inactive nearby ship never blocks progress")
	var dead_player = _fixture(1500)
	dead_player.escape_armed = true
	dead_player.ships[1]["active"] = false
	_ticks(dead_player, required + 10)
	t.check(dead_player.result.is_empty() and dead_player.escape_clear_ticks == 0, "inactive player never escapes")
	var no_enemy = _fixture(1500)
	no_enemy.escape_armed = true
	no_enemy.ships[2]["active"] = false
	_ticks(no_enemy, required + 10)
	t.check(no_enemy.result.is_empty(), "no active enemy never awards escape")
	var resolved = _fixture(1500)
	resolved.escape_armed = true
	resolved.result = {"outcome": "victory", "elapsed": 1.0, "defeated": []}
	_ticks(resolved, required + 10)
	t.check(resolved.result["outcome"] == "victory", "existing result is never overwritten by escape")


func _test_practice(t) -> void:
	var sim = NavalSimulation.new()
	sim.reset("practice", "sloop")
	sim.step(DT, {})  # target 500 away: within arming distance
	sim.ships[1]["position"] = PLAYER_AT
	sim.ships[1]["heading"] = PI
	sim.ships[2]["position"] = Vector2(3000, 2100)
	for i in required + 60:
		sim.step(DT, {})
	t.check(not sim.escape_armed and sim.escape_clear_ticks == 0 and sim.result.is_empty(),
		"practice: approach then depart >1400 for >8 s gives no arming, progress or result")
	sim.ships[2]["hull"] = 3.0
	_lethal(sim, 1, 2, "round")
	sim.step(DT, {})
	t.check(not sim.ships[2]["active"] and sim.result.is_empty(), "practice target defeat yields no result")
	sim.reset("practice", "sloop")
	t.check(sim.ships[2]["active"] and sim.ships[2]["hull"] == Definitions.VESSELS["brig"]["hull"],
		"practice target reset works")


# --- precedence / lifecycle ---


## Armed with 479 clear ticks; the next real step would complete escape unless combat resolves.
func _test_precedence(t) -> void:
	var cases := [
		["enemy hull", [[1, 2, "round", "hull"]], "victory", "sunk"],
		["enemy sails", [[1, 2, "chain", "sails"]], "victory", "disabled"],
		["enemy crew", [[1, 2, "grape", "crew"]], "victory", "disabled"],
		["enemy hull+sails", [[1, 2, "round", "hull"], [1, 2, "chain", "sails"]], "victory", "sunk"],
		["player hull", [[2, 1, "round", "hull"]], "defeat", "sunk"],
		["both hulls", [[1, 2, "round", "hull"], [2, 1, "round", "hull"]], "draw", "sunk"],
		["no lethal hit", [], "escaped", ""],
	]
	for c in cases:
		var sim = _separated("duel_sloop", "sloop")
		sim.escape_armed = true
		sim.escape_clear_ticks = required - 1
		for shot in c[1]:
			sim.ships[shot[1]][shot[3]] = 1.0
			_lethal(sim, shot[0], shot[1], shot[2])
		sim.step(DT, {})
		t.check(sim.ships[1]["position"].distance_to(sim.ships[2]["position"]) > Definitions.ESCAPE_DISTANCE,
			"%s: centers still separated after movement" % c[0])
		t.check(sim.result.get("outcome") == c[2], "%s resolves %s (got %s)" % [c[0], c[2], sim.result.get("outcome")])
		if c[3] != "":
			t.check(sim.result["defeated"][0]["reason"] == c[3], "%s classified %s" % [c[0], c[3]])


func _test_freeze(t) -> void:
	var sim = _separated("duel_sloop", "sloop")
	sim.escape_armed = true
	sim.escape_clear_ticks = required - 1
	sim.step(DT, {})
	t.check(sim.result.get("outcome") == "escaped", "real step completes escape")
	var frozen := _state(sim)
	for i in 30:
		sim.step(DT, {1: {"turn": 1.0, "fire_port": true, "toggle_sails": true}, 2: {"turn": 1.0, "fire_starboard": true}})
	var after := _state(sim)
	t.check(after["ships"] == frozen["ships"] and after["result"] == frozen["result"]
		and after["elapsed"] == frozen["elapsed"] and after["projectiles"] == frozen["projectiles"]
		and sim.events.is_empty(), "escape freezes state and ignores later actions")


func _test_three_ship_progress(t) -> void:
	var sim = _separated("duel_sloop", "sloop")
	_add_enemy(sim, 3, 500)
	sim.ships[3]["heading"] = PI / 2.0
	sim.escape_armed = true
	sim.escape_clear_ticks = required - 1
	sim.step(DT, {})
	t.check(sim.escape_clear_ticks == 0 and sim.result.is_empty(), "nearby pursuer resets 479 ticks of progress")
	sim.ships[3]["hull"] = 1.0
	_lethal(sim, 1, 3, "round")
	sim.step(DT, {})
	t.check(not sim.ships[3]["active"] and sim.escape_clear_ticks == 1,
		"defeating the pursuer with another enemy beyond 1400 restarts progress at 1")
	t.check(sim.result.is_empty(), "an operational enemy remains: no combat result")


func _test_reset_lifecycle(t) -> void:
	for preset_id in DUELS:
		for vessel_id in VESSELS:
			var label := "%s/%s" % [preset_id, vessel_id]
			var fresh = NavalSimulation.new()
			fresh.reset(preset_id, vessel_id)
			var expected := _state(fresh)
			var sim = _separated(preset_id, vessel_id)
			sim.escape_armed = true
			for i in 120:
				sim.step(DT, {1: {"fire_port": i == 0, "cycle_starboard": i == 1}})
			t.check(sim.escape_clear_ticks == 120 and sim.result.is_empty(), "%s: partial progress" % label)
			sim.reset(preset_id, vessel_id)
			t.check(_state(sim) == expected, "%s: reset after partial progress equals fresh" % label)
			sim = _separated(preset_id, vessel_id)
			sim.escape_armed = true
			for i in required:
				sim.step(DT, {})
			t.check(sim.result.get("outcome") == "escaped", "%s: escapes when held clear" % label)
			sim.reset(preset_id, vessel_id)
			t.check(_state(sim) == expected, "%s: reset after escape equals fresh" % label)
	var changed = _separated("duel_frigate", "frigate")
	changed.escape_armed = true
	changed.escape_clear_ticks = 200
	changed.reset("duel_brig", "sloop")
	var other = NavalSimulation.new()
	other.reset("duel_brig", "sloop")
	t.check(_state(changed) == _state(other), "reset into a different selection equals fresh")
	changed.escape_armed = true
	changed.escape_clear_ticks = 10
	changed.reset("practice", "brig")
	t.check(not changed.escape_armed and changed.escape_clear_ticks == 0, "practice reset clears escape state")


func _test_pause_focus(t) -> void:
	var main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	main.start_encounter("duel_sloop", "sloop")
	var sim = main.sim
	sim.ships[1]["position"] = PLAYER_AT
	sim.ships[1]["heading"] = PI
	sim.ships[2]["position"] = Vector2(3500, 2100)
	sim.escape_armed = true
	for i in 120:
		main.advance_tick()
	t.check(sim.escape_clear_ticks == 120, "controller countdown reaches 120 ticks")
	main.set_paused(true)
	var paused := _state(sim)
	for i in 600:  # 10 s of controller time
		main.advance_tick()
	t.check(_state(sim) == paused, "paused: 10 s of ticks leave progress, ships and projectiles frozen")
	main.set_paused(false)
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.check(main.mode == "paused", "focus loss mid-countdown pauses")
	for keycode in [KEY_Q, KEY_W]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.pressed = true
		main._input(ev)
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	main.advance_tick()
	t.check(main.mode == "paused" and sim.escape_clear_ticks == 120, "focus return stays paused")
	var reefed: bool = sim.ships[1]["reefed"]
	main.set_paused(false)
	main.advance_tick()
	t.check(sim.escape_clear_ticks == 121, "explicit resume continues the countdown")
	t.check(sim.ships[1]["reefed"] == reefed and not sim.events.any(func(e): return e["type"] == "shot" and e["ship_id"] == 1),
		"resume replays no buffered fire/sail edges")
	main.free()


## HUD status texts, result reason and pause-menu hint (headless wiring, not readability).
func _test_ui(t) -> void:
	var main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	var hud = main.hud
	main.start_encounter("duel_sloop", "sloop")
	t.check("Escape unarmed: close to within 900" in hud.escape_rule_label.text and "Nearest enemy 1000" in hud.escape_status_label.text,
		"unarmed HUD rule and nearest distance")
	var sim = main.sim
	sim.ships[1]["position"] = PLAYER_AT
	sim.ships[1]["heading"] = PI
	sim.ships[2]["position"] = Vector2(3500, 2100)
	sim.escape_armed = true
	main.hud.refresh(sim)
	t.check("farther than 1400 from EVERY active enemy for %s s" % Definitions.ESCAPE_SECONDS in hud.escape_rule_label.text,
		"armed HUD rule (%s)" % hud.escape_rule_label.text)
	for i in 192:
		main.advance_tick()
	t.check(hud.escape_status_label.text.begins_with("Breaking pursuit: 3.2 / 8.0 s — nearest enemy ") and hud.escape_bar.visible,
		"counting HUD shows progress, target and nearest distance (%s)" % hud.escape_status_label.text)
	sim.ships[2]["position"] = sim.ships[1]["position"] + Vector2(500, 0)
	main.advance_tick()
	t.check(hud.escape_status_label.text.begins_with("Pursuit resumed — progress reset; escape remains armed."),
		"reset HUD notice after interruption")
	sim.ships[2]["position"] = sim.ships[1]["position"] + Vector2(2000, 0)
	sim.escape_clear_ticks = required - 1
	main.advance_tick()
	t.check(main.mode == "result" and main.result_menu.title_label.text == "Escaped"
		and "you broke pursuit while an opponent remained operational" in main.result_menu.detail_label.text,
		"result menu shows escape reason")
	t.check(main.result_menu.replay_button.has_focus(), "replay has default focus after escape")
	main.result_menu.replay_button.pressed.emit()
	t.check(main.mode == "sailing" and not main.sim.escape_armed and main.sim.escape_clear_ticks == 0
		and "Escape unarmed" in hud.escape_rule_label.text, "one-action replay returns clean unarmed state")
	main.set_paused(true)
	var guidance: String = main.pause_menu.guidance_label.text
	t.check("chain shot slows pursuers" in guidance and "Z/C cycle to Chain" in guidance and "W toggle sails" in guidance,
		"duel pause help shows escape hint with live bindings")
	main.set_paused(false)
	main.start_encounter("practice", "sloop")
	t.check(hud.escape_rule_label.text == "Escape unavailable — reset target or return via Pause."
		and not hud.escape_status_label.visible, "practice HUD says escape unavailable")
	main.set_paused(true)
	t.check(not ("chain shot slows pursuers" in main.pause_menu.guidance_label.text), "practice pause help omits escape hint")
	main.free()
