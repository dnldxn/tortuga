# Plan 06 settings — evidence

- Build: base commit `0e7444a` plus the plan 06 working tree (see the commit that adds this file).
- Engine: Godot 4.7.2.stable.official.ed1daf0bf.
- OS: Linux 7.2.4-200.fc44.x86_64.
- Display server: headless (no X11/Wayland/Xvfb on this host).
- Keyboard layout: n/a in headless runs. Tests and probes use synthetic logical keycodes (`InputEventKey.keycode`; `physical_keycode` 0).
- Client size: n/a in headless runs.
- Data path: isolated `/tmp/opencode/tortuga-settings.XXXXXX/data/godot/app_userdata/Tortuga`. It is created by `game/tests/run_settings_checks.sh` and removed by its EXIT trap; the real player profile is never touched.
- Command: `bash game/tests/run_settings_checks.sh` (exit 0). The runbook and command migration are in [`docs/phase-2/settings-demo.md`](../../../phase-2/settings-demo.md).

## Headless / automated

| Check | Expected | Actual | Result |
|---|---|---|---|
| [Guard rejection](../../../../game/tests/run_settings_checks.sh) (`TORTUGA_TEST_ROOT` unset, then mismatched) | exit 1, isolation message, no suites, sentinel sha256 unchanged | `Guard rejection: OK` | Pass |
| [Full registered suite](../../../../game/tests/run_tests.gd), incl. [`test_settings.gd`](../../../../game/tests/test_settings.gd) and [`test_settings_ui.gd`](../../../../game/tests/test_settings_ui.gd) | 0 failures | 2908 checks, 0 failures | Pass |
| `--self-test-failure` | exit 1, probes not run | 2909 checks, 1 failure, exit 1 | Pass |
| [Probe](../../../../game/tests/settings_process_probe.gd) `write`: J/60/25/0/fullscreen saved; sections exactly meta/bindings/audio/display; keys exactly version / 8 actions / master,effects,ambient / mode | 0 failures | 7 checks, 0 failures | Pass |
| Probe `read` (new process): load OK, values exact, notice ""; turn_left = one logical J event; Master −4.437 dB, Effects −12.041 dB (±0.001), Ambient muted; 3 buses; display mode value preserved | 0 failures | 13 checks, 0 failures | Pass |
| Probe `corrupt`: writes `"[audio\nmaster="` | 0 failures | 2 checks, 0 failures | Pass |
| Probe `fallback` (new process): load non-OK; all defaults + `LOAD_NOTICE`; InputMap defaults; pause = Escape; ui_cancel/ui_accept intact; file bytes unchanged | 0 failures | 8 checks, 0 failures | Pass |
| Probe `restore`: `save_values(defaults())` | OK | 1 check, 0 failures | Pass |
| Probe `read-defaults` (new process): original keys, 1 / .8 / .35 → dB, no mutes, windowed | 0 failures | 14 checks, 0 failures | Pass |
| Probe `read` alone against an empty profile | exit 1 (proves a failing mode stops the wrapper) | 13 checks, 8 failures, exit 1 | Pass |
| Probe unknown/no mode; probe without `TORTUGA_TEST_ROOT` | exit 1; no file written when not isolated | exit 1 in each case; no `settings.cfg` written | Pass |
| `--quit-after 30` smoke with toolchain `$P/xdg` exports | exit 0, real profile untouched | exit 0 | Pass |

Headless runs skip the native window mode/size by design (`DisplayServer.get_name() == "headless"`). Only the persisted `display_mode` value is checked.

## Native / real display

| Check | Result |
|---|---|
| Keyboard and mouse remap, pause/focus/resume, relaunch persistence, Defaults round trip, corrupt-file notice | Pending owner real-display verification (unverified) |
| Windowed/fullscreen at 1280×720 and 1920×1080; actual settled size/mode | Pending owner real-display verification (unverified) |

## Later audibility (plan 07) and packages (plan 08)

| Check | Result |
|---|---|
| Effects/Ambient source routing, perceived volume, pause silence | Unverified — no sound sources until plan 07 |
| Packaged Linux/Windows/macOS persistence, input, display, focus | Unverified — plan 08 |
