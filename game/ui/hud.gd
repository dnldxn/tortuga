extends Control
## Read-only sailing HUD. refresh(sim) re-reads sim state/definitions; never mutates sim.

const Definitions := preload("res://sim/definitions.gd")
const Bindings := preload("res://input_bindings.gd")

const GUIDANCE := "Full sails: faster · Reefed: tighter turns · Into the wind is slow, but you can still turn."
const BANNER := "Sailing practice — no target yet."
const COMPASS := ["east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast"]

var name_label: Label
var condition_label: Label
var speed_label: Label
var sails_label: Label
var wind_label: Label
var wind_arrow: Control  # draws an arrow along the wind's travel direction
var wind_heading := 0.0  # copied from sim on refresh; drives the arrow
var bindings_label: Label


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var top := HBoxContainer.new()
	top.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(top)
	var status := VBoxContainer.new()
	name_label = _label(status)
	condition_label = _label(status)
	speed_label = _label(status)
	sails_label = _label(status)
	var wind_row := HBoxContainer.new()
	wind_label = _label(wind_row)
	wind_arrow = Control.new()
	wind_arrow.name = "WindArrow"
	wind_arrow.custom_minimum_size = Vector2(48, 48)
	wind_arrow.draw.connect(_draw_wind_arrow)
	wind_row.add_child(wind_arrow)
	status.add_child(wind_row)
	top.add_child(_panel(status))
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var banner := VBoxContainer.new()
	var banner_label := _label(banner)
	banner_label.text = BANNER
	top.add_child(_panel(banner, SIZE_SHRINK_BEGIN))

	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	fill.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(fill)
	var help := VBoxContainer.new()
	var guidance_label := _label(help)
	guidance_label.text = GUIDANCE
	bindings_label = _label(help)
	column.add_child(_panel(help))


func refresh(sim) -> void:
	var ship: Dictionary = sim.ships.get(sim.PLAYER_ID, {})
	if ship.is_empty():
		return
	var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
	name_label.text = vessel["display_name"]
	condition_label.text = "Hull %d/%d · Sails %d/%d · Crew %d/%d" % [
		ship["hull"], vessel["hull"], ship["sails"], vessel["sails"], ship["crew"], vessel["crew"]]
	speed_label.text = "Sailing speed %d" % roundi(ship["speed"])
	sails_label.text = "REEFED" if ship["reefed"] else "FULL SAILS"
	var sector := posmod(roundi(sim.wind_heading / (PI / 4.0)), 8)
	wind_label.text = "Wind travels %s" % COMPASS[sector]
	wind_heading = sim.wind_heading
	wind_arrow.queue_redraw()
	bindings_label.text = "%s/%s steer · %s sails · %s pause" % [
		Bindings.binding_label("turn_left"), Bindings.binding_label("turn_right"),
		Bindings.binding_label("toggle_sails"), Bindings.binding_label("pause")]


## Arrow in the 48x48 WindArrow box, pointing where the wind travels (0 = east, clockwise).
func _draw_wind_arrow() -> void:
	var c := wind_arrow.size / 2.0
	var dir := Vector2.from_angle(wind_heading)
	var side := dir.orthogonal()
	wind_arrow.draw_circle(c, 23, Color(0, 0, 0, 0.45))
	wind_arrow.draw_line(c - dir * 16, c + dir * 6, Color.WHITE, 4.0)
	wind_arrow.draw_colored_polygon(PackedVector2Array([c + dir * 19, c + dir * 4 + side * 9, c + dir * 4 - side * 9]), Color.WHITE)


func _label(parent: Node) -> Label:
	var label := Label.new()
	parent.add_child(label)
	return label


func _panel(content: Control, v_flags := SIZE_FILL) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = v_flags
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(content)
	return panel
