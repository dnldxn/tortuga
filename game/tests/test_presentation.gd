extends RefCounted

const Sim := preload("res://sim/naval_simulation.gd")


func run(t) -> bool:
	var script = load("res://view/combat_presentation.gd")
	t.check(script != null, "presentation calculation and event adapter loads")
	if script == null:
		return true
	var p = script.new()
	t.check(is_equal_approx(p.zoom_for_extent(Vector2(2000, 900), Vector2(608, 200)), 0.75), "camera zoom floor")
	t.check(is_equal_approx(p.zoom_for_extent(Vector2(10, 10), Vector2(608, 200)), 1.10), "camera zoom ceiling")
	var a := 1.1
	var b := 1.1
	for i in 60:
		a = p.approach(a, .75, 6.0, 1.0 / 60.0)
	for i in 30:
		b = p.approach(b, .75, 6.0, 1.0 / 30.0)
	t.check(a > .75 and a < 1.1 and absf(a - b) < .00001, "frame-rate independent smooth zoom")
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	t.check(p.edge_point(Vector2(3000, 360), screen) == Vector2(1280, 360), "edge ray intersection")
	var shots := []
	for i in 8:
		shots.append({"type": "shot", "ship_id": 1, "side": "port", "position": Vector2(i, 0), "direction": Vector2.UP})
	var first: Array = p.normalize_events(shots)
	t.check(first.size() == 9 and first[8] == {"type": "volley", "ship_id": 1, "side": "port", "position": Vector2.ZERO, "ready_count": 8}, "eight guns produce one volley and retain shots")
	shots.append({"type": "shot", "ship_id": 1, "side": "starboard", "position": Vector2.ZERO})
	t.check(p.normalize_events(shots).filter(func(e): return e["type"] == "volley").size() == 2, "opposite sides are separate volleys")
	t.check(p.normalize_events(shots).filter(func(e): return e["type"] == "volley").size() + first.filter(func(e): return e["type"] == "volley").size() == 3, "tick batches remain separate")
	var normalized: Array = p.normalize_events([{"type": "hit", "projectile_id": 7, "victim_id": 3, "position": Vector2.ONE, "track": "crew", "damage": 5, "ammo": "grape"}, {"type": "splash", "projectile_id": 8, "position": Vector2.ZERO}, {"type": "fire_rejected", "ship_id": 1, "side": "port", "reason": "no_loaded_guns"}, {"type": "ship_defeated", "ship_id": 2, "position": Vector2.ZERO, "reasons": ["sails", "crew"]}])
	t.check(normalized.map(func(e): return e["type"]) == ["hit", "splash", "empty", "defeated"] and normalized[0]["target_id"] == 3 and normalized[3]["reasons"] == ["sails", "crew"], "event fields translated at adapter")
	t.check(normalized[0]["projectile_id"] == 7 and normalized[0]["track"] == "crew" and normalized[0]["damage"] == 5 and normalized[0]["ammo"] == "grape" and normalized[1]["projectile_id"] == 8 and normalized[2]["ship_id"] == 1, "hit, splash and empty retain authoritative fields")
	var sim = Sim.new()
	sim.reset("two_sloops", "sloop")
	var before := {"ships": sim.ships.duplicate(true), "projectiles": sim.projectiles.duplicate(true), "result": sim.result.duplicate(true)}
	p.normalize_events(shots)
	t.check(sim.ships == before["ships"] and sim.projectiles == before["projectiles"] and sim.result == before["result"], "presentation adapter leaves simulation state unchanged")
	t.check(p.ship_label(sim, 2) == "Sloop A" and p.ship_label(sim, 3) == "Sloop B", "identity follows stable IDs")
	var duel = Sim.new()
	duel.reset("duel_brig", "sloop")
	t.check(p.ship_label(duel, 2) == "Enemy A (Brig)" and p.has_method("marker_badge")
		and p.call("marker_badge", duel, 2) == "Enemy A",
		"duel row and marker share the same ID-derived name")
	duel.reset("practice", "sloop")
	t.check(p.ship_label(duel, 2) == "Target" and p.has_method("marker_badge")
		and p.call("marker_badge", duel, 2) == "TARGET",
		"practice identity shared by HUD and marker")
	var main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	var view = main.arena_view
	view.set_process(false)
	main.start_encounter("two_sloops", "sloop")
	var hud = main.hud
	main.sim.result = {"outcome": "victory", "elapsed": 1.0,
		"defeated": [{"ship_id": 2, "reason": "sunk", "disabled_by": []}]}
	main.result_menu.show_result(main.sim)
	t.check(main.result_menu.detail_label.text.contains(p.ship_label(main.sim, 2))
		and main.result_menu.detail_label.text.contains(p.ship_label(main.sim, 3)),
		"result reasons and survivor names use shared stable identities")
	main.start_encounter("two_sloops", "sloop")
	var player_view: Node2D = view._ships[1]
	t.check(player_view.has_node("ConditionOverlay") and player_view.get_node("ConditionOverlay").get_index() > player_view.display_sprite.get_index(), "condition overlay renders above the ship sprite")
	main.sim.ships[1]["heading"] = PI / 3.0
	main.sim.ships[1]["hull"] = 49.0
	main.sim.ships[1]["sails"] = 34.0
	view.sync(main.sim)
	if player_view.has_node("ConditionOverlay"):
		var overlay: Node2D = player_view.get_node("ConditionOverlay")
		t.check(is_equal_approx(overlay.rotation, PI / 3.0) and overlay.get("hull_fraction") < .5 and overlay.get("sail_fraction") < .5, "condition strokes rotate with damaged ship and follow tracks")
		main.sim.ships[1]["sails"] = 70.0
		main.sim.ships[1]["reefed"] = true
		view.sync(main.sim)
		t.check(overlay.get("reefed") and overlay.get("sail_fraction") == 1.0, "reefed intact sail has no torn-sail state")
	main.start_encounter("two_sloops", "sloop")
	t.check(hud.panels[1].get_combined_minimum_size().y <= 144.0, "two enemy rows fit reserved top HUD height")
	t.check(not hud.panels[2].get_global_rect().intersects(hud.panels[3].get_global_rect())
		and not hud.panels[3].get_global_rect().intersects(hud.panels[4].get_global_rect()),
		"player tracks and side cards occupy separate bottom regions")
	var port_pips: Array = hud.gun_bars["port"]
	t.check(port_pips[0].get_child_count() > 0 and port_pips[0].get_child(0) is Label
		and port_pips[0].get_child(0).text == "●", "loaded gun uses filled pip")
	main.sim.ships[1]["weapons"]["port"]["loads"] = [0.5, 0.0, 1.0, 1.0]
	hud.refresh(main.sim)
	t.check(port_pips[0].get_child_count() > 0 and port_pips[0].get_child(0).text == "◑"
		and port_pips[1].get_child(0).text == "○", "partially reloading and empty guns use outlined pips")
	main.sim.ships[1]["weapons"]["port"]["ammo"] = "chain"
	main.sim.ships[1]["weapons"]["port"]["loads"].fill(0.0)
	hud.refresh(main.sim)
	t.check("LOAD RESET" in hud.ammo_labels["port"].text and "LOAD RESET" not in hud.ammo_labels["starboard"].text,
		"ammo change announces only that side's reload reset")
	t.check(hud.get("aim_icons") == null and hud.get("aim_labels") == null
		and not p.has_method("aim_label"), "no aim-assist status or symbol remains in the HUD")
	main.start_encounter("two_sloops", "sloop")
	main.sim.ships[2]["active"] = false
	main.sim.ships[2]["defeat_reasons"] = ["sails", "crew"]
	hud.refresh(main.sim)
	t.check(hud.target_label.text.contains("Sloop A") and hud.second_target_label.text.contains("Sloop B") and hud.target_state_label.text.contains("SAILS") and hud.target_state_label.text.contains("CREW"), "A defeat retains both fixed rows and reasons")
	main.start_encounter("two_sloops", "sloop")
	main.sim.ships[1]["heading"] = -PI / 2.0
	main._input(_key(KEY_E, true))
	main._input(_key(KEY_E, false))
	main.advance_tick()
	t.check(main.arena_view._cues.filter(func(c): return c["type"] == "shot").size() == 4 and main.sim.events.filter(func(e): return e["type"] == "shot").size() == 4, "fixed tick passes each successful gun event once to existing muzzle cues")
	t.check(main.combat_audio.dispatch_counts["cannon"] == 1,
		"controller sends one cannon for one successful four-gun volley")
	main.advance_tick()
	t.check(main.arena_view._cues.filter(func(c): return c["type"] == "shot").size() == 4, "next tick does not consume old sim events again")
	t.check(main.combat_audio.dispatch_counts["cannon"] == 1,
		"controller does not replay old volleys on the next tick")
	main.start_encounter("two_sloops", "sloop")
	var center: Vector2 = main.sim.ships[1]["position"]
	main.sim.ships[2]["position"] = center + Vector2(3000, 0)
	main.sim.ships[3]["position"] = center + Vector2(3100, 0)
	t.check(view._desired_camera_center(main.sim).distance_to(center) <= 160.0 and view._nearby.is_empty(), "remote enemies cannot bias player follow")
	t.check(p.zoom_for_extent(Vector2(3000, 3000), Vector2(608, 200)) == .75 and 44.0 * .75 == 33.0 and 22.0 * .75 == 16.5, "remote enemy cannot lower sloop footprint below floor")
	var roster: Dictionary = main.sim.ships
	roster[2]["position"] = center + Vector2(2500, -100)
	roster[3]["position"] = center + Vector2(2500, 100)
	var screen_rect := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var gameplay_safe: Rect2 = p.SAFE.grow(-24.0)
	var behind_hud: Vector2 = view.get_canvas_transform().affine_inverse() * Vector2(640, 100)
	roster[2]["position"] = behind_hud
	roster[3]["position"] = center + Vector2(2500, 100)
	var hud_markers: Dictionary = view.enemy_markers(main.sim, center, screen_rect)
	t.check(hud_markers.has(2) and view._marker_edges[2].y >= gameplay_safe.position.y,
		"enemy projected behind top HUD receives gameplay-edge indicator")
	behind_hud = view.get_canvas_transform().affine_inverse() * Vector2(640, 620)
	roster[2]["position"] = behind_hud
	hud_markers = view.enemy_markers(main.sim, center, screen_rect)
	t.check(hud_markers.has(2) and view._marker_edges[2].y <= gameplay_safe.end.y,
		"enemy projected behind bottom HUD receives gameplay-edge indicator")
	roster[2]["position"] = center + Vector2(2500, -100)
	var markers: Dictionary = view.enemy_markers(main.sim, center, screen_rect)
	t.check(markers.has(2) and markers.has(3) and not view.marker_label_rect(main.sim, 2, markers[2], center, screen_rect).intersects(view.marker_label_rect(main.sim, 3, markers[3], center, screen_rect)), "same-edge A/B labels do not intersect")
	roster[2]["position"] = center + Vector2(2500, 0)
	roster[3]["position"] = center + Vector2(2600, 0)
	t.check(view.has_method("indicator_geometry"), "drawing exposes resolved arrow and badge geometry")
	if view.has_method("indicator_geometry"):
		var drawn: Dictionary = view.indicator_geometry(main.sim, center, screen_rect)
		t.check(drawn.has(2) and drawn.has(3) and drawn[2]["arrow"].distance_to(drawn[3]["arrow"]) >= 24.0
			and drawn[2]["badge"].distance_to(drawn[3]["badge"]) >= 24.0,
			"same-bearing drawn arrows and identity badges separate, not just labels")
		t.check(drawn[2]["identity"] == "A" and drawn[3]["identity"] == "B"
			and drawn[2]["true_edge"] == view._marker_edges[2] and drawn[3]["true_edge"] == view._marker_edges[3]
			and drawn[3]["arrow"] != drawn[3]["true_edge"],
			"A/B identities remain attached to resolved arrow and leader reaches true edge: %s" % [drawn])
	roster[2]["position"] = center + Vector2(2000, -2000)
	roster[3]["position"] = center + Vector2(2400, -1600)
	markers = view.enemy_markers(main.sim, center, screen_rect)
	t.check(markers.has(2) and markers.has(3) and not view.marker_label_rect(main.sim, 2, markers[2], center, screen_rect).intersects(view.marker_label_rect(main.sim, 3, markers[3], center, screen_rect)), "adjacent corner A/B labels do not intersect")
	var safe_labels: Rect2 = p.gameplay_rect(screen_rect.size)
	for projected_pair in [[Vector2(1500, 520), Vector2(1260, 800)],
		[Vector2(1500, 200), Vector2(1260, -200)],
		[Vector2(-200, 520), Vector2(20, 800)]]:
		roster[2]["position"] = view.get_canvas_transform().affine_inverse() * projected_pair[0]
		roster[3]["position"] = view.get_canvas_transform().affine_inverse() * projected_pair[1]
		markers = view.enemy_markers(main.sim, center, screen_rect)
		var box_a: Rect2 = view.marker_label_rect(main.sim, 2, markers[2], center, screen_rect)
		var box_b: Rect2 = view.marker_label_rect(main.sim, 3, markers[3], center, screen_rect)
		t.check(safe_labels.encloses(box_a) and safe_labels.encloses(box_b) and not box_a.intersects(box_b),
			"adjacent-edge boxes fit gameplay rect without overlap at %s" % [projected_pair])
	roster[2]["active"] = false
	t.check(not view.enemy_markers(main.sim, center, screen_rect).has(2) and view.enemy_markers(main.sim, center, screen_rect).has(3) and view._marker_label(main.sim, 3).begins_with("B •"), "inactive A hidden, surviving B identity retained")
	var limits := Rect2(-240, -240, 6480, 4680)
	t.check(p.has_method("padded_art_half"), "rotated art-fit calculation available")
	if p.has_method("padded_art_half"):
		var wide: Vector2 = p.padded_art_half(34.0, 0.0)
		var tall: Vector2 = p.padded_art_half(34.0, PI / 2.0)
		var diagonal: Vector2 = p.padded_art_half(34.0, PI / 4.0)
		t.check(wide == Vector2(58, 41) and tall.x > 40.9 and tall.y > 57.9 and diagonal.x > 60.0 and diagonal.y > 60.0,
			"rotated 68×34 art corners plus 24 padding enlarge fit on both axes")
		main.start_encounter("practice", "frigate")
		main.sim.ships[1]["heading"] = PI / 4.0
		var rotated_bounds: Rect2 = view._active_bounds(main.sim)
		t.check(rotated_bounds.size.x >= diagonal.x * 2 and rotated_bounds.size.y >= diagonal.y * 2,
			"camera bounds use rotated frigate footprint")
	for zoom in [.75, 1.10]:
		for corner in [Vector2(182, 182), Vector2(5818, 182), Vector2(182, 4018), Vector2(5818, 4018)]:
			var c: Vector2 = p.clamp_center(corner, corner, zoom, Vector2(1280, 720), Vector2(6000, 4200))
			var half: Vector2 = Vector2(1280, 720) / (2.0 * zoom)
			var visible := Rect2(c - half, half * 2)
			var projected: Vector2 = Vector2(640, 360) + (corner - c) * zoom
			t.check(limits.encloses(visible) and p.SAFE.has_point(projected), "boundary framing %s zoom %.2f" % [corner, zoom])
	main.start_encounter("two_sloops", "sloop")
	var pos: Vector2 = view.camera.position
	var z: Vector2 = view.camera.zoom
	main.set_paused(true)
	main.sim.ships[1]["position"] += Vector2(200, 0)
	for i in 120:
		view._process(1.0 / 60.0)
	t.check(view.camera.position == pos and view.camera.zoom == z, "paused camera remains frozen")
	main.set_paused(false)
	var impacts := []
	for i in 100:
		impacts.append({"type": "hit", "projectile_id": i, "target_id": 2, "position": Vector2.ZERO, "track": "hull", "damage": 8.0, "ammo": "round"})
	view.consume_events(impacts)
	t.check(view._cues.size() <= 48, "impact cosmetics bounded to 48 records")
	var total: Array = view._cues.filter(func(c): return c["type"] == "damage" and c["target_id"] == 2 and c["track"] == "hull")
	t.check(total.size() == 1 and total[0]["damage"] == 800.0 and not total[0]["settled"],
		"100 simultaneous hits keep the actual unsettled damage total under cosmetic cap")
	view.consume_events(impacts.slice(0, 2))
	total = view._cues.filter(func(c): return c["type"] == "damage" and c["target_id"] == 2)
	t.check(total.size() == 1 and total[0]["damage"] == 816.0, "later same-window hits extend retained damage aggregate")
	view.reset_effects()
	view.consume_events(impacts.slice(0, 2))
	var damage: Array = view._cues.filter(func(c): return c["type"] == "damage")
	t.check(damage.size() == 1 and damage[0]["damage"] == 16.0, "two actual hull hits group damage for same track")
	for i in 6:
		view.advance_effects()
	t.check(view._cues.filter(func(c): return c["type"] == "damage")[0]["settled"], "damage group settles after .1 seconds")
	_test_controller_frames(t, main, p)
	main.restart_practice()
	t.check(view._cues.is_empty() and view._nearby.is_empty(), "restart clears presentation state")
	_test_audio(t, main, p)
	main.free()
	return true


func _test_audio(t, main, p) -> void:
	var script = load("res://audio/combat_audio.gd")
	t.check(script != null, "combat audio loads")
	if script == null:
		return
	var audio = main.get_node_or_null("CombatAudio")
	t.check(audio != null, "controller owns combat audio")
	if audio == null:
		return
	for bus in ["Master", "Effects", "Ambient"]:
		t.check(AudioServer.get_bus_index(bus) >= 0, "audio bus %s exists" % bus)
	var groups: Dictionary = audio.effects
	t.check(groups["cannon"].size() == 3 and groups["impact"].size() == 2
		and groups["splash"].size() == 1 and audio.get_child_count() == 7,
		"six bounded effect voices and one sea voice")
	for kind in groups:
		for player in groups[kind]:
			t.check(player.bus == &"Effects" and player.max_polyphony == 1
				and player.volume_db == -18.0 and player.stream.get_length() > 0,
				"%s player routes to Effects" % kind)
	t.check(audio.ambient.bus == &"Ambient" and audio.ambient.volume_db == -20.0
		and audio.ambient.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and audio.ambient.stream.loop_begin == 0
		and audio.ambient.stream.loop_end == 8 * 22050
		and is_equal_approx(audio.ambient.stream.get_length(), 8.0),
		"sea loops at exact sample boundary on Ambient")
	main.start_encounter("two_sloops", "sloop")
	t.check(audio.ambient.playing and not audio.ambient.stream_paused, "encounter starts one sea voice")
	var base: Dictionary = audio.dispatch_counts.duplicate()
	var shots := []
	for i in 8:
		shots.append({"type": "shot", "ship_id": 1, "side": "port", "position": Vector2.ZERO})
	audio.consume(p.normalize_events(shots))
	t.check(audio.dispatch_counts["cannon"] - base["cannon"] == 1, "eight guns dispatch one cannon")
	audio.consume(p.normalize_events(shots + [{"type": "shot", "ship_id": 1, "side": "starboard", "position": Vector2.ZERO}]))
	t.check(audio.dispatch_counts["cannon"] - base["cannon"] == 3, "separate ticks and sides dispatch separate volleys")
	audio.consume([{"type": "empty", "ship_id": 1, "side": "port"}])
	t.check(audio.dispatch_counts["cannon"] - base["cannon"] == 3, "empty fire is silent")
	var many_volleys := []
	for i in 20:
		many_volleys.append({"type": "volley", "ship_id": i + 1, "side": "port"})
	audio.consume(many_volleys)
	t.check(audio.dispatch_counts["cannon"] - base["cannon"] == 3,
		"busy cannon slots drop newest volleys without a playback queue")
	var hit := {"type": "hit", "target_id": 2, "track": "hull"}
	audio.consume([hit, hit, {"type": "hit", "target_id": 3, "track": "hull"}])
	t.check(audio.dispatch_counts["impact"] - base["impact"] == 2, "same target/track hits within window share impact")
	audio.consume([hit])
	t.check(audio.dispatch_counts["impact"] - base["impact"] == 2, "following tick hit still grouped")
	for i in 6:
		audio.consume([])
	audio.consume([hit, {"type": "splash"}])
	t.check(audio.hit_groups.has("2/hull") and audio.dispatch_counts["splash"] - base["splash"] == 1,
		"expired hit window and projectile expiry route to separate sounds")
	for kind in groups:
		t.check(audio.dispatch_counts[kind] - base[kind] <= groups[kind].size() + 1,
			"bounded %s voices drop newest while all slots busy" % kind)
	main.set_paused(true)
	t.check(audio.paused and audio.ambient.stream_paused
		and audio.hit_groups.is_empty(), "pause stops effects and clears grouping but pauses sea")
	var counts: Dictionary = audio.dispatch_counts.duplicate()
	audio.consume([hit, {"type": "volley"}, {"type": "splash"}])
	t.check(audio.dispatch_counts == counts, "paused events ignored")
	main._notification(main.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.check(audio.ambient.stream_paused, "focus return never auto-resumes sea")
	main.set_paused(false)
	t.check(not audio.ambient.stream_paused and audio.ambient.playing, "explicit resume keeps sea voice")
	main.return_to_selection()
	t.check(not audio.ambient.playing and audio.hit_groups.is_empty(), "selection clears audio")
	main.start_encounter("practice", "sloop")
	t.check(audio.ambient.playing and not audio.ambient.stream_paused, "replay starts one fresh sea voice")
	main.set_paused(true)
	main.restart_practice()
	t.check(audio.ambient.playing and not audio.ambient.stream_paused,
		"restart directly from pause starts audible sea")
	main.sim.result = {"outcome": "victory", "elapsed": 1.0,
		"defeated": [{"ship_id": 2, "reason": "sunk", "disabled_by": []}]}
	main._enter_mode("result")
	t.check(not audio.ambient.playing and audio.hit_groups.is_empty(), "result clears sea and pending sounds")
	var original_gain: Dictionary = main.settings.values.duplicate(true)
	var changed_gain: Dictionary = original_gain.duplicate(true)
	changed_gain["audio"]["ambient"] = 0.0
	changed_gain["audio"]["effects"] = 0.0
	main.settings.apply_values(changed_gain)
	t.check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambient"))
		and AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects"))
		and audio.ambient.volume_db == -20.0, "applied bus gain silences both voices without changing local gain")
	main.settings.apply_values(original_gain)


func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	return event


func _test_controller_frames(t, main, p) -> void:
	var view = main.arena_view
	main.start_practice("sloop")
	main.sim.ships[1]["heading"] = -PI / 2.0
	main._input(_key(KEY_E, true))
	main._input(_key(KEY_E, false))
	main.advance_tick()
	var first_ids: Array = view._cues.filter(func(c): return c["type"] == "shot").map(func(c): return c["projectile_id"])
	main.sim.ships[1]["weapons"]["starboard"]["loads"].fill(1.0)
	main._input(_key(KEY_E, true))
	main._input(_key(KEY_E, false))
	main.advance_tick()
	var shots: Array = view._cues.filter(func(c): return c["type"] == "shot")
	var second_ids: Array = shots.map(func(c): return c["projectile_id"])
	t.check(first_ids.size() == 4 and shots.size() == 8 and second_ids.slice(0, 4) == first_ids
		and second_ids.slice(4, 8) != first_ids, "controller consumes each tick before a render frame without merging volleys")
	var ages: Array = view._cues.map(func(c): return c["ticks"])
	var center: Vector2 = view.camera.position
	var zoom: Vector2 = view.camera.zoom
	main.set_paused(true)
	for i in 120:
		main.advance_tick()
		view._process(1.0 / 60.0)
	main._notification(main.NOTIFICATION_APPLICATION_FOCUS_OUT)
	for i in 120:
		main.advance_tick()
		view._process(1.0 / 60.0)
	t.check(main.mode == "paused" and center == view.camera.position and zoom == view.camera.zoom
		and ages == view._cues.map(func(c): return c["ticks"]), "120 paused frames plus focus return freeze camera and effect ages")
	main.set_paused(false)
	main.start_encounter("two_sloops", "sloop")
	var logical: Rect2 = p.gameplay_rect(Vector2(1280, 720))
	var window: Window = main.get_window()
	var original_window: Vector2i = window.size
	window.size = Vector2i(1920, 1080)
	var world: Vector2 = view.get_canvas_transform().affine_inverse() * Vector2(640, 100)
	main.sim.ships[2]["position"] = world
	var screen: Vector2 = view.marker_canvas.size
	var indicators: Dictionary = view.enemy_markers(main.sim, view.camera.position, Rect2(Vector2.ZERO, screen))
	t.check(window.size == Vector2i(1920, 1080) and screen == Vector2(1280, 720) and indicators.has(2)
		and view._marker_edges[2].y == logical.position.y, "1920×1080 window projects through logical gameplay canvas")
	window.size = original_window
	var baseline = Sim.new()
	baseline.reset("two_sloops", "sloop")
	var enabled = Sim.new()
	enabled.reset("two_sloops", "sloop")
	var tape := [{1: {"fire_port": true}, 2: {"fire_starboard": true}},
		{1: {"turn": 1.0}}, {}, {1: {"cycle_port": true}}, {1: {"fire_starboard": true}}]
	for command in tape:
		baseline.step(1.0 / 60.0, command)
		enabled.step(1.0 / 60.0, command)
		view.advance_effects()
		view.consume_events(p.normalize_events(enabled.events))
	t.check(baseline.ships == enabled.ships and baseline.projectiles == enabled.projectiles
		and baseline.result == enabled.result and baseline.events == enabled.events,
		"identical command tape preserves sim ships/projectiles/results with presentation on or off")
