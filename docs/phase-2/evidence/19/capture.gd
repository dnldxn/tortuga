extends SceneTree
var main
func _initialize():
 call_deferred("capture")
func capture():
 var started := Time.get_ticks_usec()
 main = load("res://main.tscn").instantiate()
 root.add_child(main)
 main.set_physics_process(false)
 print("MAIN_READY_MS=", (Time.get_ticks_usec()-started)/1000.0)
 root.size = Vector2i(1280,720)
 print("DISPLAY physical_window=", DisplayServer.window_get_size(), " logical_canvas=", root.get_visible_rect().size, " screen_scale=",DisplayServer.screen_get_scale(), " screen_size=", DisplayServer.screen_get_size(), " audio=",AudioServer.output_device)
 for vessel in ["sloop","brig","frigate"]:
  for reefed in [false,true]:
   var before := Time.get_ticks_usec()
   main.start_encounter("two_sloops",vessel)
   print("ENCOUNTER_MS=", (Time.get_ticks_usec()-before)/1000.0)
   var sim = main.sim
   var origin: Vector2 = sim.ships[1]["position"]
   sim.ships[1]["heading"] = 0.0
   sim.ships[1]["reefed"] = reefed
   sim.ships[2]["position"] = origin+Vector2(0,-250)
   sim.ships[3]["position"] = origin+Vector2(0,250)
   main.arena_view.sync(sim)
   main.arena_view.reset_effects()
   main.arena_view._fit_camera(0.0)
   main.hud.refresh(sim)
   main.combat_audio.clear()
   for i in 25: await process_frame
   await RenderingServer.frame_post_draw
   var out: String = OS.get_environment("TORTUGA_CAPTURE_DIR")+"/"+vessel+("-reefed" if reefed else "-full")+".png"
   root.get_texture().get_image().save_png(out)
   print("CAPTURE=",out)
 main.free()
 for i in 10: await process_frame
 quit()
