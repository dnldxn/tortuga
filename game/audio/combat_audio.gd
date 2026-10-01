extends Node
## Presentation-only, bounded non-positional audio. consume() is called once per sim tick.

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


func _ready() -> void:
	var effect_bus: String = Settings.BUSES["effects"]
	var ambient_bus: String = Settings.BUSES["ambient"]
	if AudioServer.get_bus_index(effect_bus) < 0 or AudioServer.get_bus_index(ambient_bus) < 0:
		push_error("Combat audio requires Effects and Ambient buses")
		return
	for kind in effects:
		var stream: AudioStream = {"cannon": CANNON, "impact": IMPACT, "splash": SPLASH}[kind]
		var count: int = {"cannon": 3, "impact": 2, "splash": 1}[kind]
		for i in count:
			var player := AudioStreamPlayer.new()
			player.stream = stream
			player.bus = effect_bus
			player.volume_db = -18.0
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
			"volley":
				_play("cannon")
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


func _play(kind: String) -> void:
	for player in effects[kind]:
		if not player.playing:
			player.play()
			dispatch_counts[kind] += 1
			return  # All busy: drop the newest, never interrupt a voice.
