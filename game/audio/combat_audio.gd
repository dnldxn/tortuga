extends Node
## Presentation-only, bounded positional cannon audio. consume() is called once per sim tick.

const Definitions := preload("res://sim/definitions.gd")
const Settings := preload("res://settings.gd")
const CANNON := preload("res://assets/audio/cannon.wav")
const IMPACT := preload("res://assets/audio/impact.wav")
const SPLASH := preload("res://assets/audio/splash.wav")
const SEA := preload("res://assets/audio/sea.wav")

var effects := {"cannon": [], "impact": [], "splash": []}
var ambient: AudioStreamPlayer
var paused := false
var hit_groups := {}  # target/track -> tick of first audible hit
var dispatch_counts := {"cannon": 0, "impact": 0, "splash": 0}
var _tick := 0
var arena_view: Node2D


func _ready() -> void:
	var effect_bus: String = Settings.BUSES["effects"]
	var ambient_bus: String = Settings.BUSES["ambient"]
	if AudioServer.get_bus_index(effect_bus) < 0 or AudioServer.get_bus_index(ambient_bus) < 0:
		push_error("Combat audio requires Effects and Ambient buses")
		return
	for kind in effects:
		var stream: AudioStream = {"cannon": CANNON, "impact": IMPACT, "splash": SPLASH}[kind]
		var count: int = {"cannon": Definitions.PRESENTATION.cannon_voices, "impact": 2, "splash": 1}[kind]
		for i in count:
			var player = AudioStreamPlayer2D.new() if kind == "cannon" else AudioStreamPlayer.new()
			if kind == "cannon":
				player.attenuation = 0.0
				player.max_distance = 100000.0
				player.panning_strength = 1.0
			player.stream = stream
			player.bus = effect_bus
			player.volume_db = Definitions.PRESENTATION.cannon_db if kind == "cannon" else -18.0
			player.max_polyphony = 1
			add_child(player)
			effects[kind].append(player)
	ambient = AudioStreamPlayer.new()
	var loop := SEA.duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
	ambient.stream = loop
	ambient.bus = ambient_bus
	ambient.volume_db = -20.0
	add_child(ambient)


func _process(_delta: float) -> void:
	# A mute must not leave an inaudible tail to emerge on later unmute.
	if AudioServer.is_bus_mute(AudioServer.get_bus_index(Settings.BUSES["effects"])) or AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")):
		for kind in effects:
			for player in effects[kind]:
				player.stop()


func start_encounter() -> void:
	clear()
	if ambient != null:
		ambient.play()


func consume(events: Array) -> void:
	if paused:
		return
	_tick += 1
	for key in hit_groups.keys():
		if _tick - hit_groups[key] >= 6:  # six fixed 1/60s ticks = .1s
			hit_groups.erase(key)
	for event in events:
		match event.get("type", ""):
			"shot":
				_play("cannon", event)
			"hit":
				var key := "%s/%s" % [event["target_id"], event["track"]]
				if not hit_groups.has(key):
					hit_groups[key] = _tick
					_play("impact")
			"splash":
				_play("splash")


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	if value:
		for kind in effects:
			for player in effects[kind]:
				player.stop()
		hit_groups.clear()
	if ambient != null:
		ambient.stream_paused = value


func clear() -> void:
	for kind in effects:
		for player in effects[kind]:
			player.stop()
	if ambient != null:
		ambient.stop()
	paused = false
	hit_groups.clear()
	_tick = 0
	for kind in dispatch_counts:
		dispatch_counts[kind] = 0


func finish_encounter() -> void:
	if ambient != null:
		ambient.stop()
	hit_groups.clear()


## Native panner receives a clamped screen coordinate mapped back through the camera.
func cannon_mix(event: Dictionary) -> Dictionary:
	var tuning: Dictionary = Definitions.PRESENTATION
	var source: Vector2 = event.get("position", Vector2.ZERO)
	var position := source
	var gain := 1.0
	if arena_view != null:
		var sim = arena_view.main.sim
		if sim.ships.has(event.get("ship_id", -1)):
			source = sim.ships[event["ship_id"]]["position"]
		var transform: Transform2D = arena_view.get_canvas_transform()
		var screen: Vector2 = arena_view.get_viewport_rect().size
		var projected: Vector2 = transform * source
		projected.x = clampf(projected.x, screen.x * (.5 - tuning.audio_pan_extent * .5), screen.x * (.5 + tuning.audio_pan_extent * .5))
		projected.y = screen.y * .5
		position = transform.affine_inverse() * projected
		var focus_id: int = arena_view.main.focus_ship_id()
		if sim.ships.has(focus_id):
			gain = lerpf(1.0, tuning.audio_far_gain, clampf(source.distance_to(sim.ships[focus_id]["position"]) / tuning.audio_distance, 0.0, 1.0))
	var variation: float = float(int(event.get("projectile_id", dispatch_counts["cannon"])) % 7 - 3) / 3.0
	return {"position": position, "volume_db": tuning.cannon_db + linear_to_db(gain) - absf(variation) * tuning.cannon_level_variation,
		"pitch": 1.0 + variation * tuning.cannon_pitch_variation}


func _play(kind: String, event: Dictionary = {}) -> void:
	for player in effects[kind]:
		if not player.playing:
			if kind == "cannon":
				var mix: Dictionary = cannon_mix(event)
				player.global_position = mix["position"]
				player.volume_db = mix["volume_db"]
				player.pitch_scale = mix["pitch"]
			player.play()
			dispatch_counts[kind] += 1
			return
	if kind == "cannon":
		push_error("Cannon capacity exceeded (unsupported load beyond overlapping 32-shot volleys)")
