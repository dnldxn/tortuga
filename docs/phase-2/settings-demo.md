# Plan 06 — Settings: verification record and demo runbook

Godot 4.7.2 stable, Compatibility renderer. Evidence record: [`docs/research/evidence/phase-2/settings.md`](../research/evidence/phase-2/settings.md).

## Implementation summary

- **`game/settings.gd`** is a `RefCounted` model owned by `main`. At startup it runs `load_settings()` then `apply_values()`. It persists one ConfigFile, `user://settings.cfg`. `load_settings()` only replaces `values` and has no native side effects. `apply_values()` is the only place that touches InputMap, the audio buses and (when not headless) the window.
- **Schema** (only these are written; extra data is dropped on save and ignored on load):
  - `[meta] version=1`
  - `[bindings]` with the eight gameplay actions as logical keycodes: `turn_left`, `turn_right`, `toggle_sails`, `fire_port`, `fire_starboard`, `cycle_port`, `cycle_starboard`, `reset_practice`
  - `[audio] master`, `effects`, `ambient` as finite floats in [0, 1]
  - `[display] mode` = `windowed` | `fullscreen`
- **Defaults:**
  - keys A / D / W / Q / E / Z / C / R
  - Master 1.0, Effects 0.8, Ambient 0.35
  - windowed at 1280×720
  - Escape (`pause`) and the built-in `ui_*` actions are reserved and never remappable.
- **Invalid or unreadable file:** every value falls back to defaults (nothing is partially kept) and `LOAD_NOTICE` (“Settings could not be loaded; defaults are active.”) is shown on the selection menu. The file is **never rewritten** on load. A missing file is a silent first launch.
- **Buses:** `game/default_bus_layout.tres` (Master, Effects, Ambient) is wired through `project.godot` `[audio] buses/default_bus_layout`. A gain of 0 mutes the bus; any other gain sets `linear_to_db(gain)`.
- **`game/ui/settings_menu.gd`** is a draft-edit overlay opened from the selection or pause menu. While it is open, `main` routes every input event to it first: key capture, then Escape = Back. Gameplay sees none.
  - Conflicting and reserved keys are rejected with a status message.
  - Apply saves first and applies only if the save succeeds.
  - Defaults resets only the draft.
  - Back returns to the source menu without resuming or resetting.
- **`game/input_bindings.gd`** gained remapping helpers for the eight actions: validation, apply, snapshot and labels. HUD prompts read the live bindings.
- **Test isolation:**
  - `game/tests/run_tests.gd` refuses to run unless `user://` lives under `$TORTUGA_TEST_ROOT`.
  - `game/tests/run_settings_checks.sh` creates that isolated root under `/tmp/opencode` and checks the guard's rejection path. It then imports, runs the full registered suite, and runs the cross-process probes `game/tests/settings_process_probe.gd` (write → read → corrupt → fallback → restore → read-defaults). Each probe is a separate Godot process sharing the isolated profile.
  - The EXIT trap removes the root.

## Command migration

- **Canonical full-suite command:** `bash game/tests/run_settings_checks.sh` runs the full registered suite plus the settings process probes against isolated user data. `GODOT` must be exported as an absolute path. After plan 06 it supersedes every standalone raw `"$GODOT" --headless --path game --script res://tests/run_tests.gd` command in Plans 01–05 and their derived runbooks:
  - `sailing-playground.md`
  - `02-broadside-practice.md`
  - `03-ai-duels.md`
  - `04-deliberate-escape.md`
  - `two-opponent.md`
  - `reef-glass-integration.md`

  Those records are historical and remain unedited; their commands were valid before plan 06.
- **Raw harness:** invoking `run_tests.gd` directly is now an internal wrapper command. It requires the guarded environment and otherwise exits 1 with `Settings tests require isolated user data. Run: bash game/tests/run_settings_checks.sh`.
- **Plans 07 and 08** must use the wrapper for every full-suite regression gate.
- **Plan 01's intentional failure check** becomes `bash game/tests/run_settings_checks.sh --self-test-failure`. It is run separately and must exit 1. The runner fails, so `set -e` stops the wrapper before the probes.
- **XDG scope:** the wrapper's `XDG_*`/`TORTUGA_TEST_ROOT` exports live only in its child shell. Plan 08's export-template discovery in the parent environment is unchanged.
- **Native package runs** remain separate acceptance checks; the wrapper does not replace them.

## Automated checks (Linux headless)

Run from the repository root with `GODOT=$HOME/.cache/tortuga-godot-4.7.2/bin/Godot_v4.7.2-stable_linux.x86_64`. Host: Linux 7.2.4-200.fc44.x86_64, headless tty, no display.

| Command | Result |
|---|---|
| `"$GODOT" --version` | `4.7.2.stable.official.ed1daf0bf` |
| `bash game/tests/run_settings_checks.sh` | exit 0. Output: `Guard rejection: OK`; **Tests: 2908 checks, 0 failures**; probes write 7/0, read 13/0, corrupt 2/0, fallback 8/0, restore 1/0, read-defaults 14/0 (checks/failures); `Settings process probes: OK` |
| `bash game/tests/run_settings_checks.sh --self-test-failure` | exit 1. Output: `Tests: 2909 checks, 1 failures` (deliberate); probes not run |
| Probe `read` run alone against an empty isolated profile | exit 1 (`Probe read: 13 checks, 8 failures`). Confirms a probe failure fails the step, so `set -e` stops the wrapper |
| Probe with unknown mode `bogus` / no mode | exit 1 (`known mode` failure) |
| Probe `write` with `TORTUGA_TEST_ROOT` unset | exit 1, isolation message, no `settings.cfg` written |
| `"$GODOT" --headless --path game --quit-after 30` (toolchain `$P/xdg` exports) | exit 0. `user://` resolves under `$P/xdg/data/godot/app_userdata/Tortuga`, not the real profile; missing file = silent defaults |
| `ls /tmp/opencode \| grep tortuga-settings` after runs | empty (EXIT trap cleanup) |

Expected `ERROR` lines in the output are deliberate: unknown preset/vessel, invalid bindings/settings rejected, and the ConfigFile parse errors for truncated files. In headless mode the probes verify the persisted `display_mode` value only; the native window mode/size is skipped because `DisplayServer` is headless.

## Own player demo (owner performs on a real display)

No display exists on this Linux host, so **none** of the following has been observed. Use a throwaway profile so the real one is untouched. On Linux, `user://` is `$XDG_DATA_HOME/godot/app_userdata/Tortuga`:

```bash
ls /tmp/opencode
DEMO_ROOT="$(mktemp -d /tmp/opencode/tortuga-settings-demo.XXXXXX)"
export XDG_DATA_HOME="$DEMO_ROOT/data"
mkdir -p "$XDG_DATA_HOME"
"$GODOT" --path game
# After closing, relaunch with the same environment:
"$GODOT" --path game
```

On macOS, where the owner plays, an editor/project run stores the file at `~/Library/Application Support/Godot/app_userdata/Tortuga/settings.cfg`. This follows Godot 4.7 `OS.get_user_data_dir()`; the project does not set `application/config/use_custom_user_dir`. Move any existing file aside before the demo and restore it afterwards.

1. **Keyboard remap.** At 1280×720 windowed, use the keyboard only to open Settings.
   - Bind Turn left to Q: rejected, conflicts with Fire port.
   - Bind J, set 60 / 25 / 0, select Fullscreen, Apply.
   - Check that the current prompts show J. Select practice and steer with J; A no longer steers.
2. **Settings from pause.** Damage the practice target, then Escape → Settings.
   - Waiting or editing does not advance damage, projectiles or reload.
   - Start a key capture, switch applications and return: the capture cancels and the game stays paused.
   - Back returns to Pause.
   - An explicit Resume produces no stray action; a fresh fire works.
   - Restart keeps the preferences.
3. **Relaunch.** Quit during damaged practice and relaunch with the same demo profile.
   - The selection menu appears, and J / 60 / 25 / 0 / Fullscreen are restored.
   - Starting practice gives fresh positions, tracks and guns, with no earlier damage, projectiles or encounter outcome.
4. **Mouse and display modes.**
   - Repeat using mouse click/drag at 1920×1080.
   - Check windowed and fullscreen at both target client sizes on suitable native displays. For 1080p, resize the windowed client manually.
   - Record the actual size and mode after transitions settle. Labels, status, focus and footer must stay readable and reachable.
   - Returning to windowed requests 1280×720; window coordinates and size do not persist.
   - Record any native mode that is unavailable as unverified.
5. **Defaults and fallback.**
   - Defaults → Apply → exit/relaunch should restore the original bindings, 100 / 80 / 35, and 1280×720 windowed.
   - Corrupt only the isolated demo file. Verify the native fallback notice and that the default menus are reachable.
   - Remove only the owned `$DEMO_ROOT` after every launch has closed and evidence is collected.
6. **Audio scope.** Record the bus values and mute state now. Actual Effects/Ambient source routing, perceived volume and pause silence need the plan 07 sounds. Plan 08 repeats the persistence/input/display/focus checks in native packaged Linux, Windows and macOS runs. Export or headless success cannot close those gates.

## Native results

| Check | Build / display / client size / tester | Observation |
|---|---|---|
| Keyboard remap, 1280×720 windowed → fullscreen | Pending owner real-display verification | No rendered observations claimed from headless checks. |
| Pause/Settings freeze, focus-loss capture cancel, Resume | Pending owner real-display verification | — |
| Relaunch restores J/60/25/0/fullscreen; fresh practice | Pending owner real-display verification | — |
| Mouse at 1920×1080, windowed/fullscreen at both sizes | Pending owner real-display verification | — |
| Defaults round trip; corrupt-file native notice | Pending owner real-display verification | — |
| Audible bus routing / perceived volume / pause silence | Plan 07 (no sound sources yet) | Unverified |
| Packaged Linux/Windows/macOS persistence | Plan 08 | Unverified |
