#!/usr/bin/env bash
# Full test suite with isolated user data (never the real player profile).
# Linux: user:// follows XDG_DATA_HOME; macOS: it follows HOME (XDG is ignored). Both are isolated.
# Usage (repo root, GODOT exported as an absolute path): bash game/tests/run_settings_checks.sh [--self-test-failure]
set -euo pipefail

test -n "${GODOT:-}" && test -x "$GODOT"
case "$GODOT" in /*) ;; *) exit 1 ;; esac
ls /tmp/opencode > /dev/null
TEST_ROOT="$(mktemp -d /tmp/opencode/tortuga-settings.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

sum() { if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi; }
# user:// of Tortuga under an isolated root
user_dir() {
	case "$(uname -s)" in
		Darwin) echo "$1/home/Library/Application Support/Godot/app_userdata/Tortuga" ;;
		*) echo "$1/data/godot/app_userdata/Tortuga" ;;
	esac
}

# Guard rejection: own fresh XDG/HOME dirs, TORTUGA_TEST_ROOT unset or mismatched -> exit 1,
# actionable message, no suites, sentinel settings file untouched.
GUARD="$TEST_ROOT/guard"
SENTINEL="$(user_dir "$GUARD")/settings.cfg"
mkdir -p "$(dirname "$SENTINEL")" "$GUARD/home" "$GUARD/data" "$GUARD/config" "$GUARD/cache"
printf '[meta]\nversion=1\n' > "$SENTINEL"
SENTINEL_SUM="$(sum "$SENTINEL")"
for root in "" "$TEST_ROOT/elsewhere"; do
	status=0
	out="$(env -u TORTUGA_TEST_ROOT ${root:+TORTUGA_TEST_ROOT="$root"} \
		HOME="$GUARD/home" XDG_DATA_HOME="$GUARD/data" XDG_CONFIG_HOME="$GUARD/config" XDG_CACHE_HOME="$GUARD/cache" \
		"$GODOT" --headless --path game --script res://tests/run_tests.gd 2>&1)" || status=$?
	if [ "$status" -ne 1 ] || ! grep -qF "Settings tests require isolated user data. Run: bash game/tests/run_settings_checks.sh" <<< "$out" \
		|| grep -q "^Suite:" <<< "$out" || [ "$(sum "$SENTINEL")" != "$SENTINEL_SUM" ]; then
		echo "Guard check failed (TORTUGA_TEST_ROOT='$root', exit $status)"
		echo "$out"
		exit 1
	fi
done
echo "Guard rejection: OK"

export TORTUGA_TEST_ROOT="$TEST_ROOT"
export XDG_DATA_HOME="$TEST_ROOT/data"
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export HOME="$TEST_ROOT/home" # macOS user:// root; inert on Linux
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --script res://tests/run_tests.gd -- "$@"

# Separate processes sharing the isolated profile; set -e stops at the first failing mode.
for mode in write read corrupt fallback restore read-defaults; do
	"$GODOT" --headless --path game \
		--script res://tests/settings_process_probe.gd -- "$mode"
done
echo "Settings process probes: OK"
