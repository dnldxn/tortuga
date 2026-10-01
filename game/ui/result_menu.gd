extends Control
## Duel outcome overlay: reason lines plus Replay (default focus) and Return.

signal replay_requested
signal return_requested

const Definitions := preload("res://sim/definitions.gd")
const SelectionMenu := preload("res://ui/selection_menu.gd")
const Presentation := preload("res://view/combat_presentation.gd")

const OUTCOME_TEXT := {"victory": "Victory", "defeat": "Defeat", "draw": "Draw", "escaped": "Escaped"}
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
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	detail_label = Label.new()
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
	for d in sim.result["defeated"]:
		var ship: Dictionary = sim.ships[d["ship_id"]]
		var name: String = Presentation.ship_label(sim, d["ship_id"]) if ship["team"] == 1 else "You"
		if not sim.ships.has(3) and ship["team"] == 1:
			name = Presentation.marker_badge(sim, d["ship_id"])
		if d["reason"] == "sunk":
			lines.append("%s (%s) sunk." % [name, Definitions.VESSELS[ship["vessel_id"]]["display_name"]])
		else:
			var cause := " and ".join(PackedStringArray(d["disabled_by"]))
			lines.append("%s (%s) disabled: %s exhausted." % [name, Definitions.VESSELS[ship["vessel_id"]]["display_name"], cause])
	if sim.ships.has(3):
		for id in [2, 3]:
			if sim.ships[id]["active"]:
				lines.append("%s (Sloop) Active." % Presentation.ship_label(sim, id))
	detail_label.text = "\n".join(lines)
	visible = true
	replay_button.grab_focus()


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 48)
	return button
