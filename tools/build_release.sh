#!/usr/bin/env bash
# Build one release: 3 full builds, 3 packs, update.json.
# Usage (repo root; absolute $GODOT + 4.7.2 templates): bash tools/build_release.sh 0.N <outdir>
set -euo pipefail

V="${1:?usage: build_release.sh 0.N <outdir>}"
[[ "$V" =~ ^0\.[0-9]+$ ]] || { echo "version must be 0.N" >&2; exit 2; }
test -x "${GODOT:?set GODOT}"
mkdir -p "${2:?outdir required}"
OUT="$(cd "$2" && pwd)"
STAGE="$(mktemp -d)"
cp game/version.cfg "$STAGE/version.cfg.committed"
trap 'cp "$STAGE/version.cfg.committed" game/version.cfg; rm -rf "$STAGE"' EXIT

# Base ID: what a pack cannot change (engine, startup files, class_name registry).
BASE="$({
	"$GODOT" --version
	for f in project.godot export_presets.cfg default_bus_layout.tres boot.gd boot.tscn; do
		if [ -f "game/$f" ]; then cat "game/$f"; fi
	done
	grep -rh --include='*.gd' --exclude-dir=.godot '^class_name ' game | LC_ALL=C sort
} | sha256sum | cut -c1-16)"

printf '[build]\nversion="%s"\nbase="%s"\n' "$V" "$BASE" > game/version.cfg
G=("$GODOT" --headless --path game)
"${G[@]}" --import
mkdir -p "$STAGE/windows" "$STAGE/linux"
"${G[@]}" --export-release windows "$STAGE/windows/Tortuga.exe"
"${G[@]}" --export-release linux "$STAGE/linux/Tortuga.x86_64"
"${G[@]}" --export-release macos "$OUT/Tortuga-$V-macos.zip"
for p in windows macos linux; do
	"${G[@]}" --export-pack "$p" "$OUT/tortuga-$V-$p.pck"
done
(cd "$STAGE/windows" && python3 -m zipfile -c "$OUT/Tortuga-$V-windows.zip" Tortuga.exe Tortuga.pck)
tar -czf "$OUT/Tortuga-$V-linux.tar.gz" -C "$STAGE/linux" Tortuga.x86_64 Tortuga.pck

python3 - "$V" "$BASE" "$OUT" <<'PY'
import hashlib, json, sys
v, base, out = sys.argv[1:]
packs = {}
for p in ("windows", "macos", "linux"):
    f = f"tortuga-{v}-{p}.pck"
    with open(f"{out}/{f}", "rb") as s:
        packs[p] = {"file": f, "sha256": hashlib.file_digest(s, "sha256").hexdigest()}
with open(f"{out}/update.json", "w") as s:
    json.dump({"version": v, "base": base, "packs": packs}, s, indent=1)
PY
ls -l "$OUT"
