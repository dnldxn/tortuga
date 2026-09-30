extends Node2D
## Read-only arena presentation: sea, shallows/coast, ship sprites and follow camera.
## Reads the parent controller's `sim` fresh every frame (it is replaced on return to
## selection) and never mutates it.

const Definitions := preload("res://sim/definitions.gd")

const TEXTURES := {
	"sloop": preload("res://assets/ships/sloop.svg"),
	"brig": preload("res://assets/ships/brig.svg"),
	"frigate": preload("res://assets/ships/frigate.svg"),
}
## Mast x positions in sprite-canvas pixels, relative to the sprite centre.
const MASTS := {"sloop": [2.0], "brig": [-10.0, 12.0], "frigate": [-20.0, 2.0, 22.0]}
const REEFED_SAIL_SCALE := Vector2(0.6, 0.5)

const SEA := Color(0.09, 0.36, 0.55)
const WAVE := Color(0.55, 0.78, 0.9, 0.35)
const SHALLOWS := Color(0.36, 0.72, 0.72)
const HATCH := Color(0.9, 0.95, 0.85, 0.45)
const LAND := Color(0.42, 0.55, 0.3)
const SAND := Color(0.9, 0.82, 0.58)
const LIMIT := Color(1.0, 0.92, 0.55)
const WARNING := "Shallows / Turn back"

var main: Node
var camera := Camera2D.new()
var _ships := {}  # ship id -> Sprite2D


func _ready() -> void:
	main = get_parent()
	camera.zoom = Vector2.ONE
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	camera.ignore_rotation = true
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(Definitions.ARENA_SIZE.x)
	camera.limit_bottom = int(Definitions.ARENA_SIZE.y)
	add_child(camera)
	main.practice_started.connect(_on_practice_started)
	main.mode_changed.connect(func(_mode: String) -> void: sync(main.sim))


func _process(_delta: float) -> void:
	sync(main.sim)


## Reconciles ship nodes with sim.ships by stable id and points the camera at the player.
func sync(sim) -> void:
	for id in _ships.keys():
		var ship: Dictionary = sim.ships.get(id, {})
		if ship.is_empty() or ship["vessel_id"] != _ships[id].get_meta("vessel_id"):
			_ships[id].free()
			_ships.erase(id)
	for id in sim.ships:
		var ship: Dictionary = sim.ships[id]
		if not _ships.has(id):
			_ships[id] = _make_ship(ship["vessel_id"])
			add_child(_ships[id])
		var node: Sprite2D = _ships[id]
		node.visible = ship["active"]
		node.position = ship["position"]
		node.rotation = ship["heading"]
		for patch in node.get_node("Sails").get_children():
			patch.scale = REEFED_SAIL_SCALE if ship["reefed"] else Vector2.ONE
	if sim.ships.has(sim.PLAYER_ID):
		camera.position = sim.ships[sim.PLAYER_ID]["position"]


func _on_practice_started() -> void:
	sync(main.sim)
	camera.reset_smoothing()


func _make_ship(vessel_id: String) -> Sprite2D:
	var texture: Texture2D = TEXTURES[vessel_id]
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.set_meta("vessel_id", vessel_id)
	# Displayed length = collision diameter; sails live in canvas pixels under this scale.
	sprite.scale = Vector2.ONE * (2.0 * Definitions.VESSELS[vessel_id]["radius"] / texture.get_width())
	var sails := Node2D.new()
	sails.name = "Sails"
	sprite.add_child(sails)
	var half := texture.get_height() * 0.55
	for x in MASTS[vessel_id]:
		var patch := Polygon2D.new()
		patch.position = Vector2(x, 0)
		patch.color = Color(0.96, 0.93, 0.84, 0.95)
		# A yard-and-canvas patch across the beam, bellied toward the bow.
		patch.polygon = PackedVector2Array([Vector2(-2, -half), Vector2(3, -half * 0.8),
			Vector2(6, 0), Vector2(3, half * 0.8), Vector2(-2, half)])
		sails.add_child(patch)
	return sprite


func _draw() -> void:
	var size := Definitions.ARENA_SIZE
	var m := Definitions.ARENA_MARGIN
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	# Open-sea wave marks: little chevrons on a staggered grid.
	var waves := PackedVector2Array()
	for row in int(size.y / 140.0):
		for x in range(60 + (row % 2) * 90, int(size.x), 180):
			var p := Vector2(x, 100 + row * 140)
			waves.append_array([p, p + Vector2(10, -6), p + Vector2(10, -6), p + Vector2(20, 0)])
	draw_multiline(waves, WAVE, 2.0)
	# Shallows band on all four sides, hatched so it reads without colour.
	var bands := [Rect2(0, 0, size.x, m), Rect2(0, size.y - m, size.x, m),
		Rect2(0, 0, m, size.y), Rect2(size.x - m, 0, m, size.y)]
	var hatch := PackedVector2Array()
	for band in bands:
		draw_rect(band, SHALLOWS)
		for y in range(int(band.position.y), int(band.end.y) - 12, 24):
			for x in range(int(band.position.x), int(band.end.x) - 12, 24):
				hatch.append_array([Vector2(x, y), Vector2(x + 12, y + 12)])
	draw_multiline(hatch, HATCH, 1.5)
	_draw_west_coast(size.y)
	# Navigable limit: dashed line with buoys and repeated warnings inside the shallows.
	var safe := Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0)
	var corners := [safe.position, Vector2(safe.end.x, m), safe.end, Vector2(m, safe.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], LIMIT, 4.0, 30.0)
	var font := ThemeDB.fallback_font
	for x in range(400, int(size.x) - 300, 800):
		_warning(font, Vector2(x, 100), 0.0)
		_warning(font, Vector2(x, size.y - 40), 0.0)
		_buoy(Vector2(x - 40, m - 12))
		_buoy(Vector2(x - 40, size.y - m + 12))
	for y in range(700, int(size.y) - 300, 800):
		_warning(font, Vector2(m - 14, y), -PI / 2.0)
		_warning(font, Vector2(size.x - m + 36, y), -PI / 2.0)
		_buoy(Vector2(m - 12, y + 40))
		_buoy(Vector2(size.x - m + 12, y + 40))


## West coast: jagged land with a sand fringe and hill marks, all west of the shallows limit.
func _draw_west_coast(height: float) -> void:
	var coast := PackedVector2Array([Vector2(0, 0)])
	for i in int(height / 150.0) + 2:
		coast.append(Vector2(70 + 25 * sin(i * 2.0) + (i % 2) * 12, minf(i * 150.0, height)))
	coast.append(Vector2(0, height))
	draw_colored_polygon(coast, LAND)
	draw_polyline(coast.slice(1, coast.size() - 1), SAND, 8.0)
	for y in range(200, int(height), 400):
		draw_arc(Vector2(30, y), 14, PI, TAU, 8, SAND.darkened(0.4), 3.0)


func _warning(font: Font, at: Vector2, angle: float) -> void:
	draw_set_transform(at, angle)
	draw_string_outline(font, Vector2.ZERO, WARNING, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color.BLACK)
	draw_string(font, Vector2.ZERO, WARNING, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, LIMIT)
	draw_set_transform(Vector2.ZERO)


func _buoy(at: Vector2) -> void:
	draw_circle(at, 9, Color(0.85, 0.15, 0.1))
	draw_circle(at, 4, Color.WHITE)
