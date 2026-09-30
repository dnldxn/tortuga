extends Control
## Read-only practice HUD: corners carry ship/weapon state; feedback ages in physics ticks.

const Definitions := preload("res://sim/definitions.gd")
const Bindings := preload("res://input_bindings.gd")

const GUIDANCE := "Full sails: faster · Reefed: tighter turns · Into the wind is slow, but you can still turn."
const BANNER := "TARGET · Brig"
const COMPASS := ["east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast"]
const AIM_TEXT := {"assisted": "assisted", "outside_arc": "outside arc", "out_of_range": "out of range", "no_active_enemy": "no active enemy"}

var name_label: Label
var condition_label: Label
var speed_label: Label
var sails_label: Label
var wind_label: Label
var wind_arrow: Control
var wind_heading := 0.0
var bindings_label: Label
var target_label: Label
var side_labels := {}
var feedback_labels := {}
var _feedback := {}  # side -> remaining physics ticks


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
	var left_stack := VBoxContainer.new()
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
	left_stack.add_child(_panel(status))
	var port := VBoxContainer.new()
	_make_side(port, "port")
	left_stack.add_child(_panel(port))
	top.add_child(left_stack)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var right_stack := VBoxContainer.new()
	var target_box := VBoxContainer.new()
	target_label = _label(target_box)
	right_stack.add_child(_panel(target_box))
	var starboard := VBoxContainer.new()
	_make_side(starboard, "starboard")
	right_stack.add_child(_panel(starboard))
	top.add_child(right_stack)
	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	fill.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(fill)
	var help := VBoxContainer.new()
	var guidance_label := _label(help)
	guidance_label.text = GUIDANCE
	_label(help).text = "Round: hull / Chain: sails / Grape: crew · Changing ammo restarts that side's reload."
	bindings_label = _label(help)
	column.add_child(_panel(help))


func _make_side(parent: Node, side: String) -> void:
	side_labels[side] = _label(parent)
	feedback_labels[side] = _label(parent)


func reset_effects() -> void:
	_feedback.clear()
	for label in feedback_labels.values():
		label.text = ""


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
	name_label.text = vessel["display_name"]
	condition_label.text = "Hull %d/%d · Sails %d/%d · Crew %d/%d" % [
		ship["hull"], vessel["hull"], ship["sails"], vessel["sails"], ship["crew"], vessel["crew"]]
	speed_label.text = "Sailing speed %d" % roundi(ship["speed"])
	sails_label.text = "REEFED" if ship["reefed"] else "FULL SAILS"
	var sector := posmod(roundi(sim.wind_heading / (PI / 4.0)), 8)
	wind_label.text = "Wind travels %s" % COMPASS[sector]
	wind_heading = sim.wind_heading
	wind_arrow.queue_redraw()
	var target: Dictionary = sim.ships.get(2, {})
	if not target.is_empty():
		var target_vessel: Dictionary = Definitions.VESSELS[target["vessel_id"]]
		var reason := " · DEFEATED: %s" % ", ".join(target["defeat_reasons"]) if not target["active"] else ""
		target_label.text = "%s%s\nHull %d/%d · Sails %d/%d\nCrew %d/%d" % [BANNER, reason,
			target["hull"], target_vessel["hull"], target["sails"], target_vessel["sails"],
			target["crew"], target_vessel["crew"]]
	for side in Definitions.SIDES:
		var weapon: Dictionary = ship["weapons"][side]
		var loads: Array = weapon["loads"]
		var ready := loads.filter(func(load): return load == 1.0).size()
		var progress := []
		for i in loads.size():
			var percent := 100 if loads[i] == 1.0 else mini(99, roundi(loads[i] * 100.0))
			progress.append("%d:%d%%" % [i + 1, percent])
		var aim: Dictionary = sim.aim_for(sim.PLAYER_ID, side)
		var aim_label: String = "target %d · assisted" % aim["target_id"] if aim["target_id"] != null else AIM_TEXT[aim["reason"]]
		side_labels[side].text = "%s · %s · %d/%d ready\nGuns %s\nRange %d · %s" % [
			side.capitalize(), Definitions.AMMO[weapon["ammo"]]["display_name"], ready, loads.size(),
			"  ".join(progress.slice(0, 4)) + ("\n          " + "  ".join(progress.slice(4)) if loads.size() > 4 else ""),
			roundi(aim["range"]), aim_label]
		feedback_labels[side].text = "no loaded guns" if _feedback.has(side) else ""
	bindings_label.text = "%s/%s steer · %s sails · %s pause\n%s fire Port · %s fire Starboard · %s cycle Port · %s cycle Starboard\n%s reset" % [
		Bindings.binding_label("turn_left"), Bindings.binding_label("turn_right"),
		Bindings.binding_label("toggle_sails"), Bindings.binding_label("pause"),
		Bindings.binding_label("fire_port"), Bindings.binding_label("fire_starboard"),
		Bindings.binding_label("cycle_port"), Bindings.binding_label("cycle_starboard"),
		Bindings.binding_label("reset_practice")]


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


func _panel(content: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(content)
	return panel
