extends Node2D
## Read-only arena presentation: sea, shallows/coast, ship sprites and follow camera.
## Reads the parent controller's `sim` fresh every frame (it is replaced on return to
## selection) and never mutates it.

const Definitions := preload("res://sim/definitions.gd")
const ReefGlass := preload("res://view/reef_glass.gd")
const ShipView := preload("res://view/ship_3d_view.gd")
const Presentation := preload("res://view/combat_presentation.gd")

const SHALLOWS := Color(0.36, 0.72, 0.72, 0.25)
const HATCH := Color(0.9, 0.95, 0.85, 0.45)
const LAND := Color(0.42, 0.55, 0.3)
const SAND := Color(0.9, 0.82, 0.58)
const LIMIT := Color(1.0, 0.92, 0.55)
const WARNING := "Shallows / Turn back"
const TARGET_INK := Color(1.0, 0.9, 0.55)
const SHOT_INK := Color(1.0, 0.98, 0.85)
const ENEMY_INK := Color(1.0, 0.62, 0.45)

var main: Node
var camera := Camera2D.new()
var _ships := {}  # ship id -> Ship3DView
var _cues := []  # deep-copied events with ticks; never aliases sim.events
var marker_layer: CanvasLayer
var marker_canvas: Control
var water: Node2D
var _nearby := {}  # active opposition IDs with 1000/1100 world-unit hysteresis
var _camera_snap := true
var _screen_size := Vector2.ZERO
var _marker_edges := {}


func advance_effects() -> void:
	water.advance(main.DT, main.sim.wind_heading)
	for cue in _cues:
		cue["ticks"] -= 1
	_cues = _cues.filter(func(cue): return cue["ticks"] > 0)
	for cue in _cues:
		if cue["type"] == "damage" and cue["ticks"] <= 42:
			cue["settled"] = true
	queue_redraw()


func consume_events(events: Array) -> void:
	for event in events:
		if event["type"] in ["shot", "hit", "splash", "defeated"]:
			if event["type"] == "hit" and event.has("target_id"):
				var joined := false
				for previous in _cues:
					if previous["type"] == "damage" and not previous["settled"] and previous["target_id"] == event["target_id"] and previous["track"] == event["track"]:
						previous["damage"] += event["damage"]
						joined = true
						break
				if not joined:
					_add_cue({"type": "damage", "target_id": event["target_id"], "track": event["track"],
						"damage": event["damage"], "position": event["position"], "ticks": 48, "settled": false})
			var cue: Dictionary = event.duplicate(true)
			cue["ticks"] = 16 if cue["type"] == "shot" else (60 if cue["type"] == "defeated" else 27)
			_add_cue(cue)
	queue_redraw()


func _add_cue(cue: Dictionary) -> void:
	if _cues.size() >= 48:
		var evict := -1
		for i in _cues.size():
			if _cues[i]["type"] != "damage":
				evict = i
				break
		if evict < 0:
			for i in _cues.size():
				if _cues[i]["settled"]:
					evict = i
					break
		if evict < 0 and cue["type"] != "damage":
			return
		if evict < 0:
			evict = 0  # At most nine active ship/track groups; unreachable outside synthetic floods.
		_cues.remove_at(evict)
	_cues.append(cue)


func reset_effects() -> void:
	_cues.clear()
	_nearby.clear()
	_camera_snap = true
	water.reset(main.sim.wind_heading)
	queue_redraw()
	if marker_canvas != null:
		marker_canvas.queue_redraw()


## Camera-centered viewport coordinates, inset so the arrow and its label remain visible.
func target_marker(center: Vector2, target: Vector2, screen: Rect2) -> Dictionary:
	var projected: Vector2 = get_canvas_transform() * target
	var safe := Presentation.gameplay_rect(screen.size)
	return {"offscreen": not safe.has_point(projected), "position": Presentation.edge_point(projected, safe) if not safe.has_point(projected) else projected}


func _ready() -> void:
	main = get_parent()
	water = ReefGlass.new()
	water.name = "ReefGlass"
	add_child(water)
	camera.zoom = Vector2.ONE
	camera.position_smoothing_enabled = false
	camera.ignore_rotation = true
	camera.limit_left = -int(Presentation.CAMERA_MARGIN)
	camera.limit_top = -int(Presentation.CAMERA_MARGIN)
	camera.limit_right = int(Definitions.ARENA_SIZE.x + Presentation.CAMERA_MARGIN)
	camera.limit_bottom = int(Definitions.ARENA_SIZE.y + Presentation.CAMERA_MARGIN)
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
	get_viewport().size_changed.connect(func() -> void:
		_nearby.clear()
		_camera_snap = true)


func _process(delta: float) -> void:
	sync(main.sim)
	for ship_view in _ships.values():
		if ship_view.visible and main.mode == "sailing":
			ship_view.advance_motion(delta)
	if main.mode == "sailing" or main.mode == "result":
		_fit_camera(delta)
	marker_canvas.queue_redraw()


## Smoothed framing around the player and all active enemies. Practice follows the player.
func _fit_camera(delta: float) -> void:
	var sim = main.sim
	if not sim.ships.has(sim.PLAYER_ID):
		return
	var screen := get_viewport_rect().size
	if screen != _screen_size:
		_screen_size = screen
		_nearby.clear()
		_camera_snap = true
	var player: Vector2 = sim.ships[sim.PLAYER_ID]["position"]
	var bounds: Rect2 = _active_bounds(sim)
	var desired_center: Vector2 = player + (bounds.get_center() - player).limit_length(160.0)
	var extent := Vector2.ZERO
	for corner in [bounds.position, Vector2(bounds.end.x, bounds.position.y),
		Vector2(bounds.position.x, bounds.end.y), bounds.end]:
		extent = extent.max((corner - desired_center).abs())
	var desired_zoom: float = Presentation.zoom_for_extent(extent, screen * Vector2(608.0 / 1280.0, 200.0 / 720.0))
	var zoom: float = desired_zoom if _camera_snap else Presentation.approach(camera.zoom.x,
		desired_zoom, 6.0 if desired_zoom < camera.zoom.x else 2.0, delta)
	zoom = clampf(zoom, Presentation.ZOOM_MIN, Presentation.ZOOM_MAX)
	camera.zoom = Vector2.ONE * zoom
	var center: Vector2 = desired_center if _camera_snap else Vector2(
		Presentation.approach(camera.position.x, desired_center.x, 6.0, delta),
		Presentation.approach(camera.position.y, desired_center.y, 6.0, delta))
	camera.position = Presentation.clamp_center(center, player, zoom, screen, Definitions.ARENA_SIZE)
	_camera_snap = false
	queue_redraw()


## Padded art bounds of player and at most two nearby active opponents.
func _active_bounds(sim) -> Rect2:
	var player: Vector2 = sim.ships[sim.PLAYER_ID]["position"]
	var ids := []
	for id in _nearby.keys():
		if not sim.ships.has(id) or not sim.ships[id]["active"]:
			_nearby.erase(id)
	for id in sim.ships:
		var ship: Dictionary = sim.ships[id]
		if ship["team"] != sim.TEAM_OPPOSITION or not ship["active"]:
			_nearby.erase(id)
			continue
		var distance: float = player.distance_to(ship["position"])
		if distance <= (1100.0 if _nearby.has(id) else 1000.0):
			_nearby[id] = true
		else:
			_nearby.erase(id)
		if _nearby.has(id):
			ids.append(id)
	ids.sort()
	for id in ids.slice(2):
		_nearby.erase(id)
	var low := player
	var high := player
	var framed := [sim.PLAYER_ID]
	framed.append_array(ids.slice(0, 2))
	for id in framed:
		var ship: Dictionary = sim.ships[id]
		var radius: float = Definitions.VESSELS[ship["vessel_id"]]["radius"]
		var pad: Vector2 = Presentation.padded_art_half(radius, ship["heading"])
		low = low.min(ship["position"] - pad)
		high = high.max(ship["position"] + pad)
	return Rect2(low, high - low)


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
			_ships[id].motion_phase = float(id) * 1.9
			add_child(_ships[id])
		var node: Node2D = _ships[id]
		# A disabled hull remains in the arena as a subdued, untargetable visual.
		node.set_ship_active(true)
		node.modulate = Color(0.58, 0.64, 0.68, 0.7) if not ship["active"] else Color.WHITE
		node.position = ship["position"]
		var condition: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
		node.set_ship_state(ship["heading"], sim.wind_heading,
			ship["speed"] / condition["full_speed"], ship["reefed"],
			ship["hull"] / condition["hull"], ship["sails"] / condition["sails"])
	queue_redraw()


func _desired_camera_center(sim) -> Vector2:
	var player: Vector2 = sim.ships[sim.PLAYER_ID]["position"]
	var bounds: Rect2 = _active_bounds(sim)
	return player + (bounds.get_center() - player).limit_length(160.0)


func _on_practice_started() -> void:
	sync(main.sim)
	_nearby.clear()
	_camera_snap = true
	_fit_camera(0.0)


func _make_ship(vessel_id: String) -> Node2D:
	var ship_view := ShipView.new()
	ship_view.setup(vessel_id, Definitions.VESSELS[vessel_id]["radius"])
	return ship_view


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
					draw_colored_polygon(PackedVector2Array([p + Vector2(0, -54), p + Vector2(-7, -40), p + Vector2(7, -40)]), ink)
				else:
					draw_colored_polygon(PackedVector2Array([p + Vector2(0, -55), p + Vector2(-7, -46), p + Vector2(0, -38), p + Vector2(7, -46)]), ink)
				_draw_text(font, p + Vector2(15, -38), Presentation.ship_label(sim, id), ink)
	for shot in sim.projectiles:
		var p: Vector2 = shot["position"]
		draw_circle(p, 5, Color.BLACK)
		draw_circle(p, 3, SHOT_INK)
		draw_line(p - shot["direction"] * 11, p, SHOT_INK, 2.0)
	for cue in _cues:
		var p: Vector2 = cue["position"]
		var fraction: float = float(cue["ticks"]) / (16.0 if cue["type"] == "shot" else (60.0 if cue["type"] == "defeated" else (48.0 if cue["type"] == "damage" else 27.0)))
		match cue["type"]:
			"shot":
				var ship: Dictionary = sim.ships.get(cue["ship_id"], {})
				if not ship.is_empty():
					p = cue["position"] + cue["direction"] * Definitions.VESSELS[ship["vessel_id"]]["radius"]
				draw_circle(p, 4 + 6 * fraction, Color(1.0, 0.9, 0.5, 0.8 * fraction))
			"hit":
				match cue.get("ammo", "round"):
					"round":
						for i in 6:
							var d := Vector2.from_angle(i * TAU / 6.0)
							draw_line(p + d * 5, p + d * (18 - 8 * fraction), TARGET_INK, 2)
					"chain":
						for x in [-7, 7]:
							draw_arc(p + Vector2(x, 0), 6, 0, TAU, 12, Color.WHITE, 2)
							draw_line(p + Vector2(-2, -4), p + Vector2(2, 4), Color.WHITE, 2)
					"grape":
						for d in [Vector2(-8, -6), Vector2(9, -3), Vector2(0, 9)]:
							draw_circle(p + d * (1.5 - fraction * .5), 3, Color.WHITE)
			"splash":
				draw_arc(p, 7 + 12 * (1.0 - fraction), 0, TAU, 24, Color(0.9, 0.98, 1, fraction), 2.0)
				draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), Color.WHITE, 2.0)
			"damage":
				if cue["settled"]:
					_draw_text(font, p + Vector2(12, -16), "%s −%d" % [cue["track"].capitalize(), roundi(cue["damage"])], Color.WHITE)
			"defeated":
				_draw_text(font, p + Vector2(-32, -20), "SUNK" if "sunk" in cue["reasons"] else "DISABLED · " + " · ".join(cue["reasons"]).to_upper(), Color(TARGET_INK.r, TARGET_INK.g, TARGET_INK.b, fraction))


## The rectangle includes the four-pixel text outline; drawing uses this same placement.
func marker_label_rect(sim, id: int, p: Vector2, center: Vector2, screen: Rect2) -> Rect2:
	var safe := Presentation.gameplay_rect(screen.size)
	var size := Vector2(180, 40)
	var direction: Vector2 = (sim.ships[id]["position"] - center).normalized()
	var origin: Vector2 = p - direction * 50 - size * .5
	return Rect2(origin.clamp(safe.position, safe.end - size), size)


func _marker_edge(point: Vector2, safe: Rect2) -> String:
	if is_equal_approx(point.x, safe.position.x):
		return "west"
	if is_equal_approx(point.x, safe.end.x):
		return "east"
	if is_equal_approx(point.y, safe.position.y):
		return "north"
	return "south"


func _marker_label(sim, id: int) -> String:
	var label: String = Presentation.marker_badge(sim, id)
	if sim.preset_id != "practice":
		label += " • %s wu" % _distance_label(roundi(sim.ships[id]["position"].distance_to(sim.ships[sim.PLAYER_ID]["position"]) / 10.0) * 10)
	return label


func _distance_label(distance: int) -> String:
	var text := str(distance)
	if distance >= 1000:
		text = text.substr(0, text.length() - 3) + "," + text.substr(text.length() - 3)
	return text


## Stable-ID edge placements; separate measured labels and arrow points along the edge.
func enemy_markers(sim, center: Vector2, screen: Rect2) -> Dictionary:
	var positions := {}
	_marker_edges.clear()
	var ids: Array = sim.ships.keys()
	ids.sort()
	var safe := Presentation.gameplay_rect(screen.size)
	for id in ids:
		var enemy: Dictionary = sim.ships[id]
		if enemy["team"] != sim.TEAM_OPPOSITION or not enemy["active"]:
			continue
		var radius: float = Definitions.VESSELS[enemy["vessel_id"]]["radius"]
		var projected: Vector2 = get_canvas_transform() * enemy["position"]
		var padded_half: Vector2 = Presentation.padded_art_half(radius, enemy["heading"]) * camera.zoom
		var silhouette := Rect2(projected - padded_half, padded_half * 2.0)
		if safe.encloses(silhouette):
			continue
		var p: Vector2 = Presentation.edge_point(projected, safe)
		_marker_edges[id] = p
		for other_id in positions:
			var other: Vector2 = positions[other_id]
			var previous := marker_label_rect(sim, other_id, other, center, screen)
			var current := marker_label_rect(sim, id, p, center, screen)
			if current.intersects(previous) or p.distance_to(other) < 24:
				var edge := _marker_edge(p, safe)
				var same_edge := edge == _marker_edge(_marker_edges[other_id], safe)
				var vertical := edge == "east" or edge == "west"
				var step := 48.0 if vertical else 188.0
				if same_edge:
					for sign in [1.0, -1.0, 2.0, -2.0]:
						var candidate: Vector2 = (p + (Vector2(0, sign * step) if vertical else Vector2(sign * step, 0))).clamp(safe.position, safe.end)
						if candidate.distance_to(other) >= 24 and not marker_label_rect(sim, id, candidate, center, screen).intersects(previous):
							p = candidate
							break
				else:
					p += Vector2(-48 if p.x > screen.get_center().x else 48,
						-48 if p.y > screen.get_center().y else 48)
		positions[id] = p
	return positions


## Resolved positions used by every drawn part of each indicator.
func indicator_geometry(sim, center: Vector2, screen: Rect2) -> Dictionary:
	var markers := enemy_markers(sim, center, screen)
	var geometry := {}
	for id in markers:
		var direction: Vector2 = (sim.ships[id]["position"] - center).normalized()
		var arrow: Vector2 = markers[id]
		geometry[id] = {"arrow": arrow, "badge": arrow - direction * 22,
			"true_edge": _marker_edges[id], "identity": Presentation.marker_badge(sim, id)}
	return geometry


func _draw_marker() -> void:
	if main == null or main.sim.ships.is_empty():
		return
	var sim = main.sim
	var screen := Rect2(Vector2.ZERO, marker_canvas.size)
	var center := camera.get_screen_center_position()
	var geometry := indicator_geometry(sim, center, screen)
	for id in geometry:
		var target: Vector2 = sim.ships[id]["position"]
		var p: Vector2 = geometry[id]["arrow"]
		var direction: Vector2 = (target - center).normalized()
		var across := direction.orthogonal()
		var ink := ENEMY_INK if sim.preset_id != "practice" else TARGET_INK
		var true_edge: Vector2 = geometry[id]["true_edge"]
		if p != true_edge:
			marker_canvas.draw_line(true_edge, p - direction * 8, ink, 1.5)
		# The triangle always points at the true bearing; the adjacent shape is the ID.
		marker_canvas.draw_colored_polygon(PackedVector2Array([p + direction * 16,
			p - direction * 7 + across * 8, p - direction * 7 - across * 8]), ink)
		var badge: Vector2 = geometry[id]["badge"]
		if sim.ships.has(3) and id == 3:
			marker_canvas.draw_colored_polygon(PackedVector2Array([badge + direction * 6, badge + across * 6,
				badge - direction * 6, badge - across * 6]), ink)
		else:
			marker_canvas.draw_colored_polygon(PackedVector2Array([badge + direction * 7,
				badge - direction * 5 + across * 6, badge - direction * 5 - across * 6]), ink)
		var label := _marker_label(sim, id)
		var rect := marker_label_rect(sim, id, p, center, screen)
		marker_canvas.draw_rect(rect, Color(0.04, 0.07, 0.12, 0.95))
		marker_canvas.draw_rect(rect, ink, false, 2)
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
