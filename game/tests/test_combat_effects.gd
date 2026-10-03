extends RefCounted

const Sim := preload("res://sim/naval_simulation.gd")
const P := preload("res://view/combat_presentation.gd")
const D := preload("res://sim/definitions.gd")

func run(t) -> bool:
	var sim = Sim.new()
	sim.reset("two_sloops", "frigate")
	var shot := {"type": "shot", "projectile_id": 1, "ship_id": 1, "side": "port", "gun_index": 0,
		"ammo": "round", "position": Vector2(2000, 2000), "direction": Vector2.RIGHT}
	sim.ships[2]["position"] = shot.position + Vector2(200, 0)
	sim.ships[3]["position"] = shot.position + Vector2(210, 0)
	sim.ships[3]["vessel_id"] = "frigate"
	t.check(P.arc_reference(sim, shot).target_id == 3, "larger farther center wins by first circle entry")
	t.near(P.arc_reference(sim, shot).distance, 167.5, .001, "first entry uses actual vessel collision radius")
	sim.ships[2]["vessel_id"] = "frigate"
	sim.ships[2]["position"] = sim.ships[3]["position"]
	t.check(P.arc_reference(sim, shot).target_id == 2, "exact entry tie resolved by stable ID")
	sim.ships[2]["active"] = false
	t.check(P.arc_reference(sim, shot).target_id == 3, "inactive enemy excluded")
	sim.ships[3]["team"] = sim.ships[1]["team"]
	t.check(P.arc_reference(sim, shot).target_id == -1, "friendly and owner excluded")
	sim.ships[3]["team"] = 1
	sim.ships[3]["position"] = shot.position + Vector2(100, 100)
	t.check(P.arc_reference(sim, shot).target_id == -1, "near enemy outside straight lane excluded")
	sim.ships[3]["position"] = shot.position + Vector2(1000, 0)
	t.near(P.arc_reference(sim, shot).distance, 405, .001, "no in-range intersection uses small range default")
	sim.ships[3]["position"] = shot.position
	t.check(P.arc_reference(sim, shot).distance == 0 and P.elevation(0, 0) == 0, "starts inside collision circle: zero arc")
	t.check(P.elevation(10, 30) == 0 and P.elevation(250, 200) == 0, "very close target and missed reference get no hop")
	t.near(P.elevation(100, 200), 11, .001, "bounded low arc peaks halfway")
	var main = load("res://main.tscn").instantiate()
	t.root.add_child(main)
	main.set_physics_process(false)
	main.arena_view.set_process(false)
	main.start_encounter("two_sloops", "frigate")
	var view = main.arena_view
	main.sim.ships[2]["position"] = main.sim.ships[1]["position"] + Vector2(200, 0)
	shot.position = main.sim.ships[1]["position"]
	view.consume_events([shot])
	main.sim.ships[1]["position"] += Vector2(80, 50)
	main.sim.ships[1]["heading"] = PI / 3.0
	view.consume_events([shot])
	t.check(view._cues.back().position == view._ships[1].muzzle_position("port", 0)
		and view._ships[1].position == main.sim.ships[1].position,
		"moving/turning shot syncs current barrel without an intervening render frame")
	var reference: Dictionary = view._projectile_visuals[1].duplicate(true)
	main.sim.ships[2]["position"] += Vector2(400, 100)
	t.check(view._projectile_visuals[1] == reference, "moving enemy never retargets snapshot")
	var projectile := {"id": 1, "ammo": "round", "position": shot.position + Vector2(70, 0)}
	var rendered: Vector2 = view.projectile_render_position(projectile)
	t.check(rendered.x == projectile.position.x and rendered.y < projectile.position.y, "short muzzle blend ends, shadow retains actual track")
	projectile.position = shot.position + Vector2(reference.distance + 20, 0)
	t.check(view.projectile_render_position(projectile) == projectile.position, "miss beyond snapshot stays on track with no new hop")
	var hit := {"type": "hit", "projectile_id": 1, "target_id": 2, "position": shot.position + Vector2(20, 0), "ammo": "round", "track": "hull", "damage": 8.0}
	view.consume_events([hit])
	t.check(not view._projectile_visuals.has(1) and view._cues.filter(func(c): return c.type == "hit")[0].position == hit.position,
		"early obstruction terminates sprite at authoritative hit position")
	view.consume_events([shot, hit])
	t.check(not view._projectile_visuals.has(1), "same-tick shot/hit terminates immediately")
	view.consume_events([shot, {"type": "splash", "projectile_id": 1, "position": shot.position + Vector2(900, 0)}])
	t.check(not view._projectile_visuals.has(1), "range expiry terminates arc at actual splash")
	main.start_encounter("two_sloops", "frigate")
	var salvo := []
	# Current roster: frigate sixteen guns and two sloops eight apiece = 32.
	for id in [1, 2, 3]:
		for side in D.SIDES:
			for gun in D.VESSELS[main.sim.ships[id].vessel_id].guns_per_side:
				var event: Dictionary = shot.duplicate(true)
				event.ship_id = id
				event.side = side
				event.gun_index = gun
				event.projectile_id = salvo.size() + 1
				event.position = main.sim.ships[id].position
				salvo.append(event)
	main.combat_audio.arena_view = view
	for load_index in 2:
		var events: Array = salvo.duplicate(true)
		for event in events:
			event.projectile_id += load_index * 32
		view.consume_events(P.normalize_events(events))
		main.combat_audio.consume(P.normalize_events(events))
	t.check(salvo.size() == 32 and main.combat_audio.dispatch_counts.cannon == 64,
		"32 simultaneous guns plus 32 overlapping tails dispatch without loss")
	t.check(main.combat_audio.effects.cannon.filter(func(player): return player.playing).size() == 64,
		"all 64 native voices active without stealing")
	t.check(view._cues.filter(func(c): return c.type == "shot").size() == 64, "one smoke puff per gun across overlapping volleys")
	for cue in view._cues:
		var muzzle: Vector2 = view._ships[cue.ship_id].muzzle_position(cue.side, cue.gun_index)
		t.check(cue.position == muzzle, "player/enemy smoke starts at mapped visible gun")
	var mix: Dictionary = main.combat_audio.cannon_mix(salvo[0])
	var screen_point: Vector2 = view.get_canvas_transform() * mix.position
	t.check(screen_point.x >= 288 and screen_point.x <= 992 and mix.pitch >= .975 and mix.pitch <= 1.025, "camera projection clamps stereo and pitch extremes")
	var sim_before: Dictionary = {"ships": main.sim.ships.duplicate(true), "projectiles": main.sim.projectiles.duplicate(true)}
	main.sim.result = {"outcome": "victory", "elapsed": 1.0, "defeated": []}
	main._enter_mode("result")
	t.check(not main.combat_audio.ambient.playing and main.combat_audio.effects.cannon[0].playing,
		"result stops sea while decisive cannon tail finishes")
	for i in 61:
		view._process(main.DT)
	t.check(view._cues.is_empty() and sim_before.ships == main.sim.ships and sim_before.projectiles == main.sim.projectiles,
		"result fades finish without advancing frozen combat")
	main._notification(main.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.check(main.combat_audio.paused and main.combat_audio.effects.cannon.all(func(player): return not player.playing), "result focus loss silences tails")
	main.return_to_selection()
	t.check(view._projectile_visuals.is_empty() and view._cues.is_empty(), "selection clears all projectile and smoke records")
	for i in 3:
		main.start_encounter("two_sloops", "frigate")
		view.consume_events(salvo)
		main.restart_practice()
		t.check(view._projectile_visuals.is_empty() and view._cues.is_empty(), "repeated encounter restart clears bounded records")
	var baseline = Sim.new()
	baseline.reset("two_sloops", "frigate")
	var enabled = Sim.new()
	enabled.reset("two_sloops", "frigate")
	main.sim = enabled
	view.reset_effects()
	main.combat_audio.clear()
	for tick in 240:
		var commands := {1: {"turn": .5, "fire_port": tick == 0, "fire_starboard": tick == 0},
			2: {"fire_port": tick == 0, "fire_starboard": tick == 0},
			3: {"fire_port": tick == 0, "fire_starboard": tick == 0}}
		baseline.step(main.DT, commands)
		enabled.step(main.DT, commands)
		if tick == 0:
			t.check(enabled.events.filter(func(event): return event.type == "shot").size() == 32, "real both-side commands fire all 32 guns on one sim tick")
		var events: Array = P.normalize_events(enabled.events)
		view.advance_effects()
		view.consume_events(events)
		main.combat_audio.consume(events)
		t.check(baseline.ships == enabled.ships and baseline.projectiles == enabled.projectiles
			and baseline.events == enabled.events and baseline.result == enabled.result
			and baseline.next_projectile_id == enabled.next_projectile_id,
			"enabled/disabled presentation deterministic checkpoint %d" % tick)
	main.combat_audio._play("impact")
	var terminal_voice = main.combat_audio.effects.impact.filter(func(player): return player.playing)[0]
	main.combat_audio.finish_encounter()
	t.check(terminal_voice.playing, "terminal actual impact sound allowed to finish")
	var effects_bus := AudioServer.get_bus_index("Effects")
	var was_muted := AudioServer.is_bus_mute(effects_bus)
	AudioServer.set_bus_mute(effects_bus, true)
	main.combat_audio._process(0.0)
	t.check(not terminal_voice.playing, "mute takes precedence over terminal tails")
	AudioServer.set_bus_mute(effects_bus, was_muted)
	main.start_encounter("duel_brig", "frigate")
	main.sim.ships[2]["hull"] = 8.0
	var target_position: Vector2 = main.sim.ships[2].position
	main.sim.projectiles.append({"id": 999, "owner_id": 1, "ammo": "round",
		"position": target_position - Vector2(35.1, 0), "direction": Vector2.RIGHT,
		"remaining_range": 100.0, "owner_cleared": true})
	main.combat_audio.consume([shot])
	main.advance_tick()
	t.check(main.mode == "result" and main.combat_audio.dispatch_counts.impact == 1
		and main.combat_audio.effects.impact[0].playing and main.combat_audio.effects.cannon[0].playing,
		"real decisive hit enters result with impact and preceding cannon still playing")
	main.start_encounter("two_sloops", "frigate")
	for count in [1, 3, 8, 24, 32]:
		main.combat_audio.clear()
		main.combat_audio.consume(P.normalize_events(salvo.slice(0, count)))
		t.check(main.combat_audio.dispatch_counts.cannon == count, "short/partial/full/opposing salvo dispatches %d sounds" % count)
	main.free()
	return true
