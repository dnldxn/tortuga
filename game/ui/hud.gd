extends Control
## Read-only practice HUD: four compact corner panels (own ship, enemy, port and starboard
## broadsides) so the arena centre stays clear. Help text lives in the pause menu.
## Feedback ages in physics ticks.

const Definitions := preload("res://sim/definitions.gd")

const COMPASS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const AIM_TEXT := {"assisted": "assisted", "outside_arc": "outside arc", "out_of_range": "out of range", "no_active_enemy": "no active enemy"}
const STATS := ["hull", "sails", "crew"]
const MARGIN := 12
const ICONS := {
	"hull": preload("res://assets/ui/hull.svg"), "sails": preload("res://assets/ui/sails.svg"),
	"crew": preload("res://assets/ui/crew.svg"), "speed": preload("res://assets/ui/speed.svg"),
	"cannon": preload("res://assets/ui/cannon.svg"), "distance": preload("res://assets/ui/distance.svg")}

var name_label: Label
var speed_label: Label
var wind_label: Label
var wind_arrow: Control
var wind_heading := 0.0
var target_label: Label
var target_state_label: Label
var panels := []  # the four corner PanelContainers
var ship_stats := {}  # stat -> [ProgressBar, Label]
var target_stats := {}
var side_labels := {}  # side -> header Label
var gun_bars := {}  # side -> Array[ProgressBar], prebuilt for the largest vessel
var aim_labels := {}
var feedback_labels := {}
var _feedback := {}  # side -> remaining physics ticks


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var status := _corner(PRESET_TOP_LEFT)
	name_label = _label(status)
	for stat in STATS:
		ship_stats[stat] = _stat_row(status, stat)
	var motion := _row(status)
	_icon(motion, "speed")
	speed_label = _label(motion)
	wind_arrow = Control.new()
	wind_arrow.name = "WindArrow"
	wind_arrow.custom_minimum_size = Vector2(32, 32)
	wind_arrow.draw.connect(_draw_wind_arrow)
	motion.add_child(wind_arrow)
	wind_label = _label(motion)
	var target := _corner(PRESET_TOP_RIGHT)
	target_label = _label(target)
	for stat in STATS:
		target_stats[stat] = _stat_row(target, stat)
	var where := _row(target)
	_icon(where, "distance")
	target_state_label = _label(where)
	var max_guns := 0
	for vessel in Definitions.VESSELS.values():
		max_guns = maxi(max_guns, vessel["guns_per_side"])
	for side in Definitions.SIDES:
		_make_side(_corner(PRESET_BOTTOM_LEFT if side == "port" else PRESET_BOTTOM_RIGHT), side, max_guns)


func _make_side(parent: Node, side: String, max_guns: int) -> void:
	var header := _row(parent)
	_icon(header, "cannon")
	side_labels[side] = _label(header)
	var guns := _row(parent)
	guns.add_theme_constant_override("separation", 4)
	gun_bars[side] = []
	for i in max_guns:
		var bar := _bar(guns, Vector2(12, 22))
		bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		gun_bars[side].append(bar)
	aim_labels[side] = _label(parent)
	feedback_labels[side] = _label(parent)
	feedback_labels[side].add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	feedback_labels[side].visible = false


func reset_effects() -> void:
	_feedback.clear()
	for label in feedback_labels.values():
		label.text = ""
		label.visible = false


func consume_events(events: Array) -> void:
	for event in events:
		if event["type"] == "fire_rejected" and event["ship_id"] == 1:
			_feedback[event["side"]] = 90
		elif event["type"] == "shot" and event["ship_id"] == 1:
			_feedback.erase(event["side"])


func advance_effects() -> void:
	for side in _feedback.keys():
		_feedback[side] -= 1
		if _feedback[side] <= 0:
			_feedback.erase(side)


func refresh(sim) -> void:
	var ship: Dictionary = sim.ships.get(sim.PLAYER_ID, {})
	if ship.is_empty():
		return
	var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
	name_label.text = "%s · %s" % [vessel["display_name"], "REEFED" if ship["reefed"] else "FULL SAILS"]
	_set_stats(ship_stats, ship, vessel)
	speed_label.text = "%d" % roundi(ship["speed"])
	var sector := posmod(roundi(sim.wind_heading / (PI / 4.0)), 8)
	wind_label.text = "Wind %s" % COMPASS[sector]
	wind_heading = sim.wind_heading
	wind_arrow.queue_redraw()
	var target: Dictionary = sim.ships.get(2, {})
	panels[1].visible = not target.is_empty()
	if not target.is_empty():
		var target_vessel: Dictionary = Definitions.VESSELS[target["vessel_id"]]
		target_label.text = "Enemy A (%s)" % target_vessel["display_name"] if sim.preset_id != "practice" else "TARGET · Brig"
		_set_stats(target_stats, target, target_vessel)
		var distance := roundi(target["position"].distance_to(ship["position"]))
		var state := "Active" if target["active"] else " · ".join(target["defeat_reasons"]).to_upper()
		target_state_label.text = "%d · %s" % [distance, state]
	for side in Definitions.SIDES:
		var weapon: Dictionary = ship["weapons"][side]
		var loads: Array = weapon["loads"]
		var ready := loads.filter(func(load): return load == 1.0).size()
		var bars: Array = gun_bars[side]
		for i in bars.size():
			bars[i].visible = i < loads.size()
			if i < loads.size():
				# Only a fully loaded gun reads 100; a nearly loaded one caps at 99.
				bars[i].value = 100 if loads[i] == 1.0 else mini(99, roundi(loads[i] * 100.0))
		side_labels[side].text = "%s · %s · %d/%d ready" % [
			side.capitalize(), Definitions.AMMO[weapon["ammo"]]["display_name"], ready, loads.size()]
		var aim: Dictionary = sim.aim_for(sim.PLAYER_ID, side)
		var aim_text: String = "target %d · assisted" % aim["target_id"] if aim["target_id"] != null else AIM_TEXT[aim["reason"]]
		aim_labels[side].text = "Range %d · %s" % [roundi(aim["range"]), aim_text]
		feedback_labels[side].text = "no loaded guns" if _feedback.has(side) else ""
		feedback_labels[side].visible = _feedback.has(side)


func _set_stats(rows: Dictionary, ship: Dictionary, vessel: Dictionary) -> void:
	for stat in STATS:
		var bar: ProgressBar = rows[stat][0]
		bar.max_value = vessel[stat]
		bar.value = ship[stat]
		rows[stat][1].text = "%d/%d" % [ship[stat], vessel[stat]]


func _draw_wind_arrow() -> void:
	var c := wind_arrow.size / 2.0
	var dir := Vector2.from_angle(wind_heading)
	var side := dir.orthogonal()
	wind_arrow.draw_circle(c, 15, Color(0, 0, 0, 0.45))
	wind_arrow.draw_line(c - dir * 11, c + dir * 4, Color.WHITE, 3.0)
	wind_arrow.draw_colored_polygon(PackedVector2Array([c + dir * 13, c + dir * 3 + side * 6, c + dir * 3 - side * 6]), Color.WHITE)


## A panel pinned to one screen corner, growing inward as its content grows.
func _corner(preset: LayoutPreset) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.set_anchors_and_offsets_preset(preset, PRESET_MODE_MINSIZE, MARGIN)
	panel.grow_horizontal = GROW_DIRECTION_BEGIN if preset in [PRESET_TOP_RIGHT, PRESET_BOTTOM_RIGHT] else GROW_DIRECTION_END
	panel.grow_vertical = GROW_DIRECTION_BEGIN if preset in [PRESET_BOTTOM_LEFT, PRESET_BOTTOM_RIGHT] else GROW_DIRECTION_END
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	panels.append(panel)
	return box


func _stat_row(parent: Node, stat: String) -> Array:
	var row := _row(parent)
	_icon(row, stat)
	var bar := _bar(row, Vector2(96, 12))
	var label := _label(row)
	label.custom_minimum_size.x = 80
	return [bar, label]


func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row


func _icon(parent: Node, id: String) -> void:
	var icon := TextureRect.new()
	icon.texture = ICONS[id]
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size_flags_vertical = SIZE_SHRINK_CENTER
	parent.add_child(icon)


func _bar(parent: Node, min_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = min_size
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


func _label(parent: Node) -> Label:
	var label := Label.new()
	parent.add_child(label)
	return label
