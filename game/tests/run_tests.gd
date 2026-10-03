extends SceneTree
## Dependency-free headless test runner.
## Usage: bash game/tests/run_settings_checks.sh [--self-test-failure]
## (wraps godot --headless --path game --script res://tests/run_tests.gd with isolated user data)

## Explicit suite registry: add one path per suite. Each script exposes `func run(t) -> bool`
## and returns true at the end, so a suite aborted by a runtime error counts as a failure.
const SUITES: Array[String] = [
	"res://tests/test_combat_effects.gd",
	"res://tests/test_sailing.gd",
	"res://tests/test_contact.gd",
	"res://tests/test_controller.gd",
	"res://tests/test_view.gd",
	"res://tests/test_water.gd",
	"res://tests/test_weapons.gd",
	"res://tests/test_projectile_damage.gd",
	"res://tests/test_practice.gd",
	"res://tests/test_ai_duels.gd",
	"res://tests/test_duel_ui.gd",
	"res://tests/test_escape.gd",
	"res://tests/test_two_opponent.gd",
	"res://tests/test_combat_roster.gd",
	"res://tests/test_two_opponent_escape.gd",
	"res://tests/test_settings.gd",
	"res://tests/test_settings_ui.gd",
	"res://tests/test_presentation.gd",
	"res://tests/test_hud_layout.gd",
	"res://tests/test_muzzle_mapping.gd",
	"res://tests/test_battle_mode.gd",
	"res://tests/test_ai_targeting.gd",
	"res://tests/test_protocol.gd",
	"res://tests/test_battle.gd",
	"res://tests/test_session.gd",
	"res://tests/test_updater.gd",  # keep last: loaded packs persist and switch res:// to pack DirAccess
]

const ISOLATION_MESSAGE := "Settings tests require isolated user data. Run: bash game/tests/run_settings_checks.sh"

var checks := 0
var failures := 0
var _started := false
var _cleanup_frames := 10


## True only when user:// lives under a nonempty absolute $TORTUGA_TEST_ROOT, so tests can never
## read or write the real player profile. Shared with tests/settings_process_probe.gd.
static func isolated_user_data_ok() -> bool:
	var root := OS.get_environment("TORTUGA_TEST_ROOT").simplify_path()
	if root.is_empty() or not root.is_absolute_path():
		return false
	return OS.get_user_data_dir().simplify_path().begins_with(root + "/")


func _initialize() -> void:
	if not isolated_user_data_ok():
		_started = true
		print(ISOLATION_MESSAGE)
		quit(1)


## Suites run on the first frame (not in _initialize) so `root` is inside the tree and
## scenes added by suites receive _ready. They still run synchronously within that frame.
func _process(_delta: float) -> bool:
	if _started:
		_cleanup_frames -= 1
		if _cleanup_frames == 0:
			quit(1 if failures > 0 else 0)
		return false
	_started = true
	for path in SUITES:
		_run_suite(path)
	if "--self-test-failure" in OS.get_cmdline_user_args():
		check(false, "deliberate self-test failure (--self-test-failure)")
	# A stray update_and_restart would quit(0) at once and relaunch Godot; fail and cancel the restart.
	check(not OS.is_restart_on_exit_set(), "no suite scheduled a restart")
	OS.set_restart_on_exit(false)
	print("Tests: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)  # immediately: a quit(0) already requested this frame is overridden
	# Let stopped WAV playbacks drain before the headless audio server shuts down.
	return false


func _run_suite(path: String) -> void:
	print("Suite: %s" % path)
	var script: GDScript = load(path) if ResourceLoader.exists(path) else null
	if script == null or not script.can_instantiate():
		check(false, "suite loads: %s" % path)
		return
	var before := checks
	# A runtime error aborts run() silently and yields null; suites must return true on completion.
	var completed = script.new().run(self)
	check(completed == true and checks > before, "suite completed: %s" % path)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("  FAIL: %s" % label)


func near(actual: float, expected: float, epsilon: float, label: String) -> void:
	check(absf(actual - expected) <= epsilon, "%s (actual %s, expected %s ±%s)" % [label, actual, expected, epsilon])
