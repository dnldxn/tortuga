extends Control
## Duel outcome overlay: reason lines plus Replay (default focus) and Return. A shared battle's
## result shows per-captain lines and only "Return to harbor".

signal replay_requested
signal return_requested

const Definitions := preload("res://sim/definitions.gd")
const SelectionMenu := preload("res://ui/selection_menu.gd")
const Presentation := preload("res://view/combat_presentation.gd")

const OUTCOME_TEXT := {"victory": "Victory", "defeat": "Defeat", "draw": "Draw", "escaped": "Escaped", "lost": "Lost"}
const ESCAPE_REASON := "Escaped — you broke pursuit while an opponent remained operational."

var title_label: Label
var detail_label: Label
var replay_button: Button
var return_button: Button


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	title_label = Label.new()
	title_label.theme_type_variation = "NauticalHeading"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size.x = 680
	box.add_child(detail_label)
	replay_button = _button("Replay")
	return_button = _button("Return to selection")
	box.add_child(replay_button)
	box.add_child(return_button)
	panel.add_child(box)
	center.add_child(panel)
	add_child(center)
	SelectionMenu.link_focus([replay_button, return_button])
	replay_button.pressed.connect(replay_requested.emit)
	return_button.pressed.connect(return_requested.emit)


## Fill from the sim's result dictionary; the menu never writes back to the sim.
func show_result(sim) -> void:
	title_label.text = OUTCOME_TEXT[sim.result["outcome"]]
	var lines := ["Time %.1fs" % sim.result["elapsed"]]
	if sim.result["outcome"] == "escaped":
		lines.push_front(ESCAPE_REASON)
	_show(lines + _opposition_lines(sim), true)


## Shared battle: own outcome, time, every other captain's outcome (by ship id), the opposition.
func show_battle_result(sim, own_id: int, captains: Dictionary) -> void:
	var result: Dictionary = sim.result
	title_label.text = OUTCOME_TEXT.get(result.get("outcome"), "Battle over")
	var outcomes: Dictionary = result.get("outcomes", {})
	var seconds := int(result.get("elapsed", 0.0))
	var lines := ["Your ship: %s" % str(outcomes.get(own_id, {}).get("outcome", "")).capitalize(),
		"Time %d:%02d" % [seconds / 60, seconds % 60]]
	var ids: Array = outcomes.keys()
	ids.sort()
	for id in ids:
		if id != own_id:
			lines.append("%s: %s" % [captains.get(id, {}).get("name", "Captain"), str(outcomes[id].get("outcome", "")).capitalize()])
	_show(lines + _opposition_lines(sim), false)


## Defeated opposition (and, with 2+, the still active ones); captain ships have their own lines.
func _opposition_lines(sim) -> Array:
	var lines := []
	var opposition: Array = Presentation.opposition_ids(sim)
	for d in sim.result["defeated"]:
		if not sim.ships.has(d["ship_id"]):
			continue
		var ship: Dictionary = sim.ships[d["ship_id"]]
		var enemy: bool = ship["team"] == sim.TEAM_OPPOSITION
		if sim.battle_mode and not enemy:
			continue
		var name: String = Presentation.ship_label(sim, d["ship_id"]) if enemy else "You"
		if opposition.size() < 2 and enemy:
			name = Presentation.marker_badge(sim, d["ship_id"])
		if d["reason"] == "sunk":
			lines.append("%s (%s) sunk." % [name, Definitions.VESSELS[ship["vessel_id"]]["display_name"]])
		else:
			var cause := " and ".join(PackedStringArray(d["disabled_by"]))
			lines.append("%s (%s) disabled: %s exhausted." % [name, Definitions.VESSELS[ship["vessel_id"]]["display_name"], cause])
	if opposition.size() >= 2:
		for id in opposition:
			if sim.ships[id]["active"]:
				lines.append("%s (%s) Active." % [Presentation.ship_label(sim, id),
					Definitions.VESSELS[sim.ships[id]["vessel_id"]]["display_name"]])
	return lines


## Replay exists only offline; the default focus is Replay there, Return in a shared battle.
func _show(lines: Array, offline: bool) -> void:
	detail_label.text = "\n".join(lines)
	return_button.text = "Return to selection" if offline else "Return to harbor"
	replay_button.visible = offline
	visible = true
	(replay_button if offline else return_button).grab_focus()


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 48)
	return button
