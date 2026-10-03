extends RefCounted
## Ship identities derived from the roster (no fixed ids): labels, badges, shapes, and the
## HUD / camera / feedback wiring for a battle sim with captain ships >= FIRST_CAPTAIN_SHIP_ID.

const Sim := preload("res://sim/naval_simulation.gd")


func _battle(preset: String, captains: Array) -> Object:  # captains: [[ship_id, vessel_id], ...]
	var s = Sim.new()
	s.reset_battle(preset)
	var ops := captains.map(func(c): return {"op": "add_captain", "ship_id": c[0], "vessel_id": c[1]})
	s.step(1.0 / 60.0, {}, ops)
	return s


func run(t) -> bool:
	var p = load("res://view/combat_presentation.gd").new()
	var F: int = Sim.FIRST_CAPTAIN_SHIP_ID
	var escort = _battle("frigate_escort", [[F, "brig"]])
	t.check(p.opposition_ids(escort) == [2, 3, 4], "opposition ids are the sorted AI fleet")
	t.check([2, 3, 4].map(func(id): return p.ship_label(escort, id)) == ["Frigate A", "Sloop B", "Sloop C"],
		"three opponents are named by vessel and letter")
	t.check([2, 3, 4].map(func(id): return p.marker_badge(escort, id)) == ["A", "B", "C"],
		"three opponents badge by letter")
	t.check([2, 3, 4].map(func(id): return p.identity_shape(escort, id)) == ["triangle", "diamond", "square"],
		"opposition shapes follow opposition order")
	escort.ships[3]["active"] = false
	t.check(p.opposition_ids(escort) == [2, 3, 4] and p.ship_label(escort, 4) == "Sloop C",
		"a defeated opponent keeps its place and the others keep their letters")
	var duel = _battle("duel_brig", [[F, "sloop"]])
	t.check(p.ship_label(duel, 2) == "Enemy A (Brig)" and p.marker_badge(duel, 2) == "Enemy A",
		"one battle opponent reads like the offline duel")
	var captains := {F: {"name": "Anne", "slot": 0}, F + 1: {"name": "Bob", "slot": 1}}
	var pair = _battle("frigate_escort", [[F, "brig"], [F + 1, "sloop"]])
	t.check(p.ship_label(pair, F + 1, captains) == "Bob" and p.marker_badge(pair, F + 1, captains) == "2 Bob"
		and p.identity_shape(pair, F + 1) == "ring", "captain ships use name, slot badge and ring")
	t.check(p.ship_label(pair, F + 1) == "Ally" and p.ship_label(pair, 2, captains) == "Frigate A",
		"an unnamed friendly ship is an Ally; captains never rename the opposition")
	t.check(p.short_name("Abcdefghijklmnop") == "Abcdefghi…" and p.short_name("Anne") == "Anne"
		and p.short_name("Abcdefghij") == "Abcdefghij", "short names cut past ten characters")
	t.check(p.GLYPHS["triangle"] == "▲" and p.GLYPHS["diamond"] == "◆" and p.GLYPHS["square"] == "■"
		and p.GLYPHS["ring"] == "●" and p.LETTERS == "ABCD", "glyphs and letters")
	_test_wiring(t, captains)
	t.check(_test_allies(t) == true, "ally presentation checks completed")
	return true


func _test_wiring(t, captains: Dictionary) -> void:
	var F: int = Sim.FIRST_CAPTAIN_SHIP_ID
	var main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	var view = main.arena_view
	view.set_process(false)
	var hud = main.hud
	t.check(hud.main == main and main.own_ship_id == Sim.PLAYER_ID and main.captains.is_empty()
		and main.spectate_id == -1, "offline identity defaults and HUD back-reference")
	main.sim = _battle("frigate_escort", [[F, "brig"], [F + 1, "sloop"]])
	main.own_ship_id = F
	main.captains = captains
	hud.refresh(main.sim)
	t.check("Brig" in hud.name_label.text, "HUD own card follows the own ship")
	t.check("Frigate A" in hud.target_label.text and "Sloop B" in hud.second_target_label.text
		and "Sloop C" in hud.third_target_label.text, "three opponent rows")
	var lines: Array = [hud.target_label, hud.second_target_label, hud.third_target_label]
	var glyphs := ["▲", "◆", "■"]
	for i in lines.size():
		var line: Label = lines[i]
		t.check(hud.panels[1].is_ancestor_of(line) and line.visible and line.get_theme_font_size("font_size") == 16
			and line.text.begins_with(glyphs[i]) and line.text.count(" · ") == 3,
			"opponent %d is one 16 px line in the shared card: %s" % [i, line.text])
	t.check(not hud.panels[2].visible and hud._enemy_detail_rows.all(func(r): return not r.visible),
		"second enemy card hidden and compact card detail rows hidden")
	t.check(hud.panels[1].get_combined_minimum_size().y <= 144, "compact enemy card stays short (%s)" % hud.panels[1].get_combined_minimum_size().y)
	main.sim.ships[3]["active"] = false
	main.sim.ships[3]["defeat_reasons"] = ["sunk"]
	hud.refresh(main.sim)
	t.check(hud.defeated_notice.text == "1 of 3 enemies defeated" and "SUNK" in hud.second_target_label.text,
		"defeated count and compact state cover every opponent")
	hud.consume_events([{"type": "empty", "ship_id": F, "side": "port"}])
	hud.refresh(main.sim)
	t.check(hud.feedback_labels["port"].visible and hud.feedback_labels["port"].text == "no loaded guns",
		"own-ship empty event shows port feedback")
	hud.reset_effects()
	hud.consume_events([{"type": "empty", "ship_id": 1, "side": "port"}])
	hud.refresh(main.sim)
	t.check(not hud.feedback_labels["port"].visible, "ship 1 is not the own ship in a battle")
	var own: Dictionary = main.sim.ships[F]
	view._on_practice_started()
	t.check(view.camera.position.distance_to(own["position"]) <= 160.0,
		"camera follows the own captain ship (%s)" % view.camera.position.distance_to(own["position"]))
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var ready: Dictionary = view.readiness_geometry(main.sim, own["position"], screen)
	t.check(not ready.is_empty() and ready.port.dots.size() == own["weapons"]["port"]["loads"].size(),
		"readiness strips belong to the own ship")
	main.spectate_id = F + 1
	t.check(main.focus_ship_id() == F + 1, "spectating focuses the spectated ship")
	main.spectate_id = 999
	t.check(main.focus_ship_id() == F, "a missing spectate target falls back to the own ship")
	main.return_to_selection()
	t.check(main.own_ship_id == Sim.PLAYER_ID and main.captains.is_empty() and main.spectate_id == -1,
		"return to selection restores offline identity")
	main.start_encounter("two_sloops", "sloop")
	hud.refresh(main.sim)
	t.check(hud.panels[2].visible and hud.panels[2].is_ancestor_of(hud.second_target_label)
		and not hud.third_target_label.visible and hud.target_label.get_theme_font_size("font_size") == 20
		and hud._enemy_detail_rows.all(func(r): return r.visible),
		"two opponents restore the two-card layout after a compact battle")
	main.return_to_selection()
	main.free()


## Allied captains: slot colors, rings, labels, edge markers, HUD rows and the hit-ally notice.
func _test_allies(t) -> bool:
	var p = load("res://view/combat_presentation.gd")
	var F: int = Sim.FIRST_CAPTAIN_SHIP_ID
	t.check(p.SLOT_COLORS == [Color("56b4e9"), Color("f0e442"), Color("cc79a7"), Color.WHITE]
		and p.slot_color(1) == Color("f0e442"), "slot colors")
	var raw := {"type": "hit", "projectile_id": 9, "victim_id": F + 1, "owner_id": F, "track": "hull",
		"damage": 8.0, "ammo": "round", "position": Vector2.ZERO}
	var offline_raw := raw.duplicate()
	offline_raw.erase("owner_id")
	t.check(p.normalize_events([offline_raw])[0]["owner_id"] == -1, "offline hits carry no owner")
	var main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	var view = main.arena_view
	view.set_process(false)
	var hud = main.hud
	var sim = _battle("brig_squadron", [[F, "sloop"], [F + 1, "sloop"], [F + 2, "sloop"]])
	sim.step(1.0 / 60.0, {}, [{"op": "linger", "ship_id": F + 1}])
	sim.ships[F + 2]["active"] = false
	sim.ships[F + 2]["defeat_reasons"] = ["sunk"]
	main.sim = sim
	main.own_ship_id = F
	main.captains = {F: {"name": "Anne", "slot": 0}, F + 1: {"name": "Abcdefghijklmnop", "slot": 1},
		F + 2: {"name": "Cora", "slot": 2}}
	t.check(p.condition_short(sim.ships[F]) == "H 100% S 100% C 100%", "short condition")
	t.check(view.ally_label(sim, F + 1) == "2 Abcdefghi… · AWAY" and view.ally_label(sim, F + 2) == "3 Cora",
		"ally labels: slot, short name, away")
	hud.refresh(sim)
	var rows: Array = hud.ally_labels
	t.check(rows.size() == 3 and rows.all(func(r): return r.get_theme_font_size("font_size") == 16),
		"three 16 px ally rows")
	t.check(rows[0].visible and "Abcdefghi…" in rows[0].text and "AWAY" in rows[0].text
		and rows[0].text.begins_with("●2 ") and rows[0].get_theme_color("font_color") == p.slot_color(1),
		"lingering ally row: %s" % rows[0].text)
	t.check(rows[1].visible and rows[1].text == "●3 Cora %s · SUNK" % p.condition_short(sim.ships[F + 2])
		and rows[1].get_theme_color("font_color") == p.slot_color(2), "sunk ally row: %s" % rows[1].text)
	t.check(not rows[2].visible and not rows.any(func(r): return "Anne" in r.text), "no row for the own ship")
	t.check(hud.name_label.text.begins_with("●1 Anne · "), "own card name carries slot and name")
	t.check(hud.ally_panel.visible and hud.roster_row.get_child(-1) == hud.ally_panel
		and hud.panels.find(hud.ally_panel) == 6, "allies card is the last roster card and panel")
	hud.consume_events(p.normalize_events([raw]))
	hud.refresh(sim)
	t.check(hud.ally_notice.visible and hud.ally_notice.text == "hit ally Abcdefghi…!", "own hit on an ally is called out")
	t.check(12 + hud.ally_panel.get_combined_minimum_size().y <= 160,
		"allies card with the notice stays short (%s)" % hud.ally_panel.get_combined_minimum_size().y)
	var own_height: float = hud.panels[0].get_combined_minimum_size().y
	t.check(12 + own_height <= p.gameplay_rect(Vector2(1280, 720)).position.y,
		"own card clears the combat area (%s)" % own_height)
	t.check(hud.roster_row.get_combined_minimum_size().x <= 1280 - 2 * hud.MARGIN,
		"roster with allies fits 1280 (%s)" % hud.roster_row.get_combined_minimum_size().x)
	for i in 90:
		hud.advance_effects()
	hud.refresh(sim)
	t.check(not hud.ally_notice.visible, "ally notice expires after 90 ticks")
	var enemy_hit := raw.duplicate()
	enemy_hit["victim_id"] = 2
	hud.consume_events(p.normalize_events([enemy_hit]))
	hud.refresh(sim)
	t.check(not hud.ally_notice.visible, "hitting an enemy is not an ally notice")
	var focus: Vector2 = sim.ships[F]["position"]
	for id in sim.ships:
		if id != F:
			sim.ships[id]["position"] = focus + Vector2(2500, 0)
	view._on_practice_started()
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var markers: Dictionary = view.enemy_markers(sim, view.camera.position, screen)
	t.check(markers.has(2) and markers.has(3) and markers.has(4) and markers.has(F + 1)
		and not markers.has(F) and not markers.has(F + 2), "edge markers: enemies and the active ally (%s)" % [markers.keys()])
	t.check(view._marker_label(sim, F + 1) == "2 Abcdefghi… · AWAY" and " wu" in view._marker_label(sim, 2),
		"ally marker shows its label without distance")
	sim.ships.erase(F + 1)
	view.sync(sim)
	hud.refresh(sim)
	t.check(not view._ships.has(F + 1) and not view.enemy_markers(sim, view.camera.position, screen).has(F + 1)
		and rows[0].text.begins_with("●3 Cora") and not rows[1].visible, "a departed ally drops from view, markers and rows")
	main.sim = _battle("two_sloops", [[F, "frigate"], [F + 1, "sloop"]])
	hud.refresh(main.sim)
	t.check(hud.panels[2].visible and hud.ally_panel.visible
		and hud.roster_row.get_combined_minimum_size().x <= 1280 - 2 * hud.MARGIN,
		"two enemy cards plus allies fit 1280 (%s)" % hud.roster_row.get_combined_minimum_size().x)
	main.start_encounter("two_sloops", "sloop")
	hud.refresh(main.sim)
	t.check(not hud.ally_panel.visible and rows.all(func(r): return not r.visible)
		and not "●" in hud.name_label.text, "offline: no ally rows and no slot prefix")
	t.check(hud.panels[0].get_combined_minimum_size().y == own_height, "the battle prefix does not grow the own card")
	main.return_to_selection()
	main.free()
	return true
