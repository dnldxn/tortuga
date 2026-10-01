extends Control
## Read-only HUD: wind, two fixed-ID enemy rows, player tracks and independent side cards.
## Help text lives in the pause menu.
## Feedback ages in physics ticks.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const Presentation := preload("res://view/combat_presentation.gd")
const Bindings := preload("res://input_bindings.gd")

const COMPASS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
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
var second_target_block: VBoxContainer
var second_target_label: Label
var second_target_state_label: Label
var second_target_stats := {}
var defeated_notice: Label
var side_labels := {}  # side -> header Label
var ammo_labels := {}
var gun_bars := {}  # side -> Array[ProgressBar], prebuilt for the largest vessel
var aim_labels := {}
var aim_icons := {}
var feedback_labels := {}
var _last_ammo := {}
var _ammo_notice := {}  # side -> ticks remaining after a real ammo change
var crew_notice: Label
var practice_notice: Label
var _feedback := {}  # side -> remaining physics ticks
var escape_panel: PanelContainer
var escape_rule_label: Label
var escape_status_label: Label
var escape_bar: ProgressBar
var _escape_prev_ticks := 0  # UI-local, only to notice a progress reset
var _escape_reset_notice := false


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var status := _corner(PRESET_TOP_LEFT)
	name_label = _label(status)
	var player_panel := _corner(PRESET_BOTTOM_LEFT)
	for stat in STATS:
		ship_stats[stat] = _stat_row(player_panel, stat)
	crew_notice = _label(player_panel)
	var motion := _row(status)
	_icon(motion, "speed")
	speed_label = _label(motion)
	wind_arrow = Control.new()
	wind_arrow.name = "WindArrow"
	wind_arrow.custom_minimum_size = Vector2(32, 32)
	wind_arrow.draw.connect(_draw_wind_arrow)
	motion.add_child(wind_arrow)
	wind_label = _label(motion)
	practice_notice = _label(status)
	var target := _corner(PRESET_TOP_RIGHT)
	target_label = _label(target)
	var first_stats := _row(target)
	for stat in STATS:
		target_stats[stat] = _stat_row(first_stats, stat, true)
	var where := _row(target)
	_icon(where, "distance")
	target_state_label = _label(where)
	second_target_block = VBoxContainer.new()
	second_target_block.add_theme_constant_override("separation", 2)
	target.add_child(second_target_block)
	second_target_label = _label(second_target_block)
	var second_stats := _row(second_target_block)
	for stat in STATS:
		second_target_stats[stat] = _stat_row(second_stats, stat, true)
	var second_where := _row(second_target_block)
	_icon(second_where, "distance")
	second_target_state_label = _label(second_where)
	defeated_notice = _label(target)
	var max_guns := 0
	for vessel in Definitions.VESSELS.values():
		max_guns = maxi(max_guns, vessel["guns_per_side"])
	for side in Definitions.SIDES:
		var side_box := _corner(PRESET_BOTTOM_LEFT if side == "port" else PRESET_BOTTOM_RIGHT)
		if side == "port":
			var panel: Control = side_box.get_parent()
			panel.offset_left += 310
			panel.offset_right += 310
		_make_side(side_box, side, max_guns)
	_make_escape()


## Top-centre escape panel (plan 04): rule line, status line and countdown bar.
func _make_escape() -> void:
	escape_panel = PanelContainer.new()
	escape_panel.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(escape_panel)
	escape_panel.set_anchors_and_offsets_preset(PRESET_CENTER_TOP, PRESET_MODE_MINSIZE, MARGIN)
	escape_panel.grow_horizontal = GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	escape_panel.add_child(box)
	escape_rule_label = _label(box)
	escape_status_label = _label(box)
	for label in [escape_rule_label, escape_status_label]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 340  # leaves the two-enemy rows unobstructed at 720p
	escape_bar = _bar(box, Vector2(340, 10))


func _make_side(parent: Node, side: String, max_guns: int) -> void:
	var header := _row(parent)
	_icon(header, "cannon")
	side_labels[side] = _label(header)
	ammo_labels[side] = _label(parent)
	ammo_labels[side].add_theme_font_size_override("font_size", 16)
	var guns := _row(parent)
	guns.add_theme_constant_override("separation", 4)
	gun_bars[side] = []
	for i in max_guns:
		var bar := _bar(guns, Vector2(12, 22))
		bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		var pip := Label.new()
		pip.add_theme_font_size_override("font_size", 16)
		pip.mouse_filter = MOUSE_FILTER_IGNORE
		bar.add_child(pip)
		gun_bars[side].append(bar)
	var aim_row := _row(parent)
	aim_labels[side] = _label(aim_row)
	aim_labels[side].add_theme_font_size_override("font_size", 16)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_aim_icon.bind(side))
	aim_row.add_child(icon)
	aim_icons[side] = icon
	feedback_labels[side] = _label(parent)
	feedback_labels[side].add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	feedback_labels[side].visible = false


func reset_effects() -> void:
	_feedback.clear()
	_last_ammo.clear()
	_ammo_notice.clear()
	_escape_prev_ticks = 0
	_escape_reset_notice = false
	for label in feedback_labels.values():
		label.text = ""
		label.visible = false


func consume_events(events: Array) -> void:
	for event in events:
		if event["type"] == "empty" and event["ship_id"] == 1:
			_feedback[event["side"]] = 48
		elif event["type"] == "volley" and event["ship_id"] == 1:
			_feedback.erase(event["side"])


func advance_effects() -> void:
	for side in _feedback.keys():
		_feedback[side] -= 1
		if _feedback[side] <= 0:
			_feedback.erase(side)
	for side in _ammo_notice.keys():
		_ammo_notice[side] -= 1
		if _ammo_notice[side] <= 0:
			_ammo_notice.erase(side)


func refresh(sim) -> void:
	var ship: Dictionary = sim.ships.get(sim.PLAYER_ID, {})
	if ship.is_empty():
		return
	var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
	name_label.text = "%s · %s" % [vessel["display_name"], "REEFED" if ship["reefed"] else "FULL SAILS"]
	_set_stats(ship_stats, ship, vessel)
	crew_notice.text = "Crew losses slow reload" if ship["crew"] < vessel["crew"] else ""
	speed_label.text = "%d" % roundi(ship["speed"])
	var sector := posmod(roundi(sim.wind_heading / (PI / 4.0)), 8)
	wind_label.text = "Wind %s →" % COMPASS[sector]
	wind_heading = sim.wind_heading
	wind_arrow.queue_redraw()
	practice_notice.text = "Aim assist — shots can miss" if sim.preset_id == "practice" else ""
	var target: Dictionary = sim.ships.get(2, {})
	panels[1].visible = not target.is_empty()
	second_target_block.visible = sim.ships.has(3)
	defeated_notice.visible = false
	if not second_target_block.visible:
		second_target_label.text = ""
		second_target_state_label.text = ""
		for stat in STATS:
			second_target_stats[stat][1].text = ""
		defeated_notice.text = ""
	if not target.is_empty():
		var target_vessel: Dictionary = Definitions.VESSELS[target["vessel_id"]]
		target_label.text = "TARGET · Brig" if sim.preset_id == "practice" else Presentation.ship_label(sim, 2)
		_set_stats(target_stats, target, target_vessel)
		var distance := roundi(target["position"].distance_to(ship["position"]))
		var state := "Active" if target["active"] else ("SUNK" if "sunk" in target["defeat_reasons"] else "DISABLED · " + " · ".join(target["defeat_reasons"]).to_upper())
		target_state_label.text = "%d · %s" % [distance, state]
	if second_target_block.visible:
		var second: Dictionary = sim.ships[3]
		second_target_label.text = "◆ " + Presentation.ship_label(sim, 3)
		target_label.text = "▲ " + Presentation.ship_label(sim, 2)
		_set_stats(second_target_stats, second, Definitions.VESSELS[second["vessel_id"]])
		var second_state := "Active" if second["active"] else ("SUNK" if "sunk" in second["defeat_reasons"] else "DISABLED · " + " · ".join(second["defeat_reasons"]).to_upper())
		second_target_state_label.text = "%d · %s" % [roundi(second["position"].distance_to(ship["position"])), second_state]
		defeated_notice.visible = sim.result.is_empty() and target["active"] != second["active"]
		defeated_notice.text = "1 of 2 enemies defeated" if defeated_notice.visible else ""
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
				bars[i].get_child(0).text = "●" if loads[i] == 1.0 else ("◑" if loads[i] > 0.0 else "○")
		var ammo: Dictionary = Definitions.AMMO[weapon["ammo"]]
		if _last_ammo.has(side) and _last_ammo[side] != weapon["ammo"]:
			_ammo_notice[side] = 48
		_last_ammo[side] = weapon["ammo"]
		var glyph: String = {"round": "●", "chain": "○—○", "grape": "∴"}[weapon["ammo"]]
		side_labels[side].text = "%s · %s · %d/%d ready" % [side.capitalize(), ammo["display_name"], ready, loads.size()]
		ammo_labels[side].text = "%s fire · %s cycle | %s %s → %s" % [
			Bindings.binding_label("fire_" + side), Bindings.binding_label("cycle_" + side),
			glyph, ammo["display_name"], ammo["track"].capitalize()]
		if _ammo_notice.has(side):
			ammo_labels[side].text += " · LOAD RESET"
		var aim: Dictionary = sim.aim_for(sim.PLAYER_ID, side)
		var target_name: String = Presentation.ship_label(sim, aim["target_id"]) if aim["target_id"] != null else ""
		aim_labels[side].text = "Range %d · %s" % [roundi(aim["range"]), Presentation.aim_label(ready, aim["reason"], target_name)]
		aim_icons[side].set_meta("status", "empty" if ready == 0 else aim["reason"])
		aim_icons[side].queue_redraw()
		feedback_labels[side].text = "no loaded guns" if _feedback.has(side) else ""
		feedback_labels[side].visible = _feedback.has(side)
	_refresh_escape(sim, ship)


## Rule/status text is derived from sim state each refresh; rounded numbers are display only.
func _refresh_escape(sim, ship: Dictionary) -> void:
	escape_bar.visible = false
	if sim.preset_id == "practice":
		escape_rule_label.text = "Escape unavailable — reset target or return via Pause."
		escape_status_label.visible = false
		return
	escape_status_label.visible = true
	var nearest := INF
	for id in sim.ships:
		var other: Dictionary = sim.ships[id]
		if other["active"] and other["team"] != ship["team"]:
			nearest = minf(nearest, ship["position"].distance_to(other["position"]))
	var distance_text := "nearest enemy %d" % roundi(nearest) if nearest != INF else "no active enemy"
	var arm := roundi(Definitions.ESCAPE_ARM_DISTANCE)
	var clear := roundi(Definitions.ESCAPE_DISTANCE)
	var ticks: int = sim.escape_clear_ticks
	if not sim.result.is_empty():
		_escape_reset_notice = false
	elif ticks == 0 and _escape_prev_ticks > 0:
		_escape_reset_notice = true
	elif ticks > 0:
		_escape_reset_notice = false
	_escape_prev_ticks = ticks
	if not sim.escape_armed:
		escape_rule_label.text = "Escape unarmed: close to within %d of an active enemy to enable escape." % arm
		escape_status_label.text = distance_text[0].to_upper() + distance_text.substr(1)
		return
	escape_rule_label.text = "Escape armed: stay farther than %d from EVERY active enemy for %s s." % [clear, Definitions.ESCAPE_SECONDS]
	var seconds := ticks * Definitions.ESCAPE_SECONDS / NavalSimulation.escape_ticks_required(1.0 / 60.0)
	if ticks > 0:
		escape_status_label.text = "Breaking pursuit: %.1f / %.1f s — %s" % [
			minf(seconds, Definitions.ESCAPE_SECONDS), Definitions.ESCAPE_SECONDS, distance_text]
		escape_bar.visible = true
		escape_bar.value = clampf(seconds / Definitions.ESCAPE_SECONDS, 0.0, 1.0) * 100.0
	elif _escape_reset_notice:
		escape_status_label.text = "Pursuit resumed — progress reset; escape remains armed. (%s)" % distance_text
	else:
		escape_status_label.text = "Get clear of every enemy — %s" % distance_text


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


func _draw_aim_icon(side: String) -> void:
	var icon: Control = aim_icons[side]
	match icon.get_meta("status", "assisted"):
		"empty", "no_active_enemy":
			icon.draw_arc(Vector2(12, 12), 8, 0, TAU, 24, Color.WHITE, 2)
		"out_of_range":
			for x in [3.0, 21.0]:
				icon.draw_line(Vector2(x, 4), Vector2(x, 20), Color.WHITE, 2)
			icon.draw_line(Vector2(5, 12), Vector2(19, 12), Color.WHITE, 2)
		"outside_arc":
			icon.draw_arc(Vector2(12, 12), 8, -PI * .85, PI * .55, 20, Color.WHITE, 2)
			icon.draw_colored_polygon(PackedVector2Array([Vector2(17, 5), Vector2(23, 7), Vector2(18, 12)]), Color.WHITE)
		"assisted":
			icon.draw_line(Vector2(3, 12), Vector2(21, 12), Color.WHITE, 2)
			icon.draw_line(Vector2(15, 6), Vector2(21, 12), Color.WHITE, 2)
			icon.draw_line(Vector2(15, 18), Vector2(21, 12), Color.WHITE, 2)


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


func _stat_row(parent: Node, stat: String, compact := false) -> Array:
	var row := _row(parent)
	if compact:
		var title := _label(row)
		title.text = stat.capitalize()
		title.add_theme_font_size_override("font_size", 16)
	else:
		_icon(row, stat)
	var bar := _bar(row, Vector2(40 if compact else 96, 12))
	var label := _label(row)
	label.custom_minimum_size.x = 48 if compact else 80
	if compact:
		label.add_theme_font_size_override("font_size", 16)
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
