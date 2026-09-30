extends Node2D
# Probe harness: offline scene, dedicated server, and client in one script.
# User args (after `--`): --mode=offline|server|client --scene=normal|busy
#   --host= --port= --bot=<turn -1..1> --warmup=s --bench=s --out=csv
#   --reloads=n --shot=png --shot_at=s --quit_at=s

const WATER_SHADER := "
shader_type canvas_item;
uniform sampler2D tile : repeat_enable, filter_linear;
void fragment() {
	vec2 uv = UV * vec2(15.0, 8.4375) + vec2(TIME * 0.03, sin(TIME * 0.4 + UV.x * 6.0) * 0.02);
	vec3 c = texture(tile, uv).rgb;
	float w = sin(UV.x * 40.0 + UV.y * 25.0 + TIME * 1.5) * 0.03;
	COLOR = vec4(c + w, 1.0);
}
"
const MAX_SHOTS := 256
const MAX_SPLASH := 64

var args := {}
var mode := "offline"
var sim: Sim
var my_id := 1000
var headless := false
var tick := 0

var view: Node2D
var ship_nodes := {}
var shot_pool: Array[Sprite2D] = []
var splash_pool: Array[Sprite2D] = []
var splash_next := 0
var smoke_pool: Array[CPUParticles2D] = []
var smoke_next := 0
var cannon_pool: Array[AudioStreamPlayer] = []
var cannon_next := 0
var hud_left: Label
var hud_right: Label
var hud_guns: Label

var first_frame_usec := -1
var frame_usec := PackedInt64Array()
var last_usec := 0
var bench_done := false
var shot_done := false
var last_log_sec := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	mode = args.get("mode", "offline")
	headless = DisplayServer.get_name() == "headless"
	print("ENV mode=%s display=%s renderer=%s adapter=%s vendor=%s api=%s window=%s vsync=%d" % [
		mode, DisplayServer.get_name(), RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_api_version(), DisplayServer.window_get_size(),
		DisplayServer.window_get_vsync_mode()])
	_new_world()
	var port := int(args.get("port", "24555"))
	if mode == "server":
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(port, 4)
		print("SRV listen port=%d err=%d" % [port, err])
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	elif mode == "client":
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_client(args.get("host", "127.0.0.1"), port)
		print("CLI connect err=%d" % err)
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(func(): print("CLI connected id=%d" % multiplayer.get_unique_id()))
		multiplayer.server_disconnected.connect(func(): print("CLI server_disconnected"))
	if not headless:
		_build_view()
		RenderingServer.frame_post_draw.connect(_on_first_frame, CONNECT_ONE_SHOT)


func _new_world() -> void:
	sim = Sim.new()
	if mode == "offline":
		sim.add_ship(my_id, false)
		for i in (16 if args.get("scene", "normal") == "busy" else 4):
			sim.add_ship(i + 1, true)
	elif mode == "server":
		sim.add_ship(1, true)  # one AI ship gives the server a moving value to log


func _on_peer_connected(id: int) -> void:
	sim.add_ship(id, false)
	print("SRV join id=%d wall=%.2f peers=%d" % [id, _wall(), multiplayer.get_peers().size()])


func _on_peer_disconnected(id: int) -> void:
	sim.ships.erase(id)
	print("SRV leave id=%d wall=%.2f peers=%d" % [id, _wall(), multiplayer.get_peers().size()])


func _wall() -> float:
	return Time.get_ticks_msec() / 1000.0


@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_input(turn: float) -> void:
	# A client can only ever steer the ship keyed by its own peer id.
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and sim.ships.has(id):
		sim.ships[id].turn = clampf(turn, -1.0, 1.0)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_snapshot(t: float, data: PackedFloat32Array) -> void:
	sim.apply_snapshot(t, data)


func _my_turn() -> float:
	if args.has("bot"):
		return float(args.bot)
	return Input.get_axis("ui_left", "ui_right")


func _physics_process(dt: float) -> void:
	tick += 1
	if mode == "offline":
		sim.ships[my_id].turn = _my_turn()
		sim.step(dt)
		_show_events()
	elif mode == "server":
		# Game time only advances with someone connected; the loop, the socket,
		# and this log keep running regardless.
		if multiplayer.get_peers().size() > 0:
			sim.step(dt)
			if tick % 3 == 0:
				net_snapshot.rpc(sim.time, sim.snapshot())
	elif multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		net_input.rpc_id(1, _my_turn())
	var sec := int(_wall())
	if sec != last_log_sec and (mode != "offline" or headless or args.has("log")):
		last_log_sec = sec
		var parts := PackedStringArray()
		for id in sim.ships:
			parts.append("%d:h=%.2f,x=%.0f" % [id, sim.ships[id].heading, sim.ships[id].pos.x])
		print("%s wall=%d sim=%.2f peers=%d ships[%s]" % [mode.to_upper().left(3), sec, sim.time,
			multiplayer.get_peers().size() if multiplayer.has_multiplayer_peer() else 0, " ".join(parts)])
	if args.has("quit_at") and _wall() >= float(args.quit_at) and (headless or bench_done or not args.has("bench")):
		get_tree().quit()


func _build_view() -> void:
	view = Node2D.new()
	add_child(view)
	ship_nodes.clear()
	shot_pool.clear()
	splash_pool.clear()
	smoke_pool.clear()
	cannon_pool.clear()

	var water := ColorRect.new()
	water.size = Sim.ARENA
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = WATER_SHADER
	mat.set_shader_parameter("tile", load("res://assets/tiles/tile_73.png"))
	water.material = mat
	view.add_child(water)

	var island := [[1, 2, 3], [17, 18, 19], [33, 34, 35]]
	for r in 3:
		for c in 3:
			var t := Sprite2D.new()
			t.texture = load("res://assets/tiles/tile_%02d.png" % island[r][c])
			t.position = Vector2(1500 + c * 128, 120 + r * 128)
			view.add_child(t)
	var palm := Sprite2D.new()
	palm.texture = load("res://assets/tiles/tile_71.png")
	palm.position = Vector2(1628, 248)
	view.add_child(palm)

	var ball: Texture2D = load("res://assets/parts/cannonBall.png")
	for i in MAX_SHOTS:
		var s := Sprite2D.new()
		s.texture = ball
		s.visible = false
		view.add_child(s)
		shot_pool.append(s)
	var boom: Texture2D = load("res://assets/effects/explosion3.png")
	for i in MAX_SPLASH:
		var s := Sprite2D.new()
		s.texture = boom
		s.scale = Vector2(0.4, 0.4)
		s.visible = false
		view.add_child(s)
		splash_pool.append(s)
	for i in 16:
		var p := CPUParticles2D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 24
		p.lifetime = 0.9
		p.explosiveness = 0.9
		p.spread = 180.0
		p.gravity = Vector2.ZERO
		p.initial_velocity_min = 20.0
		p.initial_velocity_max = 60.0
		p.scale_amount_min = 4.0
		p.scale_amount_max = 9.0
		p.color = Color(0.9, 0.9, 0.9, 0.6)
		view.add_child(p)
		smoke_pool.append(p)
	for i in 8:
		var a := AudioStreamPlayer.new()
		a.stream = load("res://assets/audio/cannon.wav")
		a.volume_db = -12.0
		view.add_child(a)
		cannon_pool.append(a)
	var amb := AudioStreamPlayer.new()
	var ogg: AudioStreamOggVorbis = load("res://assets/audio/ambient.ogg")
	ogg.loop = true
	amb.stream = ogg
	amb.volume_db = -18.0
	view.add_child(amb)
	amb.play()

	var hud := CanvasLayer.new()
	view.add_child(hud)
	hud_left = _label(hud, Vector2(20, 12))
	hud_right = _label(hud, Vector2(1500, 12))
	hud_guns = _label(hud, Vector2(20, 1030))
	var wind := Polygon2D.new()
	wind.polygon = PackedVector2Array([Vector2(-30, -8), Vector2(10, -8), Vector2(10, -18), Vector2(34, 0), Vector2(10, 18), Vector2(10, 8), Vector2(-30, 8)])
	wind.position = Vector2(80, 960)
	wind.rotation = Sim.WIND_DIR
	wind.color = Color(1, 1, 1, 0.8)
	hud.add_child(wind)


func _label(parent: Node, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 24)
	parent.add_child(l)
	return l


func _ship_node(id: int) -> Sprite2D:
	var n := Sprite2D.new()
	n.texture = load("res://assets/ships/ship%d.png" % (1 + id % 6))
	var wake := CPUParticles2D.new()
	wake.amount = 40
	wake.lifetime = 1.4
	wake.local_coords = false
	wake.position = Vector2(0, -50)  # sprite bow points +y, so the stern is -y
	wake.direction = Vector2(0, -1)
	wake.spread = 25.0
	wake.gravity = Vector2.ZERO
	wake.initial_velocity_min = 10.0
	wake.initial_velocity_max = 30.0
	wake.scale_amount_min = 3.0
	wake.scale_amount_max = 6.0
	wake.color = Color(1, 1, 1, 0.45)
	n.add_child(wake)
	view.add_child(n)
	view.move_child(n, 11)  # above water and island, below shots and HUD
	return n


func _show_events() -> void:
	if view == null:
		return
	for pos in sim.fired:
		var p := smoke_pool[smoke_next % smoke_pool.size()]
		smoke_next += 1
		p.position = pos
		p.restart()
		cannon_pool[cannon_next % cannon_pool.size()].play()
		cannon_next += 1
	for b in sim.shots:
		if b.life <= 1.0 / 60.0:
			var s := splash_pool[splash_next % MAX_SPLASH]
			splash_next += 1
			s.position = b.pos
			s.visible = true
			s.set_meta("until", sim.time + 0.3)


func _on_first_frame() -> void:
	first_frame_usec = Time.get_ticks_usec()
	print("T_FIRST_FRAME unix=%.3f engine_ms=%.1f" % [Time.get_unix_time_from_system(), first_frame_usec / 1000.0])


func _process(_dt: float) -> void:
	if view == null:
		return
	for id in sim.ships:
		if not ship_nodes.has(id):
			ship_nodes[id] = _ship_node(id)
		var n: Sprite2D = ship_nodes[id]
		n.position = sim.ships[id].pos
		n.rotation = sim.ships[id].heading - PI / 2
	for id in ship_nodes.keys():
		if not sim.ships.has(id):
			ship_nodes[id].queue_free()
			ship_nodes.erase(id)
	for i in MAX_SHOTS:
		var on := i < sim.shots.size()
		shot_pool[i].visible = on
		if on:
			shot_pool[i].position = sim.shots[i].pos
	for s in splash_pool:
		if s.visible and sim.time > s.get_meta("until"):
			s.visible = false
	if sim.ships.has(my_id):
		var me: Dictionary = sim.ships[my_id]
		hud_left.text = "Sloop 'Probe'  8 guns, 54 crew, %d knots" % int(sim.speed_for(me.heading) / 8.0)
	hud_right.text = "%d ships  %d shots  t=%.1f" % [sim.ships.size(), sim.shots.size(), sim.time]
	hud_guns.text = "%d guns loaded" % 8

	var now := Time.get_ticks_usec()
	var since := (now - first_frame_usec) / 1e6 if first_frame_usec >= 0 else -1.0
	if args.has("shot") and not shot_done and since >= float(args.get("shot_at", "3")):
		shot_done = true
		get_viewport().get_texture().get_image().save_png(args.shot)
		print("SHOT saved %s" % args.shot)
	if args.has("bench") and not bench_done and since >= float(args.get("warmup", "5")):
		if last_usec > 0:
			frame_usec.append(now - last_usec)
		last_usec = now
		if since >= float(args.get("warmup", "5")) + float(args.bench):
			bench_done = true
			_finish_bench()


func _finish_bench() -> void:
	var sorted := frame_usec.duplicate()
	sorted.sort()
	var n := sorted.size()
	var over := 0
	var sum := 0
	for v in frame_usec:
		sum += v
		if v > 16667:
			over += 1
	print("BENCH frames=%d mean_ms=%.3f median_ms=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f over_16.67ms=%d" % [
		n, sum / 1000.0 / n, sorted[n / 2] / 1000.0, sorted[int(n * 0.95)] / 1000.0,
		sorted[int(n * 0.99)] / 1000.0, sorted[n - 1] / 1000.0, over])
	if args.has("out"):
		var f := FileAccess.open(args.out, FileAccess.WRITE)
		for v in frame_usec:
			f.store_line(str(v))
		f.close()
	for i in int(args.get("reloads", "0")):
		await get_tree().create_timer(1.0).timeout
		var t := Time.get_ticks_usec()
		view.free()
		_new_world()
		_build_view()
		await RenderingServer.frame_post_draw
		print("T_RELOAD_MS %.2f" % ((Time.get_ticks_usec() - t) / 1000.0))
	get_tree().quit()
