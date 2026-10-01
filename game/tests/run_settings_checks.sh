#!/usr/bin/env bash
# Full test suite with isolated user data (never the real player profile).
# Usage (repo root, GODOT exported as an absolute path): bash game/tests/run_settings_checks.sh [--self-test-failure]
set -euo pipefail

test -n "${GODOT:-}" && test -x "$GODOT"
case "$GODOT" in /*) ;; *) exit 1 ;; esac
ls /tmp/opencode > /dev/null
TEST_ROOT="$(mktemp -d /tmp/opencode/tortuga-settings.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

# Guard rejection: own fresh XDG dirs, TORTUGA_TEST_ROOT unset or mismatched -> exit 1,
# actionable message, no suites, sentinel settings file untouched.
GUARD="$TEST_ROOT/guard"
SENTINEL="$GUARD/data/godot/app_userdata/Tortuga/settings.cfg"
mkdir -p "$(dirname "$SENTINEL")" "$GUARD/config" "$GUARD/cache"
printf '[meta]\nversion=1\n' > "$SENTINEL"
SENTINEL_SUM="$(sha256sum "$SENTINEL")"
for root in "" "$TEST_ROOT/elsewhere"; do
	status=0
	out="$(env -u TORTUGA_TEST_ROOT ${root:+TORTUGA_TEST_ROOT="$root"} \
		XDG_DATA_HOME="$GUARD/data" XDG_CONFIG_HOME="$GUARD/config" XDG_CACHE_HOME="$GUARD/cache" \
		"$GODOT" --headless --path game --script res://tests/run_tests.gd 2>&1)" || status=$?
	if [ "$status" -ne 1 ] || ! grep -qF "Settings tests require isolated user data. Run: bash game/tests/run_settings_checks.sh" <<< "$out" \
		|| grep -q "^Suite:" <<< "$out" || [ "$(sha256sum "$SENTINEL")" != "$SENTINEL_SUM" ]; then
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
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --script res://tests/run_tests.gd -- "$@"

# Separate processes sharing the isolated profile; set -e stops at the first failing mode.
for mode in write read corrupt fallback restore read-defaults; do
	"$GODOT" --headless --path game \
		--script res://tests/settings_process_probe.gd -- "$mode"
done
echo "Settings process probes: OK"
