extends RefCounted
## Phase 3 plan 03: the multiplayer client UI over real localhost ENet. Three main.tscn clients
## (anne, bob, offline) and a SessionServer share one SceneTree with all processing off, so
## _pump() is the only clock. Keys reach a client only through main._input(event): the mains
## share one viewport. Later tasks add their cases between connect/harbor and _teardown().

const SessionServer := preload("res://net/session_server.gd")
const MultiplayerConfig := preload("res://net/multiplayer_config.gd")
const MultiplayerMenu := preload("res://ui/multiplayer_menu.gd")
const HarborMenu := preload("res://ui/harbor_menu.gd")
const Protocol := preload("res://net/protocol.gd")
const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")

const PORT := 24790  # Plan 02 uses 24760-24775 and 24690
const PASSWORD := "harbor"
const KEYS := ["anne", "bob", "offline"]

var t
var server
var anne
var bob
var offline
var clients: Array = []
var anne_id := "a".repeat(32)
var bob_id := "b".repeat(32)


func run(runner) -> bool:
	t = runner
	_test_texts()
	offline = _client("offline")
	_test_offline_ui()
	_test_synthetic_results()
	server = SessionServer.new()
	t.root.add_child(server)
	server.set_process(false)
	server.set_physics_process(false)
	t.check(server.start(PORT, PASSWORD, Protocol.build_version()) == OK, "mp ui: server listens on %d" % PORT)
	anne = _client("anne")
	bob = _client("bob")
	_test_connect_and_harbor()
	_test_shared_battle()
	_test_defeat_and_result()
	_test_server_stop()
	_test_offline_after_multiplayer()
	_teardown()
	return true


# --- harness -----------------------------------------------------------------------------------

## A main.tscn with physics and view/session processing off and its own multiplayer cfg file.
func _client(key: String) -> Node:
	var main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	main.arena_view.set_process(false)
	main.session.set_process(false)
	main.mp_config = MultiplayerConfig.new("user://test_mp_%s.cfg" % key)
	clients.append(main)
	return main


## One clock step: the server receives and steps, then every client receives and ticks.
func _pump(n := 1) -> void:
	for _i in n:
		server.poll()
		server.advance_tick()
		for main in clients:
			main.session.poll()
			main.advance_tick()
		OS.delay_msec(1)


## Pumps until done.call() holds; false after `limit` pumps.
func _until(done: Callable, limit := 900) -> bool:
	for _i in limit:
		if done.call():
			return true
		_pump()
	return done.call()


## Multiplayer -> form filled with 127.0.0.1:PORT, name and password -> Connect.
func _connect(main: Node, captain_name: String, id: String, password := PASSWORD) -> void:
	main.selection.multiplayer_button.pressed.emit()
	main.mp_config.values["captain_id"] = id
	var menu = main.multiplayer_menu
	menu.address_edit.text = "127.0.0.1:%d" % PORT
	menu.name_edit.text = captain_name
	menu.password_edit.text = password
	menu.connect_button.pressed.emit()


func _teardown() -> void:
	for main in clients:
		main.session.disconnect_from()
	if server != null:
		server.stop(0)
		server.free()
	for main in clients:
		main.free()
	clients.clear()
	for key in KEYS:
		var path := "user://test_mp_%s.cfg" % key
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	t.check(not FileAccess.file_exists(MultiplayerConfig.PATH), "mp ui: user://multiplayer.cfg was never written")


## A key press and release delivered the way the engine would: through main._input.
func _press(main: Node, key: Key) -> void:
	_hold(main, key, true)
	_hold(main, key, false)


func _hold(main: Node, key: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = down
	main._input(event)


## Text of the first harbor row's label or button ("" without rows).
func _first_row(main: Node, part: String) -> String:
	var rows: Array = main.harbor_menu.battle_rows
	return rows[0][part].text if not rows.is_empty() else ""


func _owns_projectile(main: Node) -> bool:
	for p in main.sim.projectiles:
		if p["owner_id"] == main.own_ship_id:
			return true
	return false


## The authoritative simulation of the battle `main` is in.
func _server_sim(main: Node):
	return server.battles[main.battle_id].sim


## True when main's harbor captain list contains every given text.
func _lists(main: Node, texts: Array) -> bool:
	return texts.all(func(text): return text in main.harbor_menu.captains_label.text)


func _fits(control: Control) -> bool:
	var size := control.get_combined_minimum_size()
	return size.x <= 1280 and size.y <= 720


# --- offline -----------------------------------------------------------------------------------

func _test_texts() -> void:
	t.check(MultiplayerMenu.parse_address("h", 24680) == {"host": "h", "port": 24680}, "mp ui: bare host takes the default port")
	t.check(MultiplayerMenu.parse_address(" h:2 ", 24680) == {"host": "h", "port": 2}, "mp ui: host:port is stripped and parsed")
	for bad in ["", "h:0", "h:70000", "h:x", "a:b:c", ":5", "h:"]:
		t.check(MultiplayerMenu.parse_address(bad, 24680) == {}, "mp ui: address '%s' rejected" % bad)
	var older: String = MultiplayerMenu.refusal_text("version_mismatch", "0.7", "0.8")
	t.check("v0.7" in older and "v0.8" in older and "Update your game" in older, "mp ui: older client told to update (%s)" % older)
	var newer: String = MultiplayerMenu.refusal_text("version_mismatch", "0.9", "0.8")
	t.check("server host must update" in newer, "mp ui: newer client blames the server (%s)" % newer)
	var dev: String = MultiplayerMenu.refusal_text("version_mismatch", "dev", "0.8")
	t.check("a development build" in dev and "Both must run the same build." in dev, "mp ui: dev build mismatch (%s)" % dev)
	t.check(MultiplayerMenu.refusal_text("wrong_password", "dev", "dev") == "Wrong password.", "mp ui: wrong password text")
	t.check(MultiplayerMenu.refusal_text("server_full", "dev", "dev") == "Server full: 4 captains are already connected.",
		"mp ui: server full text")
	t.check(MultiplayerMenu.refusal_text("bad_request", "dev", "dev") == "Connection refused (bad_request).",
		"mp ui: other refusals name the reason")
	t.check(MultiplayerMenu.ENDED_TEXT == {"server_stopped": "Server stopped.", "connection_lost": "Connection lost.",
		"replaced": "Replaced by a newer connection."}, "mp ui: connection ended texts")
	for reason in ["battle_cap", "no_reentry", "unknown_battle", "already_in_battle"]:
		var text: String = HarborMenu.refused_text(reason)
		t.check(text != "Request refused (%s)." % reason and text.ends_with("."), "mp ui: refusal %s has a sentence (%s)" % [reason, text])
	t.check(HarborMenu.refused_text("bad_request") == "Request refused (bad_request).", "mp ui: other harbor refusals name the reason")
	t.check(HarborMenu.outcome_notice("escaped") == "Escaped — you broke pursuit."
		and HarborMenu.outcome_notice("abandoned") == "Your ship was abandoned."
		and HarborMenu.outcome_notice("sunk") == "" and HarborMenu.outcome_notice("victory") == "", "mp ui: outcome notices")
	var battle_keys: String = PauseMenu.bindings_text(false)
	t.check(" menu" in battle_keys and not "pause" in battle_keys and " pause" in PauseMenu.bindings_text(),
		"mp ui: battle help labels Esc menu, offline help still pause (%s)" % battle_keys)


func _test_offline_ui() -> void:
	var sel = offline.selection
	var two: Button = sel.duel_buttons["two_sloops"]
	t.check(two.focus_neighbor_bottom == two.get_path_to(sel.multiplayer_button)
		and sel.multiplayer_button.focus_neighbor_bottom == sel.multiplayer_button.get_path_to(sel.settings_button)
		and sel.settings_button.focus_neighbor_bottom == sel.settings_button.get_path_to(sel.quit_button),
		"mp ui: selection focus two_sloops -> Multiplayer -> Settings -> Quit")
	var mode_panel: Control = sel.get_child(0).get_child(0)
	var scroll: ScrollContainer = mode_panel.get_child(0)
	var content: Vector2 = scroll.get_child(0).get_combined_minimum_size()
	t.check(content.y <= scroll.custom_minimum_size.y and _fits(mode_panel),
		"mp ui: selection panel fits 720 without scrolling (%s)" % content)
	# Connect form: a bad address or blank name stays in connect and sends nothing.
	sel.multiplayer_button.pressed.emit()
	var menu = offline.multiplayer_menu
	t.check(offline.mode == "connect" and menu.visible and not sel.visible, "mp ui: Multiplayer opens the connect form")
	t.check(menu.name_edit.max_length == 16 and menu.password_edit.secret, "mp ui: name max 16, password secret")
	var sent := []
	menu.connect_requested.connect(func(host, port, captain_name, password): sent.append([host, port, captain_name, password]))
	menu.address_edit.text = ""
	menu.name_edit.text = "Anne"
	menu.connect_button.pressed.emit()
	t.check(offline.mode == "connect" and sent.is_empty() and menu.status_label.text != ""
		and offline.session.status == "offline", "mp ui: empty address shows a hint and stays in connect")
	menu.address_edit.text = "127.0.0.1"
	menu.name_edit.text = "  "
	menu.connect_button.pressed.emit()
	t.check(sent.is_empty() and menu.status_label.text != "", "mp ui: blank name shows a hint")
	t.check(_fits(menu.get_child(0).get_child(0)), "mp ui: connect form fits 1280x720")
	_test_synthetic_harbor()
	menu.back_button.pressed.emit()
	t.check(offline.mode == "selection" and sel.visible and not menu.visible, "mp ui: Back returns to the selection menu")


func _test_synthetic_harbor() -> void:
	var harbor = offline.harbor_menu
	var long_names := ["Abcdefghijklmnop", "Bcdefghijklmnopq", "Cdefghijklmnopqr", "Defghijklmnopqrs"]
	var brig := {"battle_id": 3, "preset_id": "duel_brig", "label": "Brig duel", "captains": ["Anne", "Bob"],
		"ai_left": 1, "elapsed": 185.4, "can_join": true, "lingering_here": false}
	var h := {"t": "harbor", "can_start": false, "battles": [
		{"battle_id": 1, "preset_id": "frigate_escort", "label": "Frigate escort", "captains": long_names,
			"ai_left": 3, "elapsed": 3599.0, "can_join": false, "lingering_here": true},
		{"battle_id": 2, "preset_id": "brig_squadron", "label": "Brig squadron", "captains": [],
			"ai_left": 3, "elapsed": 12.0, "can_join": false, "lingering_here": false},
		brig,
		{"battle_id": 4, "preset_id": "two_sloops", "label": "Two-ship encounter", "captains": ["Cora"],
			"ai_left": 2, "elapsed": 61.0, "can_join": true, "lingering_here": false}],
		"captains": [{"name": "Anne", "slot": 0, "battle_id": 3}, {"name": "Bob", "slot": 1, "battle_id": 0}]}
	harbor.show_harbor(h)
	harbor.visible = true
	var rows: Array = harbor.battle_rows
	t.check(rows.size() == 4 and rows.map(func(r): return r["battle_id"]) == [1, 2, 3, 4], "mp ui: one row per battle")
	if rows.size() != 4:
		return
	t.check(rows[0]["button"].text == "Reclaim" and not rows[0]["button"].disabled, "mp ui: lingering_here -> Reclaim")
	t.check(rows[1]["button"].text == "Closed" and rows[1]["button"].disabled, "mp ui: closed battle -> disabled Closed")
	t.check(rows[2]["button"].text == "Join" and not rows[2]["button"].disabled, "mp ui: joinable battle -> Join")
	t.check(rows[2]["label"].text == "Brig duel · Anne, Bob · 1 AI left · 3:05", "mp ui: battle line (%s)" % rows[2]["label"].text)
	t.check(HarborMenu.battle_line(brig) == "Brig duel · Anne, Bob · 1 AI left · 3:05", "mp ui: battle_line")
	t.check(rows[1]["label"].text.begins_with("Brig squadron · no captains · 3 AI left"), "mp ui: empty battle says no captains")
	t.check(harbor.start_button.disabled, "mp ui: can_start false disables Start")
	t.check("●1 Anne (Brig duel)" in harbor.captains_label.text and "●2 Bob (harbor)" in harbor.captains_label.text,
		"mp ui: captains list slot, name and place (%s)" % harbor.captains_label.text)
	t.check(_fits(harbor.get_child(0).get_child(0)), "mp ui: 4-battle harbor fits 1280x720 (%s)"
		% harbor.get_child(0).get_child(0).get_combined_minimum_size())
	var starts := []
	var joins := []
	harbor.start_requested.connect(func(preset_id, vessel_id): starts.append([preset_id, vessel_id]))
	harbor.join_requested.connect(func(id, vessel_id): joins.append([id, vessel_id]))
	# Join -> vessel-only picker -> join_requested(id, vessel); actions wait for a reply.
	rows[2]["button"].pressed.emit()
	t.check(harbor.confirm_button.is_visible_in_tree() and not harbor.preset_buttons["duel_sloop"].is_visible_in_tree(),
		"mp ui: Join opens a vessel-only picker")
	t.check(harbor.vessel_buttons["sloop"].button_pressed, "mp ui: picker defaults to the sloop")
	harbor.vessel_buttons["brig"].button_pressed = true
	harbor.confirm_button.pressed.emit()
	t.check(joins == [[3, "brig"]], "mp ui: Join confirms with the battle id and vessel (%s)" % [joins])
	t.check(harbor.battle_rows[0]["button"].disabled and harbor.battle_rows[2]["button"].disabled,
		"mp ui: actions wait for a reply")
	harbor.set_waiting(false)
	harbor.show_notice(HarborMenu.refused_text("unknown_battle"))
	t.check(harbor.notice_label.visible and not harbor.battle_rows[2]["button"].disabled, "mp ui: a refusal shows a notice and re-enables")
	# Reclaim sends no vessel.
	harbor.battle_rows[0]["button"].pressed.emit()
	t.check(joins.size() == 2 and joins[1] == [1, ""], "mp ui: Reclaim joins with no vessel (%s)" % [joins])
	harbor.set_waiting(false)
	# Start (when allowed) -> preset + vessel picker -> start_requested.
	h["can_start"] = true
	harbor.show_harbor(h)
	t.check(not harbor.start_button.disabled, "mp ui: can_start enables Start")
	harbor.start_button.pressed.emit()
	t.check(harbor.preset_buttons.keys() == Array(Definitions.BATTLE_PRESETS), "mp ui: presets are BATTLE_PRESETS")
	t.check(harbor.preset_buttons["duel_sloop"].is_visible_in_tree(), "mp ui: Start shows the presets")
	t.check(_fits(harbor.get_child(1).get_child(0)), "mp ui: picker fits 1280x720 (%s)"
		% harbor.get_child(1).get_child(0).get_combined_minimum_size())
	harbor.preset_buttons["frigate_escort"].button_pressed = true
	harbor.vessel_buttons["sloop"].button_pressed = true
	harbor.confirm_button.pressed.emit()
	t.check(starts == [["frigate_escort", "sloop"]], "mp ui: Start confirms preset and vessel (%s)" % [starts])
	t.check(harbor.start_button.disabled, "mp ui: Start waits for a reply")
	harbor.set_waiting(false)
	harbor.start_button.pressed.emit()
	harbor.back_button.pressed.emit()
	t.check(harbor.start_button.is_visible_in_tree() and starts.size() == 1, "mp ui: picker Back returns to the harbor")
	harbor.visible = false


## Battle result overlay and outcome notices, without a server.
func _test_synthetic_results() -> void:
	var sim = NavalSimulation.new()
	sim.reset_battle("duel_brig")
	sim.result = {"outcome": "lost", "elapsed": 61.0, "defeated": [], "outcomes": {
		100: {"outcome": "sunk", "elapsed": 20.0}, 101: {"outcome": "abandoned", "elapsed": 50.0}}}
	var menu = offline.result_menu
	menu.show_battle_result(sim, 100, {100: {"name": "Anne", "slot": 0}, 101: {"name": "Bob", "slot": 1}})
	var text: String = menu.detail_label.text
	t.check(menu.title_label.text == "Lost" and "Your ship: Sunk" in text and "Time 1:01" in text
		and "Bob: Abandoned" in text and not "Anne:" in text, "mp result: lost battle lines (%s)" % text)
	t.check(not menu.replay_button.visible and menu.return_button.text == "Return to harbor" and menu.return_button.has_focus(),
		"mp result: Replay hidden, Return to harbor focused")
	var duel = NavalSimulation.new()
	duel.reset("duel_brig", "sloop")
	duel.result = {"outcome": "victory", "elapsed": 5.0, "defeated": []}
	menu.show_result(duel)
	t.check(menu.replay_button.visible and menu.replay_button.has_focus() and menu.return_button.text == "Return to selection",
		"mp result: show_result restores Replay and Return to selection")
	menu.visible = false
	# Outcomes: another battle's notice in the harbor; escaping this battle returns to the harbor.
	offline._enter_mode("harbor")
	offline._on_outcome({"battle_id": 3, "ship_id": 100, "outcome": "abandoned", "elapsed": 1.0})
	t.check(offline.mode == "harbor" and offline.harbor_menu.notice_label.visible
		and offline.harbor_menu.notice_label.text == "Your ship was abandoned.", "mp result: abandoned elsewhere -> harbor notice")
	offline.battle_id = 5
	offline._enter_mode("battle")
	offline._on_outcome({"battle_id": 5, "ship_id": 100, "outcome": "escaped", "elapsed": 1.0})
	t.check(offline.mode == "harbor" and offline.battle_id == 0
		and offline.harbor_menu.notice_label.text == "Escaped — you broke pursuit.", "mp result: escaped -> harbor notice")
	offline._enter_mode("selection")


# --- real server -------------------------------------------------------------------------------

func _test_connect_and_harbor() -> void:
	_pump(30)
	t.check(bob.session.status == "offline" and anne.session.status == "offline", "mp ui: no connection before Connect")
	_connect(bob, "Bob", bob_id, "nope")
	t.check(_until(func(): return bob.multiplayer_menu.status_label.text == "Wrong password."),
		"mp ui: wrong password shown (%s)" % bob.multiplayer_menu.status_label.text)
	t.check(bob.mode == "connect" and not bob.multiplayer_menu.connect_button.disabled, "mp ui: refused client stays on the form")
	_connect(anne, "Anne", anne_id)
	t.check(_until(func(): return anne.mode == "harbor"), "mp ui: Anne reaches the harbor")
	_connect(bob, "Bob", bob_id)
	t.check(_until(func(): return bob.mode == "harbor"), "mp ui: Bob reaches the harbor")
	t.check(_until(func(): return _lists(anne, ["●1 Anne", "●2 Bob"])),
		"mp ui: Anne's harbor lists both captains (%s)" % anne.harbor_menu.captains_label.text)
	t.check(anne.harbor_menu.visible and not anne.multiplayer_menu.visible and not anne.hud.visible,
		"mp ui: harbor shows alone")
	var saved = MultiplayerConfig.new("user://test_mp_anne.cfg")
	t.check(saved.load_config() and saved.values == {"captain_id": anne_id, "name": "Anne", "host": "127.0.0.1",
		"port": PORT, "password": PASSWORD}, "mp ui: Anne's connection is remembered (%s)" % saved.values)
	# Disconnect -> form; the server drops Bob from Anne's list; reconnecting restores both.
	bob.harbor_menu.disconnect_button.pressed.emit()
	t.check(bob.mode == "connect" and bob.session.status == "offline" and not bob.multiplayer_menu.connect_button.disabled,
		"mp ui: Disconnect returns to the form")
	t.check(_until(func(): return not _lists(anne, ["Bob"])), "mp ui: Bob leaves Anne's list")
	_connect(bob, "Bob", bob_id)
	t.check(_until(func(): return bob.mode == "harbor" and _lists(anne, ["●2 Bob"])),
		"mp ui: Bob reconnects in slot 2")


# --- shared battle ----------------------------------------------------------------------------

func _test_shared_battle() -> void:
	# Start + drop-in: Anne starts a brig duel in a sloop; Bob joins it in a brig.
	var harbor = anne.harbor_menu
	harbor.start_button.pressed.emit()
	harbor.preset_buttons["duel_brig"].button_pressed = true
	harbor.vessel_buttons["sloop"].button_pressed = true
	harbor.confirm_button.pressed.emit()
	t.check(_until(func(): return anne.mode == "battle" and anne.sim.ships.has(anne.own_ship_id)),
		"mp battle: Anne's start enters battle with her ship mirrored")
	if anne.mode != "battle":
		return
	t.check(anne.own_ship_id >= NavalSimulation.FIRST_CAPTAIN_SHIP_ID and anne.sim == anne.buffer.mirror
		and anne.sim.battle_mode, "mp battle: own ship is a captain ship and sim is the buffer mirror")
	t.check(anne.hud.visible and not anne.harbor_menu.visible and anne.hud.target_label.text == "Enemy A (Brig)",
		"mp battle: HUD shows Enemy A (Brig) (%s)" % anne.hud.target_label.text)
	t.check(not anne.hud.banner_label.visible and anne.hud.escape_rule_label.visible, "mp battle: no waiting banner once mirrored")
	t.check(_until(func(): return _first_row(bob, "label").contains("Brig duel · Anne") and "1 AI left" in _first_row(bob, "label")),
		"mp battle: Bob's harbor lists Anne's brig duel (%s)" % _first_row(bob, "label"))
	if bob.harbor_menu.battle_rows.is_empty():
		return
	bob.harbor_menu.battle_rows[0]["button"].pressed.emit()
	bob.harbor_menu.vessel_buttons["brig"].button_pressed = true
	bob.harbor_menu.confirm_button.pressed.emit()
	t.check(_until(func(): return bob.mode == "battle" and anne.sim.ships.has(bob.own_ship_id) and anne.captains.has(bob.own_ship_id)),
		"mp battle: Anne mirrors Bob's dropped-in ship")
	t.check(anne.captains.get(bob.own_ship_id, {}).get("slot", -1) == 1 and bob.battle_id == anne.battle_id
		and bob.captains.has(anne.own_ship_id), "mp battle: captains entries for both (slot 1 = Bob)")
	t.check(_until(func(): return anne.hud.ally_labels[0].visible and "Bob" in anne.hud.ally_labels[0].text),
		"mp battle: Anne's ally row shows Bob (%s)" % anne.hud.ally_labels[0].text)
	_test_battle_actions()
	_test_battle_menu()


func _test_battle_actions() -> void:
	var own: int = anne.own_ship_id
	# Two fire presses in one tick: two reliable actions, applied on separate server ticks.
	_press(anne, KEY_Q)
	_press(anne, KEY_Q)
	t.check(_until(func(): return _owns_projectile(anne)),
		"mp battle: Anne's port volley is mirrored")
	t.check(_until(func(): return anne.hud.feedback_labels["port"].text == "no loaded guns"),
		"mp battle: the second press arrived separately (no loaded guns)")
	var heading: float = _server_sim(anne).ships[own]["heading"]
	_hold(anne, KEY_D, true)
	_pump(30)
	t.check(angle_difference(heading, _server_sim(anne).ships[own]["heading"]) > 0.05,
		"mp battle: holding D turns the server ship")
	_hold(anne, KEY_D, false)
	_pump(5)
	heading = _server_sim(anne).ships[own]["heading"]
	_pump(30)
	t.check(absf(angle_difference(heading, _server_sim(anne).ships[own]["heading"])) <= 1e-6,
		"mp battle: released steering holds the heading")


func _test_battle_menu() -> void:
	var own: int = anne.own_ship_id
	_press(anne, KEY_ESCAPE)
	t.check(anne.battle_menu.menu_open and anne.battle_menu.visible and anne.mode == "battle",
		"mp battle: Esc opens the battle menu without pausing")
	t.check(anne.battle_menu.resume_button.has_focus(), "mp battle: Resume is focused")
	anne.battle_menu.help_button.pressed.emit()
	t.check(anne.battle_menu.help_label.is_visible_in_tree() and "30 s" in anne.battle_menu.help_label.text
		and not "reset" in anne.battle_menu.help_label.text, "mp battle: Help explains leaving (%s)" % anne.battle_menu.help_label.text)
	t.check(_fits(anne.battle_menu.get_child(1).get_child(0)), "mp battle: battle menu with help fits 1280x720")
	var tick: int = server.battles[anne.battle_id].tick
	var elapsed: float = anne.sim.elapsed
	var heading: float = _server_sim(anne).ships[own]["heading"]
	_hold(anne, KEY_D, true)
	_pump(30)
	t.check(server.battles[anne.battle_id].tick >= tick + 25 and anne.sim.elapsed > elapsed,
		"mp battle: the battle keeps running behind the menu")
	t.check(absf(angle_difference(heading, _server_sim(anne).ships[own]["heading"])) <= 1e-6,
		"mp battle: no steering while the menu is open")
	_hold(anne, KEY_D, false)
	anne.battle_menu.resume_button.pressed.emit()
	t.check(not anne.battle_menu.menu_open and not anne.battle_menu.visible and anne._can_command(),
		"mp battle: Resume closes the menu")
	# Settings opens from the battle menu and returns to it.
	_press(anne, KEY_ESCAPE)
	anne.battle_menu.settings_button.pressed.emit()
	t.check(anne.settings_menu.visible and not anne.battle_menu.visible and anne.battle_menu.menu_open
		and anne.mode == "battle", "mp battle: Settings opens over the battle")
	anne.settings_menu.back()
	t.check(anne.battle_menu.visible and anne.battle_menu.settings_button.has_focus(), "mp battle: Settings returns to the battle menu")
	_press(anne, KEY_ESCAPE)
	t.check(not anne.battle_menu.menu_open, "mp battle: Esc closes the battle menu")
	# Focus loss clears held input but never pauses a battle.
	_hold(anne, KEY_D, true)
	anne._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.check(anne.mode == "battle" and anne._held.is_empty(), "mp battle: focus loss never pauses a battle")
	_hold(anne, KEY_D, false)
	# Leave -> harbor with the linger notice; Anne sees Bob AWAY; Bob reclaims the same ship.
	var bob_ship: int = bob.own_ship_id
	_press(bob, KEY_ESCAPE)
	bob.battle_menu.leave_button.pressed.emit()
	t.check(bob.mode == "harbor" and bob.buffer == null and bob.battle_id == 0 and not bob.battle_menu.visible
		and "30 s" in bob.harbor_menu.notice_label.text, "mp battle: Leave returns to the harbor (%s)" % bob.harbor_menu.notice_label.text)
	t.check(_until(func(): return anne.hud.ally_labels[0].text.ends_with("AWAY")),
		"mp battle: Anne's row for Bob ends AWAY (%s)" % anne.hud.ally_labels[0].text)
	t.check(_until(func(): return _first_row(bob, "button") == "Reclaim"), "mp battle: Bob's harbor offers Reclaim")
	if bob.harbor_menu.battle_rows.is_empty():
		return
	bob.harbor_menu.battle_rows[0]["button"].pressed.emit()
	t.check(_until(func(): return bob.mode == "battle" and bob.sim.ships.has(bob.own_ship_id)) and bob.own_ship_id == bob_ship,
		"mp battle: Reclaim returns Bob to the same ship")
	t.check(_until(func(): return not anne.hud.ally_labels[0].text.ends_with("AWAY")),
		"mp battle: Bob is back on Anne's row")


# --- defeat, spectating and results ------------------------------------------------------------

## The way test_duel_ui.gd stages a sinking: a 3-hull ship and a round ball just above it.
func _stage_sink(sim, target: int, owner: int) -> void:
	sim.ships[target]["hull"] = 3.0
	sim.projectiles.append({"id": sim.next_projectile_id, "owner_id": owner, "ammo": "round",
		"position": sim.ships[target]["position"] - Vector2(0, 10), "direction": Vector2.DOWN,
		"remaining_range": 900.0, "owner_cleared": true})
	sim.next_projectile_id += 1


func _test_defeat_and_result() -> void:
	if anne.mode != "battle" or bob.mode != "battle":
		return
	var ai_id: int = 2
	var anne_ship: int = anne.own_ship_id
	_stage_sink(_server_sim(bob), bob.own_ship_id, ai_id)
	t.check(_until(func(): return bob.battle_menu.defeat_open), "mp defeat: Bob's sinking opens the defeat panel")
	var menu = bob.battle_menu
	t.check(menu.defeat_panel.is_visible_in_tree() and menu.defeat_title.text == "Sunk" and bob.own_outcome == "sunk",
		"mp defeat: titled Sunk (%s)" % menu.defeat_title.text)
	t.check(menu.watch_button.text == "Watch allies" and not menu.watch_button.disabled and menu.harbor_button.text == "Return to harbor",
		"mp defeat: Watch allies enabled, Return to harbor")
	t.check(not bob._can_command() and bob.mode == "battle", "mp defeat: a sunk captain cannot command")
	t.check(_fits(menu.get_child(1).get_child(0)), "mp defeat: defeat panel fits 1280x720")
	menu.watch_button.pressed.emit()
	_pump()
	t.check(not menu.defeat_open and not menu.visible and bob.focus_ship_id() == anne_ship, "mp defeat: Watch follows Anne")
	t.check(bob.hud.banner_label.visible and bob.hud.banner_label.text.begins_with("Watching Anne"),
		"mp defeat: banner Watching Anne (%s)" % bob.hud.banner_label.text)
	_press(bob, KEY_D)
	t.check(bob.focus_ship_id() == anne_ship and bob._held.is_empty(), "mp defeat: turn keys cycle allies (wrapping), never steer")
	for _i in 10:
		bob.arena_view._process(0.5)
	var camera: Vector2 = bob.arena_view.camera.position
	t.check(camera.distance_to(bob.sim.ships[anne_ship]["position"]) <= 160.0, "mp defeat: camera follows Anne (%s)" % camera)
	# Anne sinks the last AI ship: both see the same shared result.
	_stage_sink(_server_sim(anne), ai_id, anne_ship)
	t.check(_until(func(): return anne.mode == "battle_result" and bob.mode == "battle_result"), "mp result: both reach the battle result")
	if anne.mode != "battle_result" or bob.mode != "battle_result":
		return
	var anne_text: String = anne.result_menu.detail_label.text
	var bob_text: String = bob.result_menu.detail_label.text
	t.check(anne.result_menu.title_label.text == "Victory" and bob.result_menu.title_label.text == "Victory"
		and anne.result_menu.visible and bob.result_menu.visible, "mp result: both titled Victory")
	t.check(not anne.sim.result.is_empty() and anne.sim.result == bob.sim.result, "mp result: identical shared results")
	t.check("Your ship: Victory" in anne_text and "Bob: Sunk" in anne_text, "mp result: Anne's lines (%s)" % anne_text)
	t.check("Your ship: Sunk" in bob_text and "Anne: Victory" in bob_text, "mp result: Bob's lines (%s)" % bob_text)
	t.check("Enemy A (Brig) sunk." in anne_text and "Enemy A (Brig) sunk." in bob_text, "mp result: opposition line")
	# The mains share one viewport, so only the synthetic case can assert focus.
	t.check(not anne.result_menu.replay_button.visible and not bob.result_menu.replay_button.visible
		and bob.result_menu.return_button.text == "Return to harbor", "mp result: Return to harbor, no Replay")
	anne.result_menu.return_button.pressed.emit()
	bob.result_menu.return_button.pressed.emit()
	t.check(anne.mode == "harbor" and bob.mode == "harbor" and not anne.result_menu.visible and anne.buffer == null,
		"mp result: Return goes to the harbor")
	t.check(_until(func(): return anne.harbor_menu.battle_rows.is_empty() and bob.harbor_menu.battle_rows.is_empty()),
		"mp result: the finished battle leaves the harbor")


func _test_server_stop() -> void:
	if anne.mode != "harbor":
		return
	var harbor = anne.harbor_menu
	harbor.start_button.pressed.emit()
	harbor.preset_buttons["duel_sloop"].button_pressed = true
	harbor.vessel_buttons["sloop"].button_pressed = true
	harbor.confirm_button.pressed.emit()
	t.check(_until(func(): return anne.mode == "battle" and anne.sim.ships.has(anne.own_ship_id)), "mp stop: Anne starts a battle")
	server.stop()
	# Clients were not polled during stop(): they end by ENet timeout with the server_stopping reason.
	var ended := func(main): return main.mode == "connect" and main.multiplayer_menu.status_label.text == "Server stopped."
	t.check(_until(func(): return ended.call(anne) and ended.call(bob), 6000),
		"mp stop: both back on the form with Server stopped. (%s / %s)" % [anne.multiplayer_menu.status_label.text,
		bob.multiplayer_menu.status_label.text])
	t.check(anne.sim.ships.is_empty() and anne.buffer == null and not anne.hud.visible, "mp stop: Anne's battle is gone")


func _test_offline_after_multiplayer() -> void:
	bob.multiplayer_menu.back_button.pressed.emit()
	t.check(bob.mode == "selection", "mp offline: Back returns Bob to the selection menu")
	bob.start_encounter("duel_brig", "sloop")
	t.check(bob.own_ship_id == 1 and bob.captains.is_empty() and not bob.sim.battle_mode and bob.mode == "sailing",
		"mp offline: an offline duel after multiplayer has no captains")
	var elapsed: float = bob.sim.elapsed
	bob.advance_tick()
	t.check(bob.sim.elapsed > elapsed, "mp offline: advance_tick steps the offline sim")
	t.check(bob.hud.target_label.text == "Enemy A (Brig)", "mp offline: HUD Enemy A (Brig) (%s)" % bob.hud.target_label.text)
	bob.return_to_selection()
