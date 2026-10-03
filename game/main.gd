extends Node
## Mode controller: selection / sailing / paused / result offline, connect / harbor / battle online.
## Owns the simulation and gates it; the SceneTree itself is never paused so menus keep running.
## Presentation (HUD and $ArenaView) reads `sim` without mutating it.

## Emitted after sim.reset() (start or restart): views must resync from `sim`.
signal practice_started
## Emitted on every mode change; "selection" means `sim` holds no encounter.
signal mode_changed(new_mode: String)

const NavalSimulation := preload("res://sim/naval_simulation.gd")
const Definitions := preload("res://sim/definitions.gd")
const Bindings := preload("res://input_bindings.gd")
const AIController := preload("res://sim/ai_controller.gd")
const SelectionMenu := preload("res://ui/selection_menu.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
const ResultMenu := preload("res://ui/result_menu.gd")
const Hud := preload("res://ui/hud.gd")
const Settings := preload("res://settings.gd")
const SettingsMenu := preload("res://ui/settings_menu.gd")
const Presentation := preload("res://view/combat_presentation.gd")
const CombatAudio := preload("res://audio/combat_audio.gd")
const UpdateService := preload("res://update/update_service.gd")
const SessionClient := preload("res://net/session_client.gd")
const MultiplayerConfig := preload("res://net/multiplayer_config.gd")
const MultiplayerMenu := preload("res://ui/multiplayer_menu.gd")
const HarborMenu := preload("res://ui/harbor_menu.gd")
const BattleMenu := preload("res://ui/battle_menu.gd")
const SnapshotBuffer := preload("res://net/snapshot_buffer.gd")

const DT := 1.0 / 60.0
const PRESET := "practice"
const TURN_ACTIONS := ["turn_left", "turn_right"]
## One-shot actions: a non-echo press while sailing queues one command for the next tick.
const EDGE_ACTIONS := ["fire_port", "fire_starboard", "cycle_port", "cycle_starboard"]
const HUD_MODES := ["sailing", "paused", "result", "battle", "battle_result"]
## Shared battles: each non-echo press sends one reliable action to the server.
const BATTLE_ACTIONS := ["toggle_sails", "fire_port", "fire_starboard", "cycle_port", "cycle_starboard"]
const LEAVE_NOTICE := "Your ship lingers for 30 s — Reclaim it from the harbor."

var sim = NavalSimulation.new()
var ai = AIController.new()
var mode := "selection"
var settings = Settings.new()
## The ship this client commands (offline: the player ship); views key own-ship UI by it.
var own_ship_id: int = NavalSimulation.PLAYER_ID
var captains := {}  # ship_id -> {"name", "slot"}; empty offline
var spectate_id := -1  # ship the camera follows instead of the own ship, when >= 0
var session: Node  # SessionClient; no socket until Connect
var mp_config = MultiplayerConfig.new()  # read only when Multiplayer is pressed
var buffer  # SnapshotBuffer of the joined battle; null outside a battle
var battle_id := 0
var own_outcome := ""  # this captain's outcome in the current battle, "" while commanding

@onready var arena_view: Node2D = $ArenaView
var selection: Control
var hud: Control
var battle_menu: Control
var pause_menu: Control
var result_menu: Control
var settings_menu: Control
var multiplayer_menu: Control
var harbor_menu: Control
var combat_audio: Node
var update_service: Node

var _held := {}  # turn actions freshly pressed while sailing and not yet released
var _toggle_queued := false  # parity of non-echo toggle presses since the last tick
var _edges := {}  # EDGE_ACTIONS pressed since the last tick (held keys never repeat)
var _reset_queued := false  # reset_practice pressed since the last tick


func _ready() -> void:
	# Dedicated server / headless bot: leave before settings, input, audio or UI exist.
	var args := OS.get_cmdline_user_args()
	for role in ["server", "bot"]:
		if "--" + role in args:
			get_tree().change_scene_to_file.call_deferred("res://net/%s_main.tscn" % role)
			return
	get_window().min_size = Vector2i(1280, 720)
	$UI.layer = 2
	Bindings.install_defaults()
	settings.load_settings()
	settings.apply_values(settings.values)
	combat_audio = CombatAudio.new()
	combat_audio.name = "CombatAudio"
	add_child(combat_audio)
	var theme := _make_theme()
	hud = Hud.new()
	hud.main = self
	battle_menu = BattleMenu.new()
	pause_menu = PauseMenu.new()
	result_menu = ResultMenu.new()
	selection = SelectionMenu.new()
	multiplayer_menu = MultiplayerMenu.new()
	harbor_menu = HarborMenu.new()
	settings_menu = SettingsMenu.new()
	for control in [hud, battle_menu, pause_menu, result_menu, selection, multiplayer_menu, harbor_menu, settings_menu]:
		control.theme = theme
		$UI.add_child(control)
		_ornament_panels(control)
	get_viewport().size_changed.connect(_fit_ui)
	_fit_ui()
	selection.start_requested.connect(start_encounter)
	selection.quit_requested.connect(get_tree().quit)
	pause_menu.resume_requested.connect(set_paused.bind(false))
	pause_menu.restart_requested.connect(restart_practice)
	pause_menu.return_requested.connect(return_to_selection)
	result_menu.replay_requested.connect(restart_practice)
	result_menu.return_requested.connect(_on_result_return)
	selection.settings_requested.connect(open_settings)
	pause_menu.settings_requested.connect(open_settings)
	battle_menu.resume_requested.connect(set_battle_menu.bind(false))
	battle_menu.settings_requested.connect(open_settings)
	battle_menu.leave_requested.connect(leave_battle)
	battle_menu.watch_requested.connect(_on_watch)
	battle_menu.harbor_requested.connect(leave_battle)
	settings_menu.closed.connect(close_settings)
	settings.changed.connect(_on_settings_changed)
	selection.show_notice(settings.notice)
	update_service = UpdateService.new()
	update_service.name = "UpdateService"
	add_child(update_service)
	update_service.state_changed.connect(selection.show_update_state)
	selection.check_updates_requested.connect(update_service.check)
	selection.update_requested.connect(update_service.update_and_restart)
	selection.full_download_requested.connect(func() -> void: OS.shell_open(UpdateService.RELEASES_URL))
	# The service picked its first state (disabled in dev builds) before the menu listened.
	selection.show_version(update_service.version)
	selection.show_update_state(update_service.state, update_service.detail)
	session = SessionClient.new()
	session.name = "SessionClient"
	add_child(session)
	selection.multiplayer_requested.connect(open_multiplayer)
	multiplayer_menu.connect_requested.connect(_on_connect_requested)
	multiplayer_menu.back_requested.connect(_on_connect_back)
	harbor_menu.start_requested.connect(session.start_battle)
	harbor_menu.join_requested.connect(session.join_battle)
	harbor_menu.disconnect_requested.connect(disconnect_session)
	session.connected_ok.connect(_on_connected)
	session.auth_refused.connect(_on_auth_refused)
	session.harbor_changed.connect(harbor_menu.show_harbor)
	session.refused.connect(_on_refused)
	session.connection_ended.connect(_on_connection_ended)
	session.joined.connect(_on_joined)
	session.snapshot_received.connect(_on_snapshot)
	session.events_received.connect(_on_events)
	session.outcome.connect(_on_outcome)
	session.battle_result.connect(_on_battle_result)
	_enter_mode("selection")


func _physics_process(_delta: float) -> void:
	advance_tick()


## Exactly one fixed step per call, and only while sailing. No accumulator/catch-up.
## In a shared battle one tick sends steering and renders the buffered server battle instead.
func advance_tick() -> void:
	if mode == "battle":
		_advance_battle()
		return
	if mode != "sailing" or not sim.result.is_empty():
		return
	if _reset_queued:
		# This tick is the reset: fire/cycle/toggle queued alongside it are discarded, not
		# deferred (restart clears all held/queued input), and views resync via practice_started.
		restart_practice()
		return
	var turn := float(_held.has("turn_right")) - float(_held.has("turn_left"))
	var command := {"turn": turn, "toggle_sails": _toggle_queued}
	for action in EDGE_ACTIONS:
		command[action] = _edges.has(action)
	_toggle_queued = false
	_edges.clear()
	var commands := {own_ship_id: command}
	if _is_duel():
		# AI sees only a copy; its commands join the player's under the opposition IDs.
		var ai_commands := ai.commands_for_tick(sim.ai_observation(), DT)
		for id in ai_commands:
			if id != own_ship_id:
				commands[id] = ai_commands[id]
	sim.step(DT, commands)
	var presentation_events: Array = Presentation.normalize_events(sim.events)
	combat_audio.arena_view = arena_view
	combat_audio.consume(presentation_events)
	arena_view.advance_effects()
	hud.advance_effects()
	arena_view.consume_events(presentation_events)
	hud.consume_events(presentation_events)
	hud.refresh(sim)
	if not sim.result.is_empty():
		_enter_mode("result")


func _advance_battle() -> void:
	var turn := 0
	if _can_command():
		turn = int(_held.has("turn_right")) - int(_held.has("turn_left"))
	session.set_steer(turn)  # every tick (S3); 0 while the menu is open or the ship is out
	var events := []
	for batch in buffer.advance():  # one normalize per tick keeps volleys per tick
		events.append_array(Presentation.normalize_events(batch))
	var allies := _live_allies()
	if spectate_id >= 0 and not spectate_id in allies:  # the watched ally left: the next one, or the own wreck
		var later := allies.filter(func(id): return id > spectate_id)
		spectate_id = later[0] if not later.is_empty() else (allies[0] if not allies.is_empty() else -1)
	if battle_menu.defeat_open:
		battle_menu.watch_button.disabled = allies.is_empty()
	combat_audio.consume(events)
	arena_view.advance_effects()
	hud.advance_effects()
	arena_view.consume_events(events)
	hud.consume_events(events)
	hud.refresh(sim)


## Steering and actions reach the server only from an open battle with the own ship afloat.
func _can_command() -> bool:
	return mode == "battle" and not battle_menu.menu_open and own_outcome == "" \
		and sim.ships.has(own_ship_id) and sim.ships[own_ship_id]["active"]


## Other captain ships still afloat and fighting, by id: the ships a defeated captain can watch.
func _live_allies() -> Array:
	var ids := []
	for id in sim.ships:
		if id != own_ship_id and sim.ships[id]["team"] == NavalSimulation.TEAM_PLAYER and sim.ships[id]["active"]:
			ids.append(id)
	ids.sort()
	return ids


## Defeated and watching (the defeat panel and menu closed): turn presses switch the watched ally.
func _spectating() -> bool:
	return mode == "battle" and own_outcome != "" and not battle_menu.defeat_open and not battle_menu.menu_open


## Steps through the live allies, wrapping; from the own wreck right picks the first, left the last.
func _cycle_spectate(step: int) -> void:
	var allies := _live_allies()
	if allies.is_empty():
		spectate_id = -1
		return
	var i := allies.find(spectate_id)
	i = (0 if step > 0 else allies.size() - 1) if i < 0 else posmod(i + step, allies.size())
	spectate_id = allies[i]


## Camera/audio focus: the spectated ship while it exists, else the own ship.
func focus_ship_id() -> int:
	return spectate_id if spectate_id >= 0 and sim.ships.has(spectate_id) else own_ship_id


## A duel is any non-practice encounter (practice has no AI opponent that acts).
func _is_duel() -> bool:
	return mode == "sailing" and sim.preset_id != PRESET and not sim.ships.is_empty()


func start_practice(vessel_id: String) -> void:
	start_encounter(PRESET, vessel_id)


## Unified fresh start for every encounter: one AI reset, one signal, clean latches.
func start_encounter(preset_id: String, vessel_id: String) -> void:
	if not Definitions.PRESETS.has(preset_id) or not Definitions.VESSELS.has(vessel_id):
		push_error("start_encounter: unknown preset '%s' or vessel '%s'" % [preset_id, vessel_id])
		return
	sim.reset(preset_id, vessel_id)
	ai.reset()
	_reset_identity()
	hud.reset_effects()
	arena_view.reset_effects()
	_enter_mode("sailing")
	combat_audio.start_encounter()
	practice_started.emit()


func restart_practice() -> void:
	if mode != "selection":
		start_encounter(sim.preset_id, sim.selected_vessel_id)


func return_to_selection() -> void:
	combat_audio.clear()
	sim = NavalSimulation.new()
	ai = AIController.new()
	_reset_identity()
	hud.reset_effects()
	arena_view.reset_effects()
	_enter_mode("selection")


## Multiplayer: the remembered connection fills the connect form.
func open_multiplayer() -> void:
	mp_config.load_config()
	_enter_mode("connect")
	multiplayer_menu.show_form(mp_config.values)


## Harbor Disconnect: back to the form, no network.
func disconnect_session() -> void:
	session.disconnect_from()
	_reset_battle_state()
	_enter_mode("connect")
	multiplayer_menu.show_form(mp_config.values)


func _on_connect_requested(host: String, port: int, captain_name: String, password: String) -> void:
	mp_config.remember(host, port, captain_name, password)  # best effort: a failed save still connects
	multiplayer_menu.show_connecting(host, port)
	var err: Error = session.connect_to(host, port, captain_name.strip_edges(), password, mp_config.values["captain_id"])
	if err != OK:
		multiplayer_menu.show_status("Could not connect (%s)." % error_string(err))


func _on_connect_back() -> void:
	session.disconnect_from()
	_enter_mode("selection")


func _on_connected(_slot: int) -> void:
	if mode == "connect":
		_enter_mode("harbor")


func _on_auth_refused(reason: String, server_version: String) -> void:
	multiplayer_menu.show_status(MultiplayerMenu.refusal_text(reason, update_service.version, server_version))


func _on_refused(reason: String) -> void:
	harbor_menu.show_notice(HarborMenu.refused_text(reason))
	harbor_menu.set_waiting(false)


func _on_connection_ended(reason: String) -> void:
	_reset_battle_state()
	_enter_mode("connect")
	multiplayer_menu.show_status(MultiplayerMenu.ENDED_TEXT.get(reason, "Disconnected."))


## The server put this captain in a battle (start, join or reclaim): mirror it from now on.
func _on_joined(info: Dictionary) -> void:
	if mode != "harbor":
		return
	battle_id = int(info.get("battle_id", 0))
	own_ship_id = int(info.get("ship_id", 0))
	captains = info["captains"].duplicate(true) if info.get("captains") is Dictionary else {}
	buffer = SnapshotBuffer.new(battle_id)
	sim = buffer.mirror
	own_outcome = ""
	spectate_id = -1
	hud.reset_effects()
	arena_view.reset_effects()
	combat_audio.arena_view = arena_view
	_enter_mode("battle")
	combat_audio.start_encounter()
	practice_started.emit()


## Own outcomes. Sunk/disabled keeps the captain in the battle behind the defeat panel; escaped or
## abandoned returns to the harbor. An outcome from a battle left earlier only leaves a notice.
func _on_outcome(info: Dictionary) -> void:
	var outcome := str(info.get("outcome", ""))
	if mode != "battle" or int(info.get("battle_id", 0)) != battle_id:
		var notice := HarborMenu.outcome_notice(outcome)
		if notice != "":
			harbor_menu.show_notice(notice)
		return
	match outcome:
		"sunk", "disabled":
			own_outcome = outcome
			_clear_input()
			battle_menu.show_defeat(outcome, not _live_allies().is_empty())
			if settings_menu.visible:  # opened from the battle menu: the defeat panel waits behind it
				battle_menu.visible = false
		"escaped", "abandoned":
			_enter_harbor(HarborMenu.outcome_notice(outcome))


## The shared result of this battle: every captain still subscribed sees the same dictionary.
func _on_battle_result(for_battle: int, result: Dictionary) -> void:
	if mode != "battle" or for_battle != battle_id:
		return
	buffer.sample(buffer.newest_tick)  # freeze on the final state the result describes
	sim.result = result.duplicate(true)
	combat_audio.clear()
	_close_battle_overlays()
	_enter_mode("battle_result")


func _on_watch() -> void:
	battle_menu.hide_defeat()
	var allies := _live_allies()
	spectate_id = allies[0] if not allies.is_empty() else -1
	get_viewport().gui_release_focus()
	hud.refresh(sim)


## Result Return: offline back to the selection menu, a shared battle back to the harbor.
func _on_result_return() -> void:
	if mode == "battle_result":
		_enter_harbor("")
	else:
		return_to_selection()


func _on_snapshot(snapshot: Dictionary) -> void:
	if buffer != null:
		buffer.push_snapshot(snapshot)


## captain_info names a dropped-in or reclaimed ship before its events reach the views.
func _on_events(for_battle: int, events: Array) -> void:
	if buffer == null or for_battle != battle_id:
		return
	for event in events:
		if event is Dictionary and event.get("type") == "captain_info":
			captains[int(event.get("ship_id", 0))] = {"name": str(event.get("name", "")), "slot": int(event.get("slot", 0))}
	buffer.push_events(events)


## Opens or closes the non-pausing battle menu; held input never carries across.
func set_battle_menu(open: bool) -> void:
	if mode != "battle":
		return
	_clear_input()
	if open:
		battle_menu.open_menu(sim.preset_id)
	else:
		battle_menu.close_menu()
		if not battle_menu.defeat_open:
			get_viewport().gui_release_focus()


## Leave battle: the ship lingers on the server (reclaimable for 30 s) while we return to the harbor.
func leave_battle() -> void:
	session.leave_battle()
	_enter_harbor(LEAVE_NOTICE if own_outcome == "" else "")


func _enter_harbor(notice: String) -> void:
	_reset_battle_state()
	_enter_mode("harbor")
	harbor_menu.show_notice(notice)


## Drops everything a shared battle left behind (no network).
func _reset_battle_state() -> void:
	combat_audio.clear()
	sim = NavalSimulation.new()
	buffer = null
	battle_id = 0
	own_outcome = ""
	_reset_identity()
	hud.reset_effects()
	arena_view.reset_effects()
	_close_battle_overlays()


func _close_battle_overlays() -> void:
	battle_menu.hide_defeat()
	battle_menu.close_menu()
	if settings_menu.visible:  # opened from the battle menu when the battle went away
		settings_menu.release_all()
		settings_menu.hide()


func _reset_identity() -> void:
	own_ship_id = NavalSimulation.PLAYER_ID
	captains = {}
	spectate_id = -1


func set_paused(value: bool) -> void:
	if value and mode == "sailing":
		combat_audio.set_paused(true)
		_enter_mode("paused")
	elif not value and mode == "paused":
		_enter_mode("sailing")
		combat_audio.set_paused(false)


## Overlays the settings menu on the selection, pause or battle menu. No reset, no resume
## (a battle keeps running and stays uncommandable: its menu remains open underneath).
func open_settings() -> void:
	var from_battle: bool = mode == "battle" and battle_menu.menu_open
	if (mode not in ["selection", "paused"] and not from_battle) or settings_menu.visible:
		return
	_clear_input()
	selection.visible = false
	pause_menu.visible = false
	battle_menu.visible = false
	settings_menu.open(settings)


## Restores the source menu and focuses its Settings button.
func close_settings() -> void:
	_clear_input()
	settings_menu.visible = false
	var source: Control = pause_menu if mode == "paused" else (battle_menu if mode == "battle" else selection)
	source.visible = true
	source.settings_button.grab_focus()


## Live prompts follow applied bindings; the load notice clears once a save succeeds.
func _on_settings_changed() -> void:
	selection.show_notice(settings.notice)
	if mode == "paused":
		pause_menu.show_help(sim)
	elif mode == "battle":
		battle_menu.refresh_help(sim.preset_id)


## Settings gets every event first while open (capture, then Escape = Back); gameplay sees none.
## Release events are observed in every mode; presses count only while sailing or commanding a
## shared battle, where each action press goes to the server at once.
## Keys held across a transition stay inert until released and pressed again.
func _input(event: InputEvent) -> void:
	if settings_menu.visible:
		var consumed: bool = settings_menu.handle_capture(event)
		if not consumed and event is InputEventKey and event.pressed and not event.echo \
				and event.keycode == KEY_ESCAPE:
			settings_menu.back()
			consumed = true
		if consumed:
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey:
		return  # mouse never steers
	for action in TURN_ACTIONS:
		if event.is_action(action):
			if not event.pressed:
				_held.erase(action)
			elif (mode == "sailing" or _can_command()) and not event.echo:
				_held[action] = true
			elif _spectating() and not event.echo:
				_cycle_spectate(1 if action == "turn_right" else -1)
	if mode == "sailing":
		if event.is_action_pressed("toggle_sails"):  # is_action_pressed excludes echoes
			_toggle_queued = not _toggle_queued
		for action in EDGE_ACTIONS:
			if event.is_action_pressed(action):
				_edges[action] = true
		if event.is_action_pressed("reset_practice"):
			_reset_queued = true
	if _can_command():
		for action in BATTLE_ACTIONS:
			if event.is_action_pressed(action):
				session.send_action(action)
	if event.is_action_pressed("pause") and mode == "battle":
		set_battle_menu(not battle_menu.menu_open)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and mode in ["sailing", "paused"]:
		set_paused(mode == "sailing")
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_input()
		settings_menu.release_all()
		if mode == "result":
			combat_audio.set_paused(true)
		set_paused(true)  # focus-in deliberately never resumes


func _enter_mode(new_mode: String) -> void:
	mode = new_mode
	if mode == "result":
		combat_audio.finish_encounter()
	_clear_input()
	selection.visible = mode == "selection"
	multiplayer_menu.visible = mode == "connect"
	harbor_menu.visible = mode == "harbor"
	hud.visible = mode in HUD_MODES
	pause_menu.visible = mode == "paused"
	result_menu.visible = mode in ["result", "battle_result"]
	match mode:
		"selection":
			selection.show_mode_select()
		"harbor":
			harbor_menu.open()
		"paused":
			pause_menu.show_help(sim)
			pause_menu.resume_button.grab_focus()
		"sailing", "battle":
			get_viewport().gui_release_focus()
		"result":
			result_menu.show_result(sim)
		"battle_result":
			result_menu.show_battle_result(sim, own_ship_id, captains)
	if hud.visible:
		hud.refresh(sim)
	mode_changed.emit(mode)


func _clear_input() -> void:
	_held.clear()
	_toggle_queued = false
	_edges.clear()
	_reset_queued = false


## Shared UI look: >= 18 px text, white outlined labels, semi-opaque dark panels.
func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_type_variation("NauticalHeading", "Label")
	theme.set_font("font", "NauticalHeading", preload("res://assets/fonts/DejaVuSerif-headings.ttf"))
	theme.set_font_size("font_size", "NauticalHeading", 24)
	theme.set_color("font_color", "NauticalHeading", Color(.98, .87, .59))
	for type in ["Label", "Button"]:
		theme.set_font_size("font_size", type, 20)
	theme.set_color("font_color", "Label", Color.WHITE)
	theme.set_color("font_outline_color", "Label", Color.BLACK)
	theme.set_constant("outline_size", "Label", 4)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.07, 0.12, 0.82)
	panel.border_color = Color(.72, .57, .28, .9)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(3)
	panel.set_content_margin_all(10)
	theme.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var button := panel.duplicate()
		button.bg_color = Color(.05, .13, .22, .94) if state in ["hover", "focus"] else Color(.03, .09, .16, .88)
		button.border_color = Color(.95, .8, .43) if state == "focus" else panel.border_color
		theme.set_stylebox(state, "Button", button)
		theme.set_stylebox(state, "OptionButton", button)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.6)
	bar_bg.set_corner_radius_all(2)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.95, 0.82, 0.45)
	bar_fill.set_corner_radius_all(2)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)
	return theme


func _ornament_panels(node: Node) -> void:
	if node is PanelContainer:
		var panel: PanelContainer = node
		panel.draw.connect(func():
			var ink := Color(.78, .64, .35, .7)
			for corner in [Vector2(5, 5), Vector2(panel.size.x - 5, 5), Vector2(5, panel.size.y - 5), panel.size - Vector2(5, 5)]:
				var inward: Vector2 = (panel.size * .5 - corner).sign()
				panel.draw_line(corner, corner + Vector2(inward.x * 7, 0), ink, 1)
				panel.draw_line(corner, corner + Vector2(0, inward.y * 7), ink, 1))
	for child in node.get_children():
		_ornament_panels(child)


## CanvasLayer has no Control parent to supply an anchor rectangle.
func _fit_ui() -> void:
	for control in [hud, battle_menu, pause_menu, result_menu, selection, multiplayer_menu, harbor_menu, settings_menu]:
		control.set_anchors_preset(Control.PRESET_TOP_LEFT)
		control.position = Vector2.ZERO
		control.size = get_viewport().get_visible_rect().size
