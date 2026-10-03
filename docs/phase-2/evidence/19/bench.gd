extends SceneTree
var main
var began := 0
var previous := 0
var samples: Array[int] = []
var steps := 0
var cleanup := 0
func _initialize():
 call_deferred("start")
func start():
 main = load("res://main.tscn").instantiate()
 root.add_child(main)
 main.set_physics_process(false)
 root.size = Vector2i(1920,1080)
 main.start_encounter("two_sloops","frigate")
 for id in main.sim.ships:
  main.sim.ships[id]["heading"] = 0.0
  main.sim.ships[id]["position"] = Vector2(2400+id*300,2100)
 began = Time.get_ticks_usec()
 print("BENCH_DISPLAY window=",DisplayServer.window_get_size()," canvas=",root.get_visible_rect().size," scale=",DisplayServer.screen_get_scale()," pid=",OS.get_process_id())
func _physics_process(_delta):
 if main == null: return false
 main.set_paused(false)
 var commands := {}
 for id in main.sim.ships: commands[id]={"fire_port":true,"fire_starboard":true}
 main.sim.step(1.0/60,commands)
 var events = load("res://view/combat_presentation.gd").normalize_events(main.sim.events)
 if main.combat_audio.has_method("finish_encounter"): main.combat_audio.arena_view=main.arena_view
 main.combat_audio.consume(events)
 main.arena_view.advance_effects()
 main.hud.advance_effects()
 main.arena_view.consume_events(events)
 main.hud.consume_events(events)
 main.hud.refresh(main.sim)
 steps+=1
 return false
func _process(_delta):
 if cleanup > 0:
  cleanup -= 1
  if cleanup == 0: quit()
  return false
 if began == 0: return false
 var now:=Time.get_ticks_usec()
 var elapsed:float=(now-began)/1000000.0
 if elapsed>=5:
  if previous>0:samples.append(now-previous)
  previous=now
 if elapsed>=65:
  var ordered:=samples.duplicate()
  ordered.sort()
  var over:=0
  for n in samples: if n>16667: over+=1
  print("BENCH frames=",samples.size()," steps=",steps," p99_ms=",ordered[int(ordered.size()*.99)]/1000.0," over_16.67_percent=",100.0*over/samples.size()," draw_calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," primitives=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
  var output:=FileAccess.open(OS.get_environment("TORTUGA_BENCH_OUT"),FileAccess.WRITE)
  for n in samples: output.store_line(str(n))
  main.combat_audio.clear()
  main.queue_free()
  main=null
  began=0
  cleanup=30
 return false
