class_name Sim
extends RefCounted
# The whole simulation. Offline play and the dedicated server both call step();
# clients only overwrite `ships` from server snapshots. No rendering types here.

const ARENA := Vector2(1920, 1080)
const WIND_DIR := 0.0  # radians; wind blows toward +x
const TURN_RATE := 1.2
const RELOAD := 3.0
const BROADSIDE := 8
const SHOT_SPEED := 420.0
const SHOT_LIFE := 1.6

var time := 0.0
var ships := {}  # id -> {pos, heading, turn, reload, ai, side}
var shots: Array[Dictionary] = []
var fired: Array[Vector2] = []  # positions of broadsides this step, for the view
var rng := RandomNumberGenerator.new()


func _init(seed_value := 1) -> void:
	rng.seed = seed_value


func add_ship(id: int, ai: bool) -> void:
	ships[id] = {
		pos = Vector2(rng.randf_range(200, ARENA.x - 200), rng.randf_range(200, ARENA.y - 200)),
		heading = rng.randf_range(0, TAU),
		turn = 0.0,
		reload = rng.randf_range(0, RELOAD),
		ai = ai,
		side = 1.0,
	}


# Slowest heading into the wind, fastest on a broad reach.
func speed_for(heading: float) -> float:
	var off := absf(angle_difference(heading, WIND_DIR))
	return maxf(20.0, 60.0 + 60.0 * cos(off - PI / 4))


func step(dt: float) -> void:
	time += dt
	fired.clear()
	for id in ships:
		var s: Dictionary = ships[id]
		if s.ai:
			var to_centre: Vector2 = ARENA / 2 - s.pos
			if to_centre.length() > 420:
				s.turn = signf(angle_difference(s.heading, to_centre.angle()))
			else:
				s.turn = sin(time * 0.3 + id)
			s.reload -= dt
			if s.reload <= 0:
				s.reload = RELOAD
				s.side = -s.side
				_broadside(s)
		s.heading = wrapf(s.heading + s.turn * TURN_RATE * dt, 0, TAU)
		s.pos += Vector2.from_angle(s.heading) * speed_for(s.heading) * dt
	for i in range(shots.size() - 1, -1, -1):
		var b := shots[i]
		b.pos += b.vel * dt
		b.life -= dt
		if b.life <= 0:
			shots.remove_at(i)


func _broadside(s: Dictionary) -> void:
	var fwd := Vector2.from_angle(s.heading)
	var out: Vector2 = fwd.orthogonal() * s.side
	for g in BROADSIDE:
		var along := (g - (BROADSIDE - 1) / 2.0) * 9.0
		shots.append({pos = s.pos + fwd * along + out * 20.0, vel = out * SHOT_SPEED, life = SHOT_LIFE})
	fired.append(s.pos + out * 24.0)


func snapshot() -> PackedFloat32Array:
	var a := PackedFloat32Array()
	for id in ships:
		var s: Dictionary = ships[id]
		a.append_array([id, s.pos.x, s.pos.y, s.heading])
	return a


func apply_snapshot(t: float, a: PackedFloat32Array) -> void:
	time = t
	var seen := {}
	for i in range(0, a.size(), 4):
		var id := int(a[i])
		seen[id] = true
		if not ships.has(id):
			ships[id] = {pos = Vector2.ZERO, heading = 0.0, turn = 0.0, reload = 0.0, ai = false, side = 1.0}
		ships[id].pos = Vector2(a[i + 1], a[i + 2])
		ships[id].heading = a[i + 3]
	for id in ships.keys():
		if not seen.has(id):
			ships.erase(id)
