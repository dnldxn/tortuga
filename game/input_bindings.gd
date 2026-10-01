extends RefCounted
## Central gameplay action catalog (logical keys). Built-in ui_* navigation stays separate.
## fire_*/cycle_*/reset_practice are handled by main.gd as one-shot press edges (plan 02).
## Remapping (plan 06) changes only the eight gameplay actions; pause and ui_* stay fixed.

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

const ACTION_NAMES := {
	"turn_left": "Turn left",
	"turn_right": "Turn right",
	"toggle_sails": "Toggle sails",
	"fire_port": "Fire port",
	"fire_starboard": "Fire starboard",
	"cycle_port": "Cycle port",
	"cycle_starboard": "Cycle starboard",
	"reset_practice": "Reset practice",
}

const RESERVED_MESSAGE := "Reserved for menus — choose another key"
const UNSUPPORTED_MESSAGE := "Unsupported key — choose a letter, number, F-key or punctuation"
const SINGLE_KEY_MESSAGE := "Use a single key without modifiers"

## Menu/navigation/modifier keys that gameplay may never take.
const RESERVED := [
	KEY_ESCAPE, KEY_TAB, KEY_BACKTAB, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE,
	KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN,
	KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK,
]
const PUNCTUATION := [
	KEY_MINUS, KEY_EQUAL, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_BACKSLASH, KEY_SEMICOLON,
	KEY_APOSTROPHE, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_QUOTELEFT,
]


## Idempotent: only fills actions that are missing or have no events.
static func install_defaults() -> void:
	for action in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var event := InputEventKey.new()
			event.keycode = DEFAULTS[action]
			InputMap.action_add_event(action, event)


## Fresh copy of the original eight gameplay keycodes (never the live InputMap; no pause).
static func default_keycodes() -> Dictionary:
	var codes := DEFAULTS.duplicate()
	codes.erase("pause")
	return codes


## Live logical keycode of each gameplay action's first key event (0 when unbound).
static func snapshot_keycodes() -> Dictionary:
	var codes := {}
	for action in default_keycodes():
		codes[action] = 0
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				codes[action] = event.keycode
				break
	return codes


## Why `code` cannot be bound to `action` within `candidate` ("" = allowed, incl. same key).
static func binding_problem(action: String, code: int, candidate: Dictionary) -> String:
	if code <= 0:
		return UNSUPPORTED_MESSAGE
	if code & KEY_MODIFIER_MASK:
		return SINGLE_KEY_MESSAGE
	if code in RESERVED:
		return RESERVED_MESSAGE
	var supported := (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9) \
		or (code >= KEY_F1 and code <= KEY_F12) or code in PUNCTUATION
	if not supported:
		return UNSUPPORTED_MESSAGE
	for other in ACTION_NAMES:
		if other != action and candidate.get(other) is int and candidate[other] == code:
			return "Already used by %s. Choose another key." % ACTION_NAMES[other]
	return ""


## Complete map of exactly the eight actions, integer codes, each allowed and unique.
static func valid_keycodes(candidate: Variant) -> bool:
	if typeof(candidate) != TYPE_DICTIONARY or candidate.size() != ACTION_NAMES.size():
		return false
	for action in ACTION_NAMES:
		if not candidate.has(action) or typeof(candidate[action]) != TYPE_INT:
			return false
		if binding_problem(action, candidate[action], candidate) != "":
			return false
	return true


## Replaces the eight gameplay actions with one logical key each; other actions untouched.
static func apply_keycodes(candidate: Dictionary) -> void:
	if not valid_keycodes(candidate):
		push_error("Invalid key bindings; not applied")
		return
	for action in default_keycodes():
		var event := InputEventKey.new()
		event.keycode = candidate[action]
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)


## Display text for a logical keycode (draft labels and live prompts).
static func key_label(code: int) -> String:
	return OS.get_keycode_string(code)


## Prompt text for the action's first live binding.
static func binding_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "?"
	var event: InputEvent = events[0]
	if event is InputEventKey:
		return key_label(event.keycode)
	return event.as_text()
