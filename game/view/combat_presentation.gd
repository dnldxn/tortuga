extends RefCounted
## Read-only logical-canvas calculations and per-tick simulation event translation.

const Definitions := preload("res://sim/definitions.gd")
const SAFE := Rect2(32, 160, 1216, 400)
const ZOOM_MIN := 0.75
const ZOOM_MAX := 1.10
const CAMERA_MARGIN := 240.0


static func gameplay_rect(screen: Vector2) -> Rect2:
	var tuning: Dictionary = Definitions.PRESENTATION
	return Rect2(tuning.side_reserved, tuning.top_reserved, screen.x - 2 * tuning.side_reserved,
		screen.y - tuning.top_reserved - tuning.bottom_reserved).grow(-tuning.combat_inset)


static func padded_art_half(radius: float, heading: float) -> Vector2:
	var c := absf(cos(heading))
	var s := absf(sin(heading))
	return Vector2(radius * c + radius * .5 * s,
		radius * s + radius * .5 * c) + Vector2.ONE * Definitions.PRESENTATION.art_padding


static func zoom_for_extent(extent: Vector2, half_safe: Vector2) -> float:
	return clampf(minf(half_safe.x / maxf(extent.x, 1.0),
		half_safe.y / maxf(extent.y, 1.0)), ZOOM_MIN, ZOOM_MAX)


static func approach(value: float, target: float, rate: float, dt: float) -> float:
	return lerpf(value, target, 1.0 - exp(-rate * maxf(dt, 0.0)))


static func edge_point(point: Vector2, rect: Rect2) -> Vector2:
	var c := rect.get_center()
	var d := point - c
	var h := rect.size * .5
	if d.length_squared() < .000001:
		return c
	var k := minf(h.x / maxf(absf(d.x), .000001), h.y / maxf(absf(d.y), .000001))
	return c + d * k


static func normalize_events(events: Array) -> Array:
	var output := []
	var groups := {}
	for event in events:
		match event.get("type", ""):
			"shot":
				output.append(event.duplicate(true))
				var key := "%s/%s" % [event["ship_id"], event["side"]]
				if not groups.has(key):
					groups[key] = {"type": "volley", "ship_id": event["ship_id"], "side": event["side"],
						"position": event["position"], "ready_count": 0}
				groups[key]["ready_count"] += 1
			"hit":
				output.append({"type": "hit", "projectile_id": event["projectile_id"],
					"target_id": event["victim_id"], "position": event["position"],
					"track": event["track"], "damage": event["damage"], "ammo": event["ammo"]})
			"splash":
				output.append({"type": "splash", "projectile_id": event["projectile_id"], "position": event["position"]})
			"fire_rejected":
				if event["reason"] == "no_loaded_guns":
					output.append({"type": "empty", "ship_id": event["ship_id"], "side": event["side"]})
			"ship_defeated":
				output.append({"type": "defeated", "ship_id": event["ship_id"],
					"position": event["position"], "reasons": event["reasons"].duplicate()})
	for group in groups.values():
		output.append(group)
	return output


static func ship_label(sim, id: int) -> String:
	if sim.preset_id == "practice":
		return "Target"
	if sim.ships.has(3):
		return "Sloop A" if id == 2 else "Sloop B"
	return "Enemy A (%s)" % sim.ships[id]["vessel_id"].capitalize()


static func marker_badge(sim, id: int) -> String:
	if sim.preset_id == "practice":
		return ship_label(sim, id).to_upper()
	if sim.ships.has(3):
		return ship_label(sim, id).trim_prefix("Sloop ")
	return ship_label(sim, id).get_slice(" (", 0)


## Full logical viewport inside expanded arena AND player inside gameplay safe region.
static func clamp_center(center: Vector2, player: Vector2, zoom: float, screen: Vector2, arena: Vector2) -> Vector2:
	var half := screen / (2.0 * zoom)
	var safe := gameplay_rect(screen).grow(-Definitions.PRESENTATION.player_padding)
	var low := Vector2.ONE * -CAMERA_MARGIN + half
	var high := arena + Vector2.ONE * CAMERA_MARGIN - half
	var player_low := player + (screen * .5 - safe.end) / zoom
	var player_high := player + (screen * .5 - safe.position) / zoom
	low = low.max(player_low)
	high = high.min(player_high)
	return Vector2(clampf(center.x, low.x, high.x) if low.x <= high.x else player.x,
		clampf(center.y, low.y, high.y) if low.y <= high.y else player.y)


## Snapshot first entry along the actual forward lane, never center distance.
static func arc_reference(sim, event: Dictionary) -> Dictionary:
	var range_left: float = Definitions.AMMO[event["ammo"]]["range"]
	var start: Vector2 = event["position"]
	var end: Vector2 = start + event["direction"] * range_left
	var owner: Dictionary = sim.ships.get(event["ship_id"], {})
	var distance := INF
	var target := -1
	var ids: Array = sim.ships.keys()
	ids.sort()
	for id in ids:
		var ship: Dictionary = sim.ships[id]
		if id == event["ship_id"] or not ship["active"] or ship["team"] == owner.get("team", -1):
			continue
		var entry: float = sim.segment_circle(start, end, ship["position"], Definitions.VESSELS[ship["vessel_id"]]["radius"])
		if entry >= 0.0 and entry * range_left < distance:
			distance = entry * range_left
			target = id
	return {"distance": range_left * Definitions.PRESENTATION.arc_default_range if target < 0 else distance, "target_id": target}


static func elevation(traveled: float, reference: float) -> float:
	var tuning: Dictionary = Definitions.PRESENTATION
	if reference <= tuning.arc_close or traveled >= reference:
		return 0.0
	return tuning.arc_height * clampf((reference - tuning.arc_close) / tuning.arc_full, 0.0, 1.0) * sin(PI * clampf(traveled / reference, 0.0, 1.0))
