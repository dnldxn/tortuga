#!/usr/bin/env bash
# Dedicated server smoke: a real --server process, two --bot captains in one battle, a refused
# password, then a graceful stop through the stop file. bash 3.2-safe (macOS) and Linux CI.
# Usage (repo root, GODOT exported as an absolute path): bash game/tests/run_server_smoke.sh
# SMOKE_PORT overrides the UDP port (default 24690).
set -euo pipefail

test -n "${GODOT:-}" && test -x "$GODOT"
case "$GODOT" in /*) ;; *) echo "GODOT must be an absolute path"; exit 1 ;; esac
cd "$(dirname "$0")/../.."
mkdir -p /tmp/opencode
ROOT="$(mktemp -d /tmp/opencode/tortuga-smoke.XXXXXX)"
PIDS=""
cleanup() {
	for pid in $PIDS; do kill -9 "$pid" 2> /dev/null || true; done
	rm -rf -- "$ROOT"
}
trap cleanup EXIT

# Isolated user data: user:// follows HOME on macOS, XDG_DATA_HOME on Linux.
export HOME="$ROOT/home" XDG_DATA_HOME="$ROOT/data" XDG_CONFIG_HOME="$ROOT/config" XDG_CACHE_HOME="$ROOT/cache"
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
unset TORTUGA_SERVER_PASSWORD TORTUGA_SERVER_PORT
PORT="${SMOKE_PORT:-24690}"
G=("$GODOT" --headless --path game)
BOT=(-- --bot --host 127.0.0.1 --port "$PORT" --password smoke)

fail() { echo "Server smoke: FAIL: $1"; [ -z "${2:-}" ] || { echo "--- $2"; cat "$2"; }; exit 1; }
# wait_for FILE PATTERN SECONDS: until FILE contains the fixed string PATTERN.
wait_for() {
	local n=0
	while ! grep -qF -- "$2" "$1" 2> /dev/null; do
		n=$((n + 1))
		[ "$n" -le $(($3 * 10)) ] || fail "no '$2' within $3 s" "$1"
		sleep 0.1
	done
}
# wait_exit PID SECONDS LOG: until PID has exited; its exit status goes to STATUS.
wait_exit() {
	local n=0
	while kill -0 "$1" 2> /dev/null; do
		n=$((n + 1))
		[ "$n" -le $(($2 * 10)) ] || fail "pid $1 still running after $2 s" "$3"
		sleep 0.1
	done
	STATUS=0
	wait "$1" || STATUS=$?
}
# expect FILE ERE: FILE has a line matching the extended regex.
expect() { grep -qE -- "$2" "$1" || fail "no line matching '$2'" "$1"; }
# run_bounded SECONDS LOG ARGS...: foreground run, killed after SECONDS; exit status in STATUS.
run_bounded() {
	local secs="$1" log="$2"
	shift 2
	STATUS=0
	perl -e 'alarm shift; exec @ARGV' "$secs" "$@" > "$log" 2>&1 || STATUS=$?
}

"$GODOT" --headless --path game --import > "$ROOT/import.log" 2>&1 || fail "import" "$ROOT/import.log"

# 1. No password: refused at startup.
run_bounded 30 "$ROOT/nopw.log" "${G[@]}" -- --server --port "$PORT"
[ "$STATUS" = 2 ] || fail "server without password exited $STATUS (want 2)" "$ROOT/nopw.log"
expect "$ROOT/nopw.log" "^SRV error password required"

# 2. Server.
"${G[@]}" -- --server --port "$PORT" --password smoke --stop-file "$ROOT/stop" > "$ROOT/server.log" 2>&1 &
SRV=$!
PIDS="$PIDS $SRV"
wait_for "$ROOT/server.log" "SRV listening port=$PORT version=dev" 30

# 3-4. Anne starts a brig duel, Bonny joins it.
"${G[@]}" "${BOT[@]}" --name Anne --captain-id smoke-anne --preset duel_brig --vessel brig --seconds 60 \
	> "$ROOT/anne.log" 2>&1 &
ANNE=$!
PIDS="$PIDS $ANNE"
wait_for "$ROOT/anne.log" "BOT joined battle=1 " 30
"${G[@]}" "${BOT[@]}" --name Bonny --captain-id smoke-bonny --preset duel_brig --join --vessel sloop --seconds 60 \
	> "$ROOT/bonny.log" 2>&1 &
BONNY=$!
PIDS="$PIDS $BONNY"
wait_for "$ROOT/bonny.log" "BOT joined battle=1 " 30

# 5. Wrong password: refused, exit 1, exactly one summary.
run_bounded 30 "$ROOT/wrong.log" "${G[@]}" -- --bot --host 127.0.0.1 --port "$PORT" --password wrong \
	--name Wrong --captain-id smoke-wrong
[ "$STATUS" = 1 ] || fail "wrong-password bot exited $STATUS (want 1)" "$ROOT/wrong.log"
expect "$ROOT/wrong.log" "^BOT refused auth reason=wrong_password "
[ "$(grep -c '^BOT summary ' "$ROOT/wrong.log")" = 1 ] || fail "wrong-password bot: not exactly one summary" "$ROOT/wrong.log"

# 6. Resource use with two captains in a battle (recorded, no threshold).
sleep 3
echo "Server CPU% / RSS KiB: $(ps -o %cpu=,rss= -p "$SRV")"

# 7. Graceful stop through the stop file.
touch "$ROOT/stop"
wait_exit "$SRV" 10 "$ROOT/server.log"
[ "$STATUS" = 0 ] || fail "server exited $STATUS (want 0)" "$ROOT/server.log"
for who in anne bonny; do
	pid=$ANNE
	[ "$who" = anne ] || pid=$BONNY
	wait_exit "$pid" 10 "$ROOT/$who.log"
	[ "$STATUS" = 0 ] || fail "$who exited $STATUS (want 0)" "$ROOT/$who.log"
done
PIDS=""

# 8. Logs.
for pattern in "^SRV auth accept " "^SRV join captain=Anne " "^SRV join captain=Bonny " \
		"^SRV auth refuse .*reason=wrong_password" "^SRV battle start id=1 preset=duel_brig " \
		"^SRV battle join id=1 " "^SRV stopping reason=stop-file" "^SRV stopped "; do
	expect "$ROOT/server.log" "$pattern"
done
for who in anne bonny; do
	log="$ROOT/$who.log"
	expect "$log" "^BOT ended reason=server_stopped$"
	[ "$(grep -c '^BOT summary ' "$log")" = 1 ] || fail "$who: not exactly one summary" "$log"
	expect "$log" "^BOT summary .* exit=0 "
	snapshots=$(sed -n 's/^BOT summary .* snapshots=\([0-9]*\) .*/\1/p' "$log")
	[ "${snapshots:-0}" -ge 20 ] || fail "$who: snapshots=${snapshots:-?} (want >= 20)" "$log"
	grep '^BOT summary ' "$log"
done
grep '^SRV stopped ' "$ROOT/server.log"
echo "Server smoke: OK"
