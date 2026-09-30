extends RefCounted
## Central gameplay action catalog (logical keys). Built-in ui_* navigation stays separate.
## fire_*/cycle_*/reset_practice are reserved: no handler or prompt until plan 02.
## ponytail: defaults only; plan 06 adds remapping/persistence.

const DEFAULTS := {
	"turn_left": KEY_A,
	"turn_right": KEY_D,
	"toggle_sails": KEY_W,
	"fire_port": KEY_Q,
	"fire_starboard": KEY_E,
	"cycle_port": KEY_Z,
	"cycle_starboard": KEY_C,
	"reset_practice": KEY_R,
	"pause": KEY_ESCAPE,
}


## Idempotent: only fills actions that are missing or have no events.
static func install_defaults() -> void:
	for action in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var event := InputEventKey.new()
			event.keycode = DEFAULTS[action]
			InputMap.action_add_event(action, event)


## Prompt text for the action's first live binding.
static func binding_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "?"
	var event: InputEvent = events[0]
	if event is InputEventKey:
		return OS.get_keycode_string(event.keycode)
	return event.as_text()
