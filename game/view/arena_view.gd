extends Node2D
## Read-only arena presentation: sea, shallows/coast, ship sprites and follow camera.
## Reads the parent controller's `sim` fresh every frame (it is replaced on return to
## selection) and never mutates it.

const Definitions := preload("res://sim/definitions.gd")
const ReefGlass := preload("res://view/reef_glass.gd")

const TEXTURES := {
	"sloop": preload("res://assets/ships/sloop.svg"),
	"brig": preload("res://assets/ships/brig.svg"),
	"frigate": preload("res://assets/ships/frigate.svg"),
}
## Mast x positions in sprite-canvas pixels, relative to the sprite centre.
const MASTS := {"sloop": [2.0], "brig": [-10.0, 12.0], "frigate": [-20.0, 2.0, 22.0]}
const REEFED_SAIL_SCALE := Vector2(0.6, 0.5)

const SHALLOWS := Color(0.36, 0.72, 0.72, 0.25)
const HATCH := Color(0.9, 0.95, 0.85, 0.45)
const LAND := Color(0.42, 0.55, 0.3)
const SAND := Color(0.9, 0.82, 0.58)
const LIMIT := Color(1.0, 0.92, 0.55)
const WARNING := "Shallows / Turn back"
const TARGET_INK := Color(1.0, 0.9, 0.55)
const SHOT_INK := Color(1.0, 0.98, 0.85)
const ENEMY_INK := Color(1.0, 0.62, 0.45)
const ZOOM_MIN := 0.65
const ZOOM_MAX := 1.0
const FIT_MARGIN_X := 120.0
const FIT_MARGIN_Y := 240.0
const ZOOM_SMOOTH := 6.0
const MARKER_INSET := 24.0

var main: Node
var camera := Camera2D.new()
var _ships := {}  # ship id -> Sprite2D
var _cues := []  # deep-copied events with ticks; never aliases sim.events
var marker_layer: CanvasLayer
var marker_canvas: Control
var water: Node2D


func advance_effects() -> void:
	water.advance(main.DT, main.sim.wind_heading)
	for cue in _cues:
		cue["ticks"] -= 1
	_cues = _cues.filter(func(cue): return cue["ticks"] > 0)
	queue_redraw()


func consume_events(events: Array) -> void:
	for event in events:
		if event["type"] in ["shot", "hit", "splash", "ship_defeated"]:
			var cue: Dictionary = event.duplicate(true)
			cue["ticks"] = 16 if cue["type"] == "shot" else 48
			_cues.append(cue)
	queue_redraw()


func reset_effects() -> void:
	_cues.clear()
	water.reset(main.sim.wind_heading)
	queue_redraw()
	if marker_canvas != null:
		marker_canvas.queue_redraw()


## Camera-centered viewport coordinates, inset so the arrow and its label remain visible.
func target_marker(center: Vector2, target: Vector2, screen: Rect2) -> Dictionary:
	var mid := screen.position + screen.size * 0.5
	var projected := mid + (target - center) * camera.zoom
	var safe := screen.grow(-MARKER_INSET)
	return {"offscreen": not safe.has_point(projected), "position": projected.clamp(safe.position, safe.end)}


func _ready() -> void:
	main = get_parent()
	water = ReefGlass.new()
	water.name = "ReefGlass"
	add_child(water)
	camera.zoom = Vector2.ONE
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	camera.ignore_rotation = true
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(Definitions.ARENA_SIZE.x)
	camera.limit_bottom = int(Definitions.ARENA_SIZE.y)
	add_child(camera)
	marker_layer = CanvasLayer.new()
	add_child(marker_layer)
	marker_canvas = Control.new()
	marker_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_canvas.draw.connect(_draw_marker)
	marker_layer.add_child(marker_canvas)
	main.practice_started.connect(_on_practice_started)
	main.mode_changed.connect(func(_mode: String) -> void: sync(main.sim))


func _process(delta: float) -> void:
	sync(main.sim)
	_fit_camera(delta)
	marker_canvas.queue_redraw()


## Smoothed framing around the player and all active enemies. Practice follows the player.
func _fit_camera(delta: float) -> void:
	var sim = main.sim
	if not sim.ships.has(sim.PLAYER_ID):
		return
	var desired_zoom := 1.0
	var screen := get_viewport_rect().size
	var bounds: Variant = _active_bounds(sim)
	if bounds != null:
		desired_zoom = clampf(minf((screen.x - FIT_MARGIN_X) / (2.0 * maxf(bounds.size.x, 1.0)),
			(screen.y - FIT_MARGIN_Y) / (2.0 * maxf(bounds.size.y, 1.0))), ZOOM_MIN, ZOOM_MAX)
	camera.zoom = camera.zoom.lerp(Vector2.ONE * desired_zoom, 1.0 - exp(-ZOOM_SMOOTH * maxf(delta, 0.0)))
	# Clamp the center so the viewport stays inside the arena where it is wider than it.
	var half: Vector2 = screen / (2.0 * camera.zoom.x)
	var desired_center := _desired_camera_center(sim)
	var clamped := desired_center
	if Definitions.ARENA_SIZE.x > half.x * 2.0:
		clamped.x = clampf(desired_center.x, half.x, Definitions.ARENA_SIZE.x - half.x)
	if Definitions.ARENA_SIZE.y > half.y * 2.0:
		clamped.y = clampf(desired_center.y, half.y, Definitions.ARENA_SIZE.y - half.y)
	camera.position = clamped
	queue_redraw()


## Bounding box of player and active opposition; practice targets are not framed.
func _active_bounds(sim) -> Variant:
	if sim.preset_id == "practice":
		return null
	var player: Vector2 = sim.ships[sim.PLAYER_ID]["position"]
	var low := player
	var high := player
	var found := false
	for id in sim.ships:
		var ship: Dictionary = sim.ships[id]
		if ship["team"] == sim.TEAM_OPPOSITION and ship["active"]:
			low = low.min(ship["position"])
			high = high.max(ship["position"])
			found = true
	return Rect2(low, high - low) if found else null


## Reconciles ship nodes with sim.ships by stable id and points the camera at the player.
func sync(sim) -> void:
	water.set_wind(sim.wind_heading)
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
		var condition: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
		node.modulate = Color.WHITE.lerp(Color(0.65, 0.5, 0.44), 1.0 - ship["hull"] / condition["hull"])
		for patch in node.get_node("Sails").get_children():
			patch.scale = REEFED_SAIL_SCALE if ship["reefed"] else Vector2.ONE
			patch.color = Color(0.96, 0.93, 0.84, 0.95).lerp(Color(0.48, 0.42, 0.36), 1.0 - ship["sails"] / condition["sails"])
	if sim.ships.has(sim.PLAYER_ID):
		# Raw follow target; _fit_camera refines zoom/center each process frame.
		camera.position = _desired_camera_center(sim)
	queue_redraw()


func _desired_camera_center(sim) -> Vector2:
	var player: Vector2 = sim.ships[sim.PLAYER_ID]["position"]
	var bounds: Variant = _active_bounds(sim)
	if bounds == null:
		return player
	return bounds.get_center()


func _on_practice_started() -> void:
	sync(main.sim)
	camera.reset_smoothing()
	_fit_camera(0.0)


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
	# Translucent shallows tint preserves the animated water beneath the safety hatch.
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
	_draw_combat()


func _draw_combat() -> void:
	if main == null or main.sim.ships.is_empty():
		return
	var sim = main.sim
	var font := ThemeDB.fallback_font
	var player: Dictionary = sim.ships.get(sim.PLAYER_ID, {})
	if not player.is_empty() and player["active"]:
		for side in Definitions.SIDES:
			var aim: Dictionary = sim.aim_for(sim.PLAYER_ID, side)
			var bearing: float = player["heading"] + (-PI / 2.0 if side == "port" else PI / 2.0)
			var radius: float = aim["range"]
			var ink := Color(1.0, 0.94, 0.67, 0.5) if aim["target_id"] != null else Color(1.0, 1.0, 1.0, 0.25)
			for edge in [-1.0, 1.0]:
				draw_line(player["position"], player["position"] + Vector2.from_angle(bearing + edge * Definitions.ARC_HALF_ANGLE) * radius, ink, 1.5)
			draw_arc(player["position"], radius, bearing - Definitions.ARC_HALF_ANGLE,
				bearing + Definitions.ARC_HALF_ANGLE, 24, ink, 2.0)
	for id in sim.ships:
		var ship: Dictionary = sim.ships[id]
		if ship["role"] != "practice_target":
			continue
		var p: Vector2 = ship["position"]
		var r: float = Definitions.VESSELS[ship["vessel_id"]]["radius"] + 12
		draw_arc(p, r, 0, TAU, 32, TARGET_INK, 3.0)
		var title := "TARGET · %s" % (" / ".join(ship["defeat_reasons"]).to_upper() if not ship["active"] else "BRIG")
		_draw_text(font, p + Vector2(-50, -r - 12), title, TARGET_INK)
	if sim.ships.has(3):
		for id in [2, 3]:
			var enemy: Dictionary = sim.ships[id]
			if enemy["active"]:
				var p: Vector2 = enemy["position"]
				var ink := ENEMY_INK
				if id == 2:
					draw_colored_polygon(PackedVector2Array([p + Vector2(0, -43), p + Vector2(-7, -32), p + Vector2(7, -32)]), ink)
				else:
					draw_colored_polygon(PackedVector2Array([p + Vector2(0, -44), p + Vector2(-7, -37), p + Vector2(0, -30), p + Vector2(7, -37)]), ink)
				_draw_text(font, p + Vector2(12, -30), "Sloop %s" % ("A" if id == 2 else "B"), ink)
	for shot in sim.projectiles:
		var p: Vector2 = shot["position"]
		draw_circle(p, 5, Color.BLACK)
		draw_circle(p, 3, SHOT_INK)
		draw_line(p - shot["direction"] * 11, p, SHOT_INK, 2.0)
	for cue in _cues:
		var p: Vector2 = cue["position"]
		var fraction: float = float(cue["ticks"]) / (16.0 if cue["type"] == "shot" else 48.0)
		match cue["type"]:
			"shot":
				var ship: Dictionary = sim.ships.get(cue["ship_id"], {})
				if not ship.is_empty():
					p = cue["position"] + cue["direction"] * Definitions.VESSELS[ship["vessel_id"]]["radius"]
				draw_circle(p, 4 + 6 * fraction, Color(1.0, 0.9, 0.5, 0.8 * fraction))
			"hit":
				draw_arc(p, 9 + 12 * (1.0 - fraction), 0, TAU, 24, TARGET_INK * Color(1, 1, 1, fraction), 3.0)
				draw_line(p + Vector2(-7, -7), p + Vector2(7, 7), Color.WHITE, 2.0)
				if cue["track"] == "crew":
					_draw_text(font, p + Vector2(12, -16), "CREW -%d" % cue["damage"], Color.WHITE)
			"splash":
				draw_arc(p, 7 + 12 * (1.0 - fraction), 0, TAU, 24, Color(0.9, 0.98, 1, fraction), 2.0)
				draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), Color.WHITE, 2.0)
			"ship_defeated":
				_draw_text(font, p + Vector2(-32, -20), "DEFEATED", TARGET_INK)


## The rectangle includes the four-pixel text outline; drawing uses this same placement.
func marker_label_rect(sim, id: int, p: Vector2, center: Vector2, screen: Rect2) -> Rect2:
	var target: Vector2 = sim.ships[id]["position"]
	var direction := (target - center).normalized()
	var label := _marker_label(sim, id)
	var font := ThemeDB.fallback_font
	var size := Vector2(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 8, font.get_height(18) + 8)
	var origin := p - direction * 45 + Vector2(-44, 1 - font.get_ascent(18))
	return Rect2(origin.clamp(screen.position + Vector2(4, 4), screen.end - size - Vector2(4, 4)), size)


func _marker_label(sim, id: int) -> String:
	var label := "TARGET" if sim.preset_id == "practice" else "Enemy A"
	if sim.ships.has(3):
		label = "Sloop %s" % ("A" if id == 2 else "B")
	if sim.preset_id != "practice":
		label += " · %d" % roundi(sim.ships[id]["position"].distance_to(sim.ships[sim.PLAYER_ID]["position"]))
	return label


## Stable-ID edge placements; separate measured labels and arrow points along the edge.
func enemy_markers(sim, center: Vector2, screen: Rect2) -> Dictionary:
	var positions := {}
	var ids: Array = sim.ships.keys()
	ids.sort()
	var safe := screen.grow(-MARKER_INSET)
	for id in ids:
		var enemy: Dictionary = sim.ships[id]
		if enemy["team"] != sim.TEAM_OPPOSITION or not enemy["active"]:
			continue
		var marker := target_marker(center, enemy["position"], screen)
		if not marker["offscreen"]:
			continue
		var p: Vector2 = marker["position"]
		for other_id in positions:
			var other: Vector2 = positions[other_id]
			var previous := marker_label_rect(sim, other_id, other, center, screen)
			var current := marker_label_rect(sim, id, p, center, screen)
			if p.distance_to(other) < 24.0 or current.intersects(previous):
				var vertical := is_equal_approx(p.x, safe.position.x) or is_equal_approx(p.x, safe.end.x)
				var step := maxf(24.0, maxf(current.size.y, previous.size.y) + 4.0) if vertical else maxf(24.0, maxf(current.size.x, previous.size.x) + 4.0)
				for sign in [1.0, -1.0]:
					var candidate := p + (Vector2(0, sign * step) if vertical else Vector2(sign * step, 0))
					candidate = candidate.clamp(safe.position, safe.end)
					if candidate.distance_to(other) >= 24.0 and not marker_label_rect(sim, id, candidate, center, screen).intersects(previous):
						p = candidate
						break
		positions[id] = p
	return positions


func _draw_marker() -> void:
	if main == null or main.sim.ships.is_empty():
		return
	var sim = main.sim
	var screen := Rect2(Vector2.ZERO, marker_canvas.size)
	var center := camera.get_screen_center_position()
	var markers := enemy_markers(sim, center, screen)
	for id in markers:
		var target: Vector2 = sim.ships[id]["position"]
		var p: Vector2 = markers[id]
		var direction: Vector2 = (target - center).normalized()
		var across := direction.orthogonal()
		var ink := ENEMY_INK if sim.preset_id != "practice" else TARGET_INK
		if sim.ships.has(3) and id == 3:
			marker_canvas.draw_colored_polygon(PackedVector2Array([p + direction * 14, p + across * 10,
				p - direction * 14, p - across * 10]), ink)
		else:
			marker_canvas.draw_colored_polygon(PackedVector2Array([p + direction * 14, p - direction * 8 + across * 9,
				p - direction * 8 - across * 9]), ink)
		var label := _marker_label(sim, id)
		var rect := marker_label_rect(sim, id, p, center, screen)
		var label_pos := rect.position + Vector2(4, ThemeDB.fallback_font.get_ascent(18) + 4)
		marker_canvas.draw_string_outline(ThemeDB.fallback_font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
		marker_canvas.draw_string(ThemeDB.fallback_font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)


func _draw_text(font: Font, p: Vector2, text: String, ink: Color) -> void:
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)


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
