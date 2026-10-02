# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Tortuga is a modern remake of *Sid Meier's Pirates!*, built in Godot **4.7.2 stable, Compatibility renderer** (pinned; no substitute version). Project-wide priorities: fast performance, very fast loading, tiny download/install size — these drive engine, asset and feature choices. `MASTER-PLAN.md` holds the phased roadmap (currently Phase 2: offline naval MVP); per-plan runbooks and verification records live in `docs/phase-2/`. Plans/specs are GitHub issues on `dnldxn/tortuga`.

## Toolchain

The engine lives outside the repo in `$HOME/.cache/tortuga-godot-4.7.2` (one-time setup with checksum verification: `docs/phase-2/sailing-playground.md`). In each new shell:

```bash
export P="$HOME/.cache/tortuga-godot-4.7.2"
export XDG_DATA_HOME="$P/xdg/data" XDG_CONFIG_HOME="$P/xdg/config" XDG_CACHE_HOME="$P/xdg/cache"
export GODOT="$P/bin/Godot_v4.7.2-stable_linux.x86_64"
```

The dev host is a headless Linux tty (no X11/Wayland, no Xvfb): headless runs validate logic only, not rendering. Real-display play is done by the owner on macOS.

## Commands (from repo root)

```bash
"$GODOT" --headless --path game --import                                  # after adding/changing assets
bash game/tests/run_settings_checks.sh                                    # full suite + settings process probes, isolated user data; exit 1 on any failure
bash game/tests/run_settings_checks.sh --self-test-failure                # must exit 1 (runner sanity)
"$GODOT" --headless --path game --quit-after 30                           # smoke-run the real main scene (reads user://settings.cfg; the toolchain $P/xdg exports keep it off the real profile)
"$GODOT" --path game --resolution 1280x720                                # play (needs a display)
bash tools/build_release.sh 0.N build/phase-2/release   # local build of all release assets
```

`GODOT` must be an absolute path for the wrapper. There is no per-test filter: to run one suite, temporarily trim `SUITES` in `game/tests/run_tests.gd` and still run it through the wrapper (raw `run_tests.gd` refuses to run without the wrapper's isolated user data, `TORTUGA_TEST_ROOT`). Expected invalid-ID `ERROR` lines in test output are deliberate.

## Tests

`game/tests/run_tests.gd` is a dependency-free runner (`extends SceneTree`). Suites are registered explicitly in its `SUITES` array — a new suite does nothing until added there. Each suite is a `RefCounted` script with `func run(t) -> bool` that calls `t.check(ok, label)` / `t.near(actual, expected, eps, label)` and **must `return true` at the end**; a GDScript runtime error aborts `run()` silently and returns null, which the runner counts as a failure. Suites run on the runner's first frame so scenes added to `t.root` get `_ready`. UI/wiring suites instantiate `res://main.tscn`, disable physics processing, and drive ticks manually via `main.advance_tick()`. The runner's isolation guard requires `user://` under `TORTUGA_TEST_ROOT` (set by the wrapper); suites that write `user://settings.cfg` must delete it and restore the InputMap/bus state they found.

## Architecture (`game/`)

Strict sim / controller / presentation split:

- **`sim/naval_simulation.gd`** — pure `RefCounted` state: no SceneTree, nodes, physics, input, drawing or audio. `reset(preset_id, vessel_id)` and `step(dt, commands)` where `commands` is keyed by ship ID (`turn`, `toggle_sails`, `fire_port/starboard`, `cycle_port/starboard`). State: `ships` (int id → Dictionary; player is id 1, opposition ≥ 2), `projectiles`, `events` (current step only), `elapsed`, `result`, `wind_heading`. Step order: toggle → turn → speed → move → `resolve_contacts()` → elapsed. A non-empty `result` freezes `step()`. Deterministic: identical command tapes must produce identical checkpoints (tests assert this).
- **`sim/definitions.gd`** — all tuning data: `VESSELS` (sloop/brig/frigate), `PRESETS`, arena, wind, `AMMO`, and `AI` tuning. Put new tuning constants here, not inline.
- **`sim/ai_controller.gd`** — deterministic opposition AI. Takes a copied `sim.ai_observation()` and returns ordinary commands (same shape a player issues); never touches the sim, nodes or input. Its own sim-time clock is the only time source.
- **`main.gd`** — mode controller (`selection` / `sailing` / `paused` / `result`). Owns `sim` and `ai`, collects input into per-tick commands (edge-triggered actions queue once per tick; held keys never repeat), and runs exactly one fixed 1/60 s step per `advance_tick()` with no accumulator/catch-up. The SceneTree is never paused (menus keep running); pausing just gates ticks. Signals `practice_started` (after reset — views resync) and `mode_changed`. `return_to_selection()` replaces `sim`, so views must read `main.sim` fresh each time.
- **`view/arena_view.gd`, `ui/*.gd`** — presentation built in code (menus, HUD, theme are created in `main._ready`, not in `.tscn`). They read `main.sim` and must never mutate it; events are deep-copied before use.
- **`input_bindings.gd`** — default action map installed at startup (A/D steer, W sails, Esc pause, plus fire/cycle/reset actions) and remapping of the 8 gameplay actions (logical keycodes; Escape and `ui_*` reserved).
- **`settings.gd`** — `RefCounted` settings model owned by main: load → apply at startup. ConfigFile `user://settings.cfg` holds only version, the 8 keys, 3 bus gains and window mode; an invalid file means all defaults + a notice and is never rewritten. Buses come from `default_bus_layout.tres` (Master/Effects/Ambient).
- **`ui/settings_menu.gd`** — draft-edit overlay opened from selection/pause; while open, main routes all input to it first. Apply = save, then apply.

Ship art is SVG in `game/assets/ships/` (see `ATTRIBUTION.md`); `game/.godot/` and `build/phase-2/` are gitignored.

## Conventions and process

- Each plan ends with a verification record in `docs/phase-2/` (commands run, check counts, what was and wasn't verified). Keep headless/automated evidence distinct from native/real-display evidence; a Linux export is not proof it runs on macOS.
- No network imports in `game/`.
- Every push to main publishes v0.N via .github/workflows/release.yml; local build: tools/build_release.sh.
