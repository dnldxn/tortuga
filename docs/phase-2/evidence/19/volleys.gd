extends SceneTree
var main
var presentation
func _initialize():call_deferred("capture")
func tick(commands:Dictionary):
 main.sim.step(1.0/60,commands)
 main.arena_view.sync(main.sim)
 var events:Array=presentation.normalize_events(main.sim.events)
 main.combat_audio.arena_view=main.arena_view
 main.combat_audio.consume(events)
 main.arena_view.advance_effects()
 main.hud.advance_effects()
 main.arena_view.consume_events(events)
 main.hud.consume_events(events)
 main.hud.refresh(main.sim)
func shot(name:String):
 for i in 5:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("TORTUGA_CAPTURE_DIR")+"/"+name+".png")
 print("CAPTURE=",name," shots=",main.combat_audio.dispatch_counts.cannon," cues=",main.arena_view._cues.size())
func capture():
 main=load("res://main.tscn").instantiate()
 root.add_child(main)
 main.set_physics_process(false)
 presentation=load("res://view/combat_presentation.gd")
 for ammo in ["round","chain","grape"]:
  main.start_encounter("two_sloops","frigate")
  var commands:Dictionary={}
  for id in main.sim.ships:
   var ship:Dictionary=main.sim.ships[id]
   ship.position=Vector2(2100+id*200,2100)
   ship.heading=0.0
   for side in ["port","starboard"]:ship.weapons[side].ammo=ammo
   commands[id]={"fire_port":true,"fire_starboard":true}
  main.arena_view.reset_effects()
  main.arena_view.sync(main.sim)
  main.arena_view._fit_camera(0.0)
  for i in 20:await process_frame
  main.set_paused(false)
  tick(commands)
  await shot(ammo+"-muzzles")
  for i in 15:tick({})
  await shot(ammo+"-flight")
 main.combat_audio.clear()
 main.free()
 for i in 20:await process_frame
 quit()
