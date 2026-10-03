extends SceneTree
var main
func _initialize():call_deferred("capture")
func shot(name: String):
 for i in 20:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("TORTUGA_CAPTURE_DIR")+"/"+name+".png")
 print("CAPTURE=",name)
func capture():
 main=load("res://main.tscn").instantiate()
 root.add_child(main)
 main.set_physics_process(false)
 await shot("selection")
 main.selection.show_notice("Settings could not be loaded. Defaults are in use. The original settings file has been preserved.")
 main.selection.show_update_state("error","The update could not be downloaded. Check your internet connection and try again. Your installed version has not changed.")
 await shot("selection-notices")
 main.selection._show_vessels("two_sloops")
 await shot("vessels")
 main.settings_menu.open(main.settings)
 await shot("settings")
 main.settings_menu.back()
 main.start_encounter("two_sloops","frigate")
 main.set_paused(true)
 await shot("pause")
 main.sim.result={"outcome":"victory","elapsed":120.0,"defeated":[{"ship_id":2,"reason":"disabled","disabled_by":["sails","crew"]},{"ship_id":3,"reason":"sunk","disabled_by":[]}]}
 main._enter_mode("result")
 await shot("result")
 main.free()
 for i in 10:await process_frame
 quit()
