extends SceneTree
## Dependency-free headless test runner.
## Usage: godot --headless --path game --script res://tests/run_tests.gd [-- --self-test-failure]

## Explicit suite registry: add one path per suite. Each script exposes `func run(t) -> bool`
## and returns true at the end, so a suite aborted by a runtime error counts as a failure.
const SUITES: Array[String] = [
	"res://tests/test_sailing.gd",
	"res://tests/test_contact.gd",
	"res://tests/test_controller.gd",
	"res://tests/test_view.gd",
	"res://tests/test_weapons.gd",
	"res://tests/test_projectile_damage.gd",
	"res://tests/test_practice.gd",
]

var checks := 0
var failures := 0
var _started := false


## Suites run on the first frame (not in _initialize) so `root` is inside the tree and
## scenes added by suites receive _ready. They still run synchronously within that frame.
func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	for path in SUITES:
		_run_suite(path)
	if "--self-test-failure" in OS.get_cmdline_user_args():
		check(false, "deliberate self-test failure (--self-test-failure)")
	print("Tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
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
