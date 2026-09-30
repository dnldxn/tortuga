# Phase 2 / Plan 01 — Sailing playground runbook

Plan: https://github.com/dnldxn/tortuga/issues/4 · Spec: https://github.com/dnldxn/tortuga/issues/3

Standalone **Sailing practice** mode: choose a sloop, brig, or frigate, read wind and sail
settings, sail a bounded sea, pause, restart, or return to selection. No target, firing, AI,
combat or outcomes (plan 02 onward).

## Toolchain (Linux x86_64)

Pinned engine: Godot **4.7.2 stable, Compatibility renderer**, stock export templates. No
substitute version. Downloads live outside the repository in a dedicated cache directory.

Download size: editor zip ~78 MB, export templates ~1.28 GB. Check free space for downloads
plus extraction (~2× that) before starting.

First confirm `$HOME/.cache/tortuga-godot-4.7.2` is absent or holds only files from this
setup (it is a dedicated destination).

```bash
set -euo pipefail
command -v gh python3 unzip sha512sum
ls "$HOME/.cache"
df -h "$HOME/.cache"
export P="$HOME/.cache/tortuga-godot-4.7.2"
mkdir -p "$P/downloads" "$P/bin" "$P/unpacked" "$P/xdg/data" "$P/xdg/config" "$P/xdg/cache"
gh release download 4.7.2-stable --repo godotengine/godot-builds \
  --dir "$P/downloads" --skip-existing \
  --pattern 'Godot_v4.7.2-stable_linux.x86_64.zip' \
  --pattern 'Godot_v4.7.2-stable_export_templates.tpz' --pattern 'SHA512-SUMS.txt'
python3 - <<'PY'
import hashlib, os
from pathlib import Path
d = Path(os.environ['P']) / 'downloads'
manifest = {}
for line in (d / 'SHA512-SUMS.txt').read_text().splitlines():
    if line.strip():
        digest, name = line.split(maxsplit=1)
        manifest[name.lstrip('*').removeprefix('./')] = digest.lower()
for name in ['Godot_v4.7.2-stable_linux.x86_64.zip',
             'Godot_v4.7.2-stable_export_templates.tpz']:
    with (d / name).open('rb') as stream:
        actual = hashlib.file_digest(stream, 'sha512').hexdigest()
    if manifest.get(name) != actual:
        raise SystemExit(f'Checksum missing/mismatch: {name}; stop setup')
    print(f'VERIFIED {name} {actual}')
PY
unzip -o "$P/downloads/Godot_v4.7.2-stable_linux.x86_64.zip" -d "$P/bin"
unzip -o "$P/downloads/Godot_v4.7.2-stable_export_templates.tpz" -d "$P/unpacked"
export XDG_DATA_HOME="$P/xdg/data" XDG_CONFIG_HOME="$P/xdg/config" XDG_CACHE_HOME="$P/xdg/cache"
export GODOT="$P/bin/Godot_v4.7.2-stable_linux.x86_64"
chmod u+x "$GODOT"
export TEMPLATE_DIR="$XDG_DATA_HOME/godot/export_templates/4.7.2.stable"
mkdir -p "$TEMPLATE_DIR"
cp -a "$P/unpacked/templates/." "$TEMPLATE_DIR/"
python3 - <<'PY'
import os, subprocess
from pathlib import Path
v = subprocess.check_output([os.environ['GODOT'], '--version'], text=True).strip()
if not v.startswith('4.7.2.stable.'):
    raise SystemExit(f'Unexpected engine: {v}')
t = Path(os.environ['TEMPLATE_DIR'])
if (t / 'version.txt').read_text().strip() != '4.7.2.stable':
    raise SystemExit('Unexpected template version')
for name in ['linux_debug.x86_64', 'linux_release.x86_64',
             'windows_debug_x86_64.exe', 'windows_release_x86_64.exe', 'macos.zip']:
    if not (t / name).is_file() or (t / name).stat().st_size == 0:
        raise SystemExit(f'Missing stock template: {name}')
print('TOOLCHAIN READY:', v)
PY
```

Stop on download, checksum, template-layout or binary-launch failure. Template presence is
not export or native verification; no export presets exist yet (plan 08).

### Restore in each new terminal

```bash
export P="$HOME/.cache/tortuga-godot-4.7.2"
export XDG_DATA_HOME="$P/xdg/data" XDG_CONFIG_HOME="$P/xdg/config" XDG_CACHE_HOME="$P/xdg/cache"
export GODOT="$P/bin/Godot_v4.7.2-stable_linux.x86_64"
```

### Recorded setup, 2026-09-30 (Linux x86_64, headless tty host)

- `"$GODOT" --version` → `4.7.2.stable.official.ed1daf0bf`
- Templates `version.txt` → `4.7.2.stable`; linux debug/release, windows debug/release and
  `macos.zip` present and non-empty.
- SHA-512 verified against the release `SHA512-SUMS.txt`:
  - `Godot_v4.7.2-stable_linux.x86_64.zip`
    `9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65`
  - `Godot_v4.7.2-stable_export_templates.tpz`
    `ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079`
- `--headless --path game --import` and `--quit-after 2` exited 0 with no errors.

## Launch and test (from repo root)

```bash
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --script res://tests/run_tests.gd
"$GODOT" --headless --path game --script res://tests/run_tests.gd -- --self-test-failure  # must exit 1
"$GODOT" --path game --resolution 1280x720   # real display
```

## macOS test build (v0.1)

`game/export_presets.cfg` has a single `macos` preset (universal x86_64+arm64, ad-hoc signed,
**not notarized**, tests excluded); plan 08 owns the full preset set. Build on Linux:

```bash
"$GODOT" --headless --path game --export-release macos ../build/phase-2/macos/Tortuga-v0.1-macos.zip
```

Originally published as GitHub release `v0.1` (private repo). On the Mac:

```bash
gh release download v0.1 --repo dnldxn/tortuga --pattern 'Tortuga-v0.1-macos.zip'
unzip Tortuga-v0.1-macos.zip
xattr -dr com.apple.quarantine Tortuga.app   # un-notarized: otherwise Gatekeeper blocks it
open Tortuga.app      # or: ./Tortuga.app/Contents/MacOS/Tortuga --resolution 1280x720
```

Export verified on Linux (bundle layout, universal Mach-O, pack runs headless). Native Mac
launch and manual play of the **original plan-01 archive**: **passed**, owner-reported
2026-09-30 (see verification record). The owner subsequently requested that release `v0.1`
be replaced with the plan-02 target-practice build; the original archive and tag no longer
represent the current download. See `02-broadside-practice.md` for the replacement's checksum
and pending real-display checks.

Suites are registered explicitly in `game/tests/run_tests.gd` (`SUITES`). Each suite exposes
`func run(t) -> bool` and must `return true`; a suite aborted by a script error counts as a
failure. Suites run on the runner's first frame so scenes added to `root` receive `_ready`.

## Controls (defaults, `game/input_bindings.gd`)

A / D steer · W full sails ↔ reefed · Esc pause/resume. Q/E/Z/C/R are reserved for plan 02
and do nothing yet. Menus: mouse, Tab/arrows, Enter/Space. Losing window focus pauses;
regaining focus does not resume.

## Contracts handed to plan 02

- `sim/definitions.gd`: vessel table (`full_speed`, `turn_rate`, `hull`, `sails`, `crew`,
  `guns_per_side`, `base_reload`, `radius`), `PRESETS`, `safe_bounds`, `wind_multiplier`.
- `sim/naval_simulation.gd`: `reset(preset_id, vessel_id)`, `step(dt, commands)`; commands keyed
  by ship ID (`turn`, `toggle_sails`, `fire_*`, `cycle_*`); state `ships`, `projectiles`,
  `events`, `elapsed`, `result`, `wind_heading`. Step order: toggle → turn → speed → move →
  `resolve_contacts()` → elapsed.
- `main.gd`: modes `selection`/`sailing`/`paused`, `start_practice`, `restart_practice`,
  `return_to_selection` (replaces `sim`), `set_paused`, `advance_tick`; signals
  `practice_started`, `mode_changed`. Views read `main.sim` fresh and never mutate it.

## Verification record, 2026-09-30

Host: Linux x86_64 desktop, headless tty session (no DISPLAY/Wayland, no Xvfb). Observer:
AI agent (automated only). Engine `4.7.2.stable.official.ed1daf0bf`.

| Gate | Result |
|---|---|
| `--import` | exit 0, no errors/warnings (3 SVGs imported) |
| `run_tests.gd` | **698 checks, 0 failures**, exit 0; suites sailing, contact, controller, view all completed; only the 2 expected invalid-ID `ERROR` lines |
| `run_tests.gd -- --self-test-failure` | 699 checks, 1 failure, exit **1** (as required) |
| `--quit-after 30` (real main scene) | exit 0, no errors |
| `git diff --check` | clean |
| `.gitignore` | before: untracked, contents `status.md`, `git hash-object` `16555215c544adb51b30e398b0fa911a54d3c587`, `git status --short` = `?? .gitignore`. After: `status.md` preserved, appended `/game/.godot/`, `/build/phase-2/`; `git check-ignore` matches no source path |
| Network imports in `game/` | none |
| Contact residual penetration (fixtures) | max 0.0049 units (limit 0.01) |

### Real-display manual test — PASSED (macOS, owner-reported 2026-09-30)

Observer: project owner. Build: original GitHub release `v0.1` (`Tortuga-v0.1-macos.zip`, SHA-256
`5d69a9c3840b19f21cb5a601b66d924c373602872545a7b971caf7cc2ec8932f`, commit `4f6edd8`), run
natively on the owner's Mac. The owner reported the manual testing as verified. Individual
observations, exact machine, display resolution and renderer output were not recorded
separately.

- [x] Title/menus readable; keyboard-only flow Sailing practice → Sloop → Start; bow, wind
  arrow, tracks and sail setting identifiable.
- [x] Sail east, turn to ~45° for top speed, then west for the upwind floor; reef (W) shows
  lower speed and tighter turn; compare brig and frigate.
- [x] Approach west shallows and an outer corner; steer away without damage or pinning.
- [x] Pause while steering/toggling, wait 5 s, resume: no time jump or queued action.
- [x] Alt-tab away and back: stays paused until explicit resume (OS focus delivery).
- [x] Restart: same vessel, exact spawn, full tracks/sails. Return, choose another vessel.
- [x] Menu flow with the mouse; readability at 720p/1080p-class windows.
- [x] Owner assessment of sailing clarity and handling.

**Not covered by this slice** (remain plan 08 / Phase 2 gates): native Linux and Windows
real-display runs, the Intel UHD performance-floor benchmark, and newcomer playtests.
