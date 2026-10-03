extends Control
## Read-only HUD: stable equal roster cards and compact navigation/ammo panels.
## Help text lives in the pause menu.
## Feedback ages in physics ticks.

const Definitions := preload("res://sim/definitions.gd")
const NavalSimulation := preload("res://sim/naval_simulation.gd")
const Presentation := preload("res://view/combat_presentation.gd")
const Bindings := preload("res://input_bindings.gd")

const COMPASS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const STATS := ["hull", "sails", "crew"]
const MARGIN: int = Definitions.PRESENTATION.ui_margin
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
var panels := []  # roster cards, navigation panel, port and starboard panels, allies card
var ship_stats := {}  # stat -> [ProgressBar, Label]
var target_stats := {}
var second_target_block: VBoxContainer
var second_target_label: Label
var second_target_state_label: Label
var second_target_stats := {}
var third_target_label: Label  # only with 3 opponents: card 1 becomes three one-line rows
var _enemy_detail_rows := []  # card 1 stat rows and state, hidden while it lists 3 opponents
var defeated_notice: Label
var side_labels := {}  # side -> header Label
var ammo_labels := {}
var feedback_labels := {}
var _last_ammo := {}
var _ammo_notice := {}  # side -> ticks remaining after a real ammo change
var crew_notice: Label
var _feedback := {}  # side -> remaining physics ticks
var escape_panel: PanelContainer
var banner_label: Label  # first line of the escape panel: shared-battle status (waiting, watching)
var _motion_row: HBoxContainer
var escape_rule_label: Label
var escape_status_label: Label
var escape_bar: ProgressBar
var _escape_prev_ticks := 0  # UI-local, only to notice a progress reset
var _escape_reset_notice := false


var roster_row: HBoxContainer
var roster_cards := {}  # card slot (1 own ship, 2/3 first/second opposition) -> card parts
var player_state_label: Label
var ally_panel: PanelContainer  # last roster card (panels[6]); shown with an ally row or the notice
var ally_labels := []  # 3 slot-colored rows, hidden when unused
var ally_notice: Label
var _ally_notice_ticks := 0
var main: Node  # set by main before _ready; supplies own_ship_id and captains

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	roster_row = HBoxContainer.new()
	roster_row.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	roster_row.offset_left = MARGIN
	roster_row.offset_right = -MARGIN
	roster_row.offset_top = MARGIN
	roster_row.add_theme_constant_override("separation", 12)
	add_child(roster_row)
	for id in [1, 2, 3]:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = SIZE_EXPAND_FILL
		roster_row.add_child(panel)
		panels.append(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		panel.add_child(box)
		var title := _label(box)
		title.theme_type_variation = "NauticalHeading"
		title.add_theme_font_size_override("font_size", 20)
		var stats := {}
		for stat in STATS:
			stats[stat] = _stat_row(box, stat)
		var state := _label(box)
		roster_cards[id] = {"panel": panel, "title": title, "stats": stats, "state": state}
	name_label = roster_cards[1].title
	ship_stats = roster_cards[1].stats
	player_state_label = roster_cards[1].state
	target_label = roster_cards[2].title
	target_stats = roster_cards[2].stats
	target_state_label = roster_cards[2].state
	second_target_block = roster_cards[3].title.get_parent()
	second_target_label = roster_cards[3].title
	second_target_stats = roster_cards[3].stats
	second_target_state_label = roster_cards[3].state
	third_target_label = _label(target_label.get_parent())
	third_target_label.theme_type_variation = "NauticalHeading"
	third_target_label.add_theme_font_size_override("font_size", 16)
	third_target_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	third_target_label.get_parent().move_child(third_target_label, 1)
	third_target_label.hide()
	for stat in STATS:
		_enemy_detail_rows.append(target_stats[stat][0].get_parent())
	_enemy_detail_rows.append(target_state_label)
	var navigation := _corner(PRESET_BOTTOM_LEFT)
	banner_label = _label(navigation)
	banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_label.custom_minimum_size.x = 420
	banner_label.hide()
	var motion := _row(navigation)
	_motion_row = motion
	_icon(motion, "speed")
	speed_label = _label(motion)
	wind_arrow = Control.new()
	wind_arrow.name = "WindArrow"
	wind_arrow.custom_minimum_size = Vector2(32, 32)
	wind_arrow.draw.connect(_draw_wind_arrow)
	motion.add_child(wind_arrow)
	wind_label = _label(motion)
	crew_notice = _label(navigation)
	crew_notice.hide()
	defeated_notice = _label(navigation)
	defeated_notice.hide()
	escape_panel = navigation.get_parent()
	escape_rule_label = _label(navigation)
	escape_status_label = _label(navigation)
	for label in [escape_rule_label, escape_status_label]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 420
		label.add_theme_font_size_override("font_size", 18)
	escape_bar = _bar(navigation, Vector2(420, 10))
	var sides := HBoxContainer.new()
	sides.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	sides.grow_horizontal = GROW_DIRECTION_BEGIN
	sides.grow_vertical = GROW_DIRECTION_BEGIN
	sides.offset_right = -MARGIN
	sides.offset_bottom = -MARGIN
	sides.add_theme_constant_override("separation", 12)
	add_child(sides)
	for side in Definitions.SIDES:
		var panel := PanelContainer.new()
		sides.add_child(panel)
		panels.append(panel)
		var box := VBoxContainer.new()
		panel.add_child(box)
		var header := _row(box)
		_icon(header, "cannon")
		side_labels[side] = _label(header)
		ammo_labels[side] = _label(box)
		ammo_labels[side].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ammo_labels[side].custom_minimum_size.x = 330
		feedback_labels[side] = _label(box)
		feedback_labels[side].visible = false
	ally_panel = PanelContainer.new()
	ally_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	ally_panel.hide()
	roster_row.add_child(ally_panel)
	panels.append(ally_panel)
	var allies := VBoxContainer.new()
	allies.add_theme_constant_override("separation", 2)
	ally_panel.add_child(allies)
	for i in 4:
		var row := _label(allies)
		row.add_theme_font_size_override("font_size", 16)
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.hide()
		ally_labels.append(row)
	ally_notice = ally_labels.pop_back()  # the fourth line is the notice


func reset_effects() -> void:
	_feedback.clear()
	_last_ammo.clear()
	_ammo_notice.clear()
	_escape_prev_ticks = 0
	_escape_reset_notice = false
	_ally_notice_ticks = 0
	for label in feedback_labels.values():
		label.text = ""
		label.visible = false


func consume_events(events: Array) -> void:
	for event in events:
		if event["type"] == "empty" and event["ship_id"] == main.own_ship_id:
			_feedback[event["side"]] = 48
		elif event["type"] == "volley" and event["ship_id"] == main.own_ship_id:
			_feedback.erase(event["side"])
		elif event["type"] == "hit" and event["owner_id"] == main.own_ship_id \
				and event["target_id"] != main.own_ship_id and main.captains.has(event["target_id"]):
			ally_notice.text = "hit ally %s!" % Presentation.short_name(main.captains[event["target_id"]]["name"])
			_ally_notice_ticks = 90


func advance_effects() -> void:
	for side in _feedback.keys():
		_feedback[side] -= 1
		if _feedback[side] <= 0:
			_feedback.erase(side)
	for side in _ammo_notice.keys():
		_ammo_notice[side] -= 1
		if _ammo_notice[side] <= 0:
			_ammo_notice.erase(side)
	_ally_notice_ticks = maxi(_ally_notice_ticks - 1, 0)


func refresh(sim) -> void:
	var own_id: int = main.own_ship_id
	var ship: Dictionary = sim.ships.get(own_id, {})
	# No own ship yet (a shared battle before its first snapshot): only the banner and allies.
	var waiting := ship.is_empty()
	banner_label.text = "Waiting for the battle…" if waiting else _defeat_banner(sim)
	banner_label.visible = banner_label.text != ""
	for node in [panels[0], panels[4], panels[5], _motion_row, escape_rule_label]:
		node.visible = not waiting
	if waiting:
		for node in [panels[1], panels[2], escape_status_label, escape_bar]:
			node.visible = false
		_refresh_allies(sim)
		return
	var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
	name_label.text = "%s · %s" % [vessel["display_name"], "REEFED" if ship["reefed"] else "FULL SAILS"]
	var own_captain: Dictionary = main.captains.get(own_id, {}) if sim.battle_mode else {}
	if not own_captain.is_empty():
		name_label.text = "●%d %s · " % [own_captain["slot"] + 1, Presentation.short_name(own_captain["name"])] + name_label.text
	name_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if own_captain.is_empty() else TextServer.OVERRUN_TRIM_ELLIPSIS
	_set_stats(ship_stats, ship, vessel)
	player_state_label.text = _ship_state(ship)
	var opposition: Array = Presentation.opposition_ids(sim)
	var compact := opposition.size() >= 3
	var slots := [own_id] + opposition  # card slot n shows slots[n - 1]
	for slot in roster_cards:
		var id: int = slots[slot - 1] if slot <= slots.size() else -1
		if sim.ships.has(id):
			var lit: bool = sim.ships[id]["active"] or (compact and slot == 2)
			roster_cards[slot].panel.modulate = Color.WHITE if lit else Color(0.72, 0.72, 0.72, 1.0)
	crew_notice.text = "Crew losses slow reload" if ship["crew"] < vessel["crew"] else ""
	speed_label.text = "%d" % roundi(ship["speed"])
	var sector := posmod(roundi(sim.wind_heading / (PI / 4.0)), 8)
	wind_label.text = "Wind %s →" % COMPASS[sector]
	wind_heading = sim.wind_heading
	wind_arrow.queue_redraw()
	var target: Dictionary = sim.ships[opposition[0]] if not opposition.is_empty() else {}
	_set_compact(compact)
	panels[1].visible = not target.is_empty()
	panels[2].visible = opposition.size() == 2
	second_target_block.visible = opposition.size() == 2
	defeated_notice.visible = false
	if opposition.size() < 2:
		second_target_label.text = ""
		second_target_state_label.text = ""
		for stat in STATS:
			second_target_stats[stat][1].text = ""
		defeated_notice.text = ""
	if not target.is_empty():
		var target_vessel: Dictionary = Definitions.VESSELS[target["vessel_id"]]
		target_label.text = "TARGET · Brig" if sim.preset_id == "practice" else Presentation.ship_label(sim, opposition[0], main.captains)
		_set_stats(target_stats, target, target_vessel)
		var distance := roundi(target["position"].distance_to(ship["position"]))
		var state := _ship_state(target)
		target_state_label.text = "%d · %s" % [distance, state]
	if opposition.size() >= 2:
		var rows := [target_label, second_target_label, third_target_label]
		for i in mini(opposition.size(), rows.size()):
			var enemy: Dictionary = sim.ships[opposition[i]]
			rows[i].text = "%s %s" % [Presentation.GLYPHS[Presentation.identity_shape(sim, opposition[i])],
				Presentation.ship_label(sim, opposition[i], main.captains)]
			if compact:
				rows[i].text += " · %s · %d · %s" % [_condition(enemy), roundi(enemy["position"].distance_to(ship["position"])), _ship_state(enemy)]
		if not compact:
			var second: Dictionary = sim.ships[opposition[1]]
			_set_stats(second_target_stats, second, Definitions.VESSELS[second["vessel_id"]])
			var second_state := _ship_state(second)
			second_target_state_label.text = "%d · %s" % [roundi(second["position"].distance_to(ship["position"])), second_state]
		var defeated := opposition.filter(func(id): return not sim.ships[id]["active"]).size()
		defeated_notice.text = "%d of %d enemies defeated" % [defeated, opposition.size()] \
			if sim.result.is_empty() and defeated > 0 and defeated < opposition.size() else ""
	for side in Definitions.SIDES:
		var weapon: Dictionary = ship["weapons"][side]
		var loads: Array = weapon["loads"]
		var ready := loads.filter(func(load): return load == 1.0).size()
		var ammo: Dictionary = Definitions.AMMO[weapon["ammo"]]
		if _last_ammo.has(side) and _last_ammo[side] != weapon["ammo"]:
			_ammo_notice[side] = 48
		_last_ammo[side] = weapon["ammo"]
		side_labels[side].text = "%s · %s · %d/%d ready" % [side.capitalize(), ammo["display_name"], ready, loads.size()]
		ammo_labels[side].text = "%s fire · %s cycle | → %s" % [
			Bindings.binding_label("fire_" + side), Bindings.binding_label("cycle_" + side),
			ammo["track"].capitalize()]
		if _ammo_notice.has(side):
			ammo_labels[side].text += " · LOAD RESET"
		feedback_labels[side].text = "no loaded guns" if _feedback.has(side) else ""
		feedback_labels[side].visible = _feedback.has(side)
	_refresh_escape(sim, ship)
	_refresh_allies(sim)


## A defeated captain behind no panel: who they watch and how to switch, or how to leave.
func _defeat_banner(sim) -> String:
	if main.mode != "battle" or main.own_outcome == "" or main.battle_menu.defeat_open:
		return ""
	var keys := "%s/%s" % [Bindings.binding_label("turn_left"), Bindings.binding_label("turn_right")]
	if main.focus_ship_id() != main.own_ship_id:
		return "Watching %s · %s switch ally" % [Presentation.ship_label(sim, main.focus_ship_id(), main.captains), keys]
	if main._live_allies().is_empty():
		return "No allies left to watch · %s menu → Leave battle" % Bindings.binding_label("pause")
	return "%s watch an ally" % keys


## One row per other captain still in the battle; the card also carries the hit-ally notice.
func _refresh_allies(sim) -> void:
	var allies: Array = Presentation.ally_ids(sim, main.captains, main.own_ship_id)
	for i in ally_labels.size():
		var row: Label = ally_labels[i]
		row.visible = i < allies.size()
		if row.visible:
			row.text = ally_row(sim, allies[i])
			var color := Presentation.slot_color(main.captains[allies[i]]["slot"])
			if row.get_theme_color("font_color") != color:
				row.add_theme_color_override("font_color", color)
	ally_notice.visible = _ally_notice_ticks > 0
	ally_panel.visible = not allies.is_empty() or ally_notice.visible


func ally_row(sim, id: int) -> String:
	var captain: Dictionary = main.captains[id]
	var ally: Dictionary = sim.ships[id]
	var text := "●%d %s %s" % [captain["slot"] + 1, Presentation.short_name(captain["name"]), Presentation.condition_short(ally)]
	if not ally["active"]:
		return text + (" · SUNK" if "sunk" in ally["defeat_reasons"] else " · DISABLED")
	return text + (" · AWAY" if ally["lingering"] else "")


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
	var ticks: int = ship["escape_clear_ticks"] if sim.battle_mode else sim.escape_clear_ticks
	if not sim.result.is_empty():
		_escape_reset_notice = false
	elif ticks == 0 and _escape_prev_ticks > 0:
		_escape_reset_notice = true
	elif ticks > 0:
		_escape_reset_notice = false
	_escape_prev_ticks = ticks
	if not (ship["escape_armed"] if sim.battle_mode else sim.escape_armed):
		escape_rule_label.text = "Escape unarmed: close to within %d of an enemy." % arm
		escape_status_label.text = distance_text[0].to_upper() + distance_text.substr(1)
		return
	escape_rule_label.text = "Escape: farther than %d from EVERY enemy for %s s." % [clear, Definitions.ESCAPE_SECONDS]
	var seconds := ticks * Definitions.ESCAPE_SECONDS / NavalSimulation.escape_ticks_required(1.0 / 60.0)
	if ticks > 0:
		escape_status_label.text = "Breaking pursuit: %.1f / %.1f s — %s" % [
			minf(seconds, Definitions.ESCAPE_SECONDS), Definitions.ESCAPE_SECONDS, distance_text]
		escape_bar.visible = true
		escape_bar.value = clampf(seconds / Definitions.ESCAPE_SECONDS, 0.0, 1.0) * 100.0
	elif _escape_reset_notice:
		escape_status_label.text = "Pursuit resumed — progress reset. (%s)" % distance_text
	else:
		escape_status_label.text = "Get clear of every enemy — %s" % distance_text


## Card 1 lists three opponents (one 16 px line each) or shows one opponent's details.
func _set_compact(compact: bool) -> void:
	if compact == third_target_label.visible:
		return
	var box: Node = target_label.get_parent() if compact else second_target_block
	if second_target_label.get_parent() != box:
		second_target_label.reparent(box, false)
		box.move_child(second_target_label, 1 if compact else 0)
	third_target_label.visible = compact
	for row in _enemy_detail_rows:
		row.visible = not compact
	for label in [target_label, second_target_label]:
		label.add_theme_font_size_override("font_size", 16 if compact else 20)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if compact else TextServer.OVERRUN_NO_TRIMMING


## Hull/sails/crew as rounded percentages of the vessel maximum.
func _condition(ship: Dictionary) -> String:
	var vessel: Dictionary = Definitions.VESSELS[ship["vessel_id"]]
	return "H%d S%d C%d" % STATS.map(func(stat): return roundi(100.0 * ship[stat] / vessel[stat]))


func _ship_state(ship: Dictionary) -> String:
	return "Active" if ship["active"] else ("SUNK" if "sunk" in ship["defeat_reasons"] else "DISABLED · " + " · ".join(ship["defeat_reasons"]).to_upper())


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


func _stat_row(parent: Node, stat: String, compact := false) -> Array:
	var row := _row(parent)
	if compact:
		var title := _label(row)
		title.text = stat.capitalize()
		title.add_theme_font_size_override("font_size", 16)
	else:
		_icon(row, stat)
		_label(row).text = stat.capitalize()
	var bar := _bar(row, Vector2(40 if compact else 60, 12))
	bar.size_flags_horizontal = SIZE_EXPAND_FILL
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
