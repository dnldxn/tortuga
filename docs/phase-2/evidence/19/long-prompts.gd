extends SceneTree
var main
func _initialize():call_deferred("capture")
func shot(name: String):
 for i in 20:
  if name == "long-prompts": main.set_paused(false)
  await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("TORTUGA_CAPTURE_DIR")+"/"+name+".png")
 print("CAPTURE=",name)
func capture():
 main=load("res://main.tscn").instantiate()
 root.add_child(main)
 main.set_physics_process(false)
 main.start_encounter("two_sloops","frigate")
 var bindings=load("res://input_bindings.gd")
 var keys:Dictionary=bindings.default_keycodes()
 keys.fire_port=KEY_BRACKETLEFT
 keys.fire_starboard=KEY_BRACKETRIGHT
 keys.cycle_port=KEY_BACKSLASH
 keys.cycle_starboard=KEY_SEMICOLON
 bindings.apply_keycodes(keys)
 main.hud.refresh(main.sim)
 for side in ["port","starboard"]: main.sim.ships[1].weapons[side].ammo="chain"
 main.sim.ships[1].crew=1.0
 main.sim.escape_armed=true
 main.sim.escape_clear_ticks=100
 main.hud.refresh(main.sim)
 main.sim.escape_clear_ticks=0
 main.hud.consume_events([{"type":"empty","ship_id":1,"side":"port"},{"type":"empty","ship_id":1,"side":"starboard"}])
 main.hud.refresh(main.sim)
 await shot("long-prompts")
 main.set_paused(true)
 await shot("pause-long-prompts")
 main.combat_audio.clear()
 main.free()
 for i in 20: await process_frame
 quit()
