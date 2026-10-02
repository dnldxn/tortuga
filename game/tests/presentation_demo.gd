extends SceneTree
## Development-only, paused simulation snapshots in the real main scene.
## Space: next snapshot. Escape: quit. --smoke: visit every snapshot headlessly.

const MainScene := preload("res://main.tscn")
const Definitions := preload("res://sim/definitions.gd")
const Presentation := preload("res://view/combat_presentation.gd")

var main: Node
var caption: Label
var snapshots: Array = []
var index := -1
var smoke := false
var started := false
var failures := 0
var valid := true
var space_held := false
var cleanup_frames := 0


func _initialize() -> void:
	var selected := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			selected = arg.trim_prefix("--case=")
		elif arg == "--smoke":
			smoke = true
		else:
			push_error("Unknown presentation demo argument: " + arg)
			valid = false
			quit(1)
			return
	match selected:
		"two-enemies": snapshots = [
			{"label": "A + B near · stable rows", "kind": "near"},
			{"label": "A + B far · zoom floor, two edge markers", "kind": "far"},
			{"label": "A + B same east edge · separate labels", "kind": "same_edge"},
			{"label": "A + B adjacent corner · separate labels", "kind": "corner"},
			{"label": "Sloop A defeated (sails + crew) · survivor is still Sloop B", "kind": "a_defeated"},
		]
		"conditions": snapshots = [
			{"label": "Full tracks · intact sails / round volley", "kind": "full"},
			{"label": "49% hull + sails · cracks and tears / chain hit", "kind": "half"},
			{"label": "24% hull + sails · extra cracks and collapsed panels / grape hit", "kind": "quarter"},
			{"label": "A disabled — SAILS · B remains active", "kind": "sails"},
			{"label": "A disabled — CREW · B remains active", "kind": "crew"},
			{"label": "A disabled — SAILS + CREW · B remains active", "kind": "both"},
			{"label": "A SUNK · B remains active", "kind": "sunk"},
			{"label": "Missed shot · splash (no impact)", "kind": "splash"},
		]
		_:
			push_error("Unknown presentation demo case: " + selected + " (choose two-enemies, conditions)")
			valid = false
			quit(1)
			return


func _process(_delta: float) -> bool:
	if not valid:
		return false
	if cleanup_frames > 0:
		cleanup_frames -= 1
		if cleanup_frames == 0:
			quit(1 if failures else 0)
		return false
	if started:
		if Input.is_key_pressed(KEY_ESCAPE):
			quit(0)
		var pressed := Input.is_key_pressed(KEY_SPACE)
		if pressed and not space_held:
			show_snapshot((index + 1) % snapshots.size())
		space_held = pressed
		return false
	started = true
	main = MainScene.instantiate()
	root.add_child(main)
	main.set_physics_process(false)  # Synthetic state must never advance combat/AI.
	var panel := PanelContainer.new()
	panel.position = Vector2(32, 135)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.get_node("UI").add_child(panel)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 18)
	panel.add_child(caption)
	if smoke:
		for i in snapshots.size():
			show_snapshot(i)
		main.combat_audio.clear()
		for kind in main.combat_audio.effects:
			for player in main.combat_audio.effects[kind]:
				_check(not player.playing, "smoke teardown stops %s voice" % kind)
		_check(not main.combat_audio.ambient.playing, "smoke teardown stops sea voice")
		print("Presentation demo: %d snapshots visited, %d failures" % [snapshots.size(), failures])
		main.queue_free()
		cleanup_frames = 10  # allow audio teardown to drain before engine shutdown
	else:
		show_snapshot(0)
	return false


func show_snapshot(next: int) -> void:
	index = next
	var kind: String = snapshots[index]["kind"]
	main.start_encounter("two_sloops", "frigate")
	# Clone the reset state; fixture edits affect this snapshot only, never definitions or sim rules.
	var sim = main.sim
	sim.ships = sim.ships.duplicate(true)
	var player: Dictionary = sim.ships[1]
	var origin: Vector2 = player["position"]
	var raw_events := []
	match kind:
		"near":
			sim.ships[2]["position"] = origin + Vector2(0, -300)
			sim.ships[3]["position"] = origin + Vector2(0, 300)
		"far":
			sim.ships[2]["position"] = origin + Vector2(2400, -600)
			sim.ships[3]["position"] = origin + Vector2(-2400, 600)
		"same_edge":
			sim.ships[2]["position"] = origin + Vector2(2500, -100)
			sim.ships[3]["position"] = origin + Vector2(2500, 100)
		"corner":
			sim.ships[2]["position"] = origin + Vector2(2700, -1100)
			sim.ships[3]["position"] = origin + Vector2(2700, -300)
		"a_defeated", "sails", "crew", "both", "sunk":
			sim.ships[2]["position"] = origin + Vector2(0, -320)
			sim.ships[3]["position"] = origin + Vector2(0, 320)
			var reasons: Array = {"a_defeated": ["sails", "crew"], "sails": ["sails"],
				"crew": ["crew"], "both": ["sails", "crew"], "sunk": ["sunk"]}[kind]
			var enemy: Dictionary = sim.ships[2]
			enemy["active"] = false
			enemy["defeat_reasons"] = reasons.duplicate()
			for reason in reasons:
				if reason == "sunk":
					enemy["hull"] = 0.0
				else:
					enemy[reason] = 0.0
			raw_events.append({"type": "ship_defeated", "ship_id": 2,
				"position": enemy["position"], "reasons": reasons.duplicate()})
		"full", "half", "quarter", "splash":
			for id in [2, 3]:
				sim.ships[id]["position"] = origin + Vector2(0, -320 if id == 2 else 320)
			if kind in ["half", "quarter"]:
				for track in ["hull", "sails"]:
					player[track] = Definitions.VESSELS["frigate"][track] * (.49 if kind == "half" else .24)
			if kind in ["full", "half", "quarter"]:
				var ammo: String = {"full": "round", "half": "chain", "quarter": "grape"}[kind]
				var track: String = Definitions.AMMO[ammo]["track"]
				player["weapons"]["port"]["ammo"] = ammo
				for gun in 8:
					raw_events.append({"type": "shot", "ship_id": 1, "side": "port",
						"gun_index": gun, "projectile_id": gun + 1, "ammo": ammo,
						"position": origin, "direction": Vector2.UP})
				raw_events.append({"type": "hit", "projectile_id": 1, "victim_id": 2,
					"position": sim.ships[2]["position"], "track": track,
					"ammo": ammo, "damage": Definitions.AMMO[ammo]["damage"]})
				raw_events.append({"type": "hit", "projectile_id": 2, "victim_id": 2,
					"position": sim.ships[2]["position"], "track": track,
					"ammo": ammo, "damage": Definitions.AMMO[ammo]["damage"]})
			else:
				raw_events.append({"type": "splash", "projectile_id": 1,
					"position": origin + Vector2(0, -380)})
	main.arena_view.reset_effects()  # Snap to this synthetic snapshot, not the preset's prior camera.
	main.arena_view.sync(sim)
	main.arena_view._fit_camera(0.0)
	main.hud.refresh(sim)
	# Same per-tick path as main.advance_tick(): raw shots -> one volley -> audio/visuals.
	var events: Array = Presentation.normalize_events(raw_events)
	main.combat_audio.consume(events)
	main.arena_view.consume_events(events)
	main.hud.consume_events(events)
	if kind in ["full", "half", "quarter"]:
		for tick in 6:
			main.arena_view.advance_effects()  # settle damage text, without stepping the sim
	main.hud.refresh(sim)
	if smoke:
		check_snapshot(kind, events)
	caption.text = "DEMO %d/%d · %s\nSpace: next snapshot   Esc: quit" % [
		index + 1, snapshots.size(), snapshots[index]["label"]]
	print("Presentation demo %d/%d: %s" % [index + 1, snapshots.size(), snapshots[index]["label"]])


func check_snapshot(kind: String, events: Array) -> void:
	var sim = main.sim
	var hud = main.hud
	_check(hud.target_label.text.contains("Sloop A") and hud.second_target_label.text.contains("Sloop B"), "stable A/B rows")
	if kind in ["far", "same_edge", "corner"]:
		var view = main.arena_view
		var markers: Dictionary = view.enemy_markers(sim, sim.ships[1]["position"],
			Rect2(Vector2.ZERO, view.marker_canvas.size))
		_check(markers.has(2) and markers.has(3), "%s shows two indicators" % kind)
		if markers.has(2) and markers.has(3):
			_check(not view.marker_label_rect(sim, 2, markers[2], sim.ships[1]["position"], Rect2(Vector2.ZERO, view.marker_canvas.size)).intersects(
				view.marker_label_rect(sim, 3, markers[3], sim.ships[1]["position"], Rect2(Vector2.ZERO, view.marker_canvas.size))),
				"%s indicator labels do not overlap" % kind)
			if kind == "corner":
				var safe: Rect2 = Presentation.gameplay_rect(view.marker_canvas.size)
				_check(is_equal_approx(view._marker_edges[2].y, safe.position.y)
					and is_equal_approx(view._marker_edges[3].x, safe.end.x)
					and view._marker_edge(view._marker_edges[2], safe) == "north"
					and view._marker_edge(view._marker_edges[3], safe) == "east",
					"corner true-edge classifications are adjacent north/east")
	if kind in ["full", "half", "quarter"]:
		_check(events.filter(func(e): return e["type"] == "shot").size() == 8
			and events.filter(func(e): return e["type"] == "volley").size() == 1,
			"eight raw shots produce one volley")
		_check(main.combat_audio.dispatch_counts["cannon"] == 1
			and main.combat_audio.dispatch_counts["impact"] == 1,
			"one cannon and one impact dispatched through production adapter")
		var ammo: String = {"full": "round", "half": "chain", "quarter": "grape"}[kind]
		var track: String = Definitions.AMMO[ammo]["track"]
		var damage: float = Definitions.AMMO[ammo]["damage"] * 2.0
		var cues := []
		for cue in main.arena_view._cues:
			if cue["type"] == "damage" and cue["target_id"] == 2 and cue["track"] == track:
				cues.append(cue)
		_check(cues.size() == 1 and cues[0]["settled"] and cues[0]["ticks"] > 0
			and is_equal_approx(cues[0]["damage"], damage),
			"%s damage text drawable: %s −%d" % [kind, track.capitalize(), roundi(damage)])
	if kind in ["a_defeated", "sails", "crew", "both", "sunk"]:
		_check(not sim.ships[2]["active"] and sim.ships[3]["active"]
			and hud.second_target_label.text.contains("Sloop B")
			and hud.target_state_label.text.contains("SUNK" if kind == "sunk" else "DISABLED"),
			"%s reason and survivor" % kind)
	if kind == "splash":
		_check(events.size() == 1 and events[0]["type"] == "splash"
			and main.combat_audio.dispatch_counts["splash"] == 1
			and main.combat_audio.dispatch_counts["impact"] == 0,
			"missed shot dispatches splash without impact")


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("Presentation demo FAIL: " + label)
