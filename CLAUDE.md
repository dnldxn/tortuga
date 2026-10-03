# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Tortuga is a modern remake of *Sid Meier's Pirates!*, built in Godot **4.7.2 stable, Compatibility renderer** (pinned; no substitute version). Project-wide priorities: fast performance, very fast loading, tiny download/install size — these drive engine, asset and feature choices. `MASTER-PLAN.md` holds the phased roadmap (currently Phase 2: offline naval MVP); per-plan runbooks and verification records live in `docs/phase-2/`. Plans/specs are GitHub issues on `dnldxn/tortuga`.

## Toolchain

The engine lives outside the repo in `$HOME/.cache/tortuga-godot-4.7.2` (one-time setup with checksum verification: `docs/phase-2/sailing-playground.md`; macOS setup and isolation notes: `docs/phase-2/08-updates.md` §1). The dev host is the owner's Mac (arm64); Linux CI is authoritative for releases. Headless runs validate logic only, not rendering. In each new shell:

Linux:
```bash
export P="$HOME/.cache/tortuga-godot-4.7.2"
export XDG_DATA_HOME="$P/xdg/data" XDG_CONFIG_HOME="$P/xdg/config" XDG_CACHE_HOME="$P/xdg/cache"
export GODOT="$P/bin/Godot_v4.7.2-stable_linux.x86_64"
mkdir -p /tmp/opencode
```

macOS:
```bash
export P="$HOME/.cache/tortuga-godot-4.7.2" GODOT="$HOME/.cache/tortuga-godot-4.7.2/bin/Godot.app/Contents/MacOS/Godot"
mkdir -p /tmp/opencode "$P/home"
```

macOS notes:
- Godot ignores `XDG_*` there; `user://` follows `$HOME/Library/Application Support`. The wrapper isolates it via `HOME`; run any direct Godot command (not the wrapper) as `HOME="$P/home" "$GODOT" ...` so the real profile is never touched.
- Never export `XDG_CONFIG_HOME` in the macOS shell: it hides `gh`'s login.
- There is no `timeout`; use `perl -e 'alarm 600; exec @ARGV' <cmd>`.

## Commands (from repo root)

```bash
"$GODOT" --headless --path game --import                                  # after adding/changing assets (macOS: prefix HOME="$P/home")
bash game/tests/run_settings_checks.sh                                    # full suite + settings process probes, isolated user data (XDG on Linux, HOME on macOS); exit 1 on any failure
bash game/tests/run_settings_checks.sh --self-test-failure                # must exit 1 (runner sanity)
"$GODOT" --headless --path game --quit-after 30                           # smoke-run the real main scene (reads user://settings.cfg; the XDG exports on Linux, HOME="$P/home" on macOS, keep it off the real profile)
"$GODOT" --path game --resolution 1280x720                                # play (needs a display)
bash tools/build_release.sh 0.N build/phase-2/release   # local build of all release assets
sudo /usr/local/sbin/tortuga-update-server [0.N]   # on the OCI server only (docs/phase-3/server-ops.md)
"$GODOT" --headless --path game -- --server --port 24680 --password SECRET [--stop-file PATH]   # dedicated server; port and password are required (CLI, else env TORTUGA_SERVER_PORT / TORTUGA_SERVER_PASSWORD; no default port; macOS: prefix HOME="$P/home"); stop = touch the stop file (exit 0); exit 2 on bad options, 1 if it cannot listen
"$GODOT" --headless --path game -- --bot --host H --port P --password SECRET [--name N --captain-id ID --preset duel_sloop --vessel sloop --join --loop --idle --seconds S]   # scriptable client; one "BOT summary" line, exit 0 / 1
bash game/tests/run_server_smoke.sh                                       # real --server + 2 --bot processes on port 24690 (SMOKE_PORT); prints "Server smoke: OK"; needs absolute GODOT; CI runs it after Test
```

Local multiplayer demo (macOS, needs a display; distinct `HOME`s give distinct captain ids; runbook and checklist: `docs/phase-3/03-multiplayer-client.md` §3):

```bash
DEMO=/tmp/opencode/tortuga-demo; mkdir -p "$DEMO"/{server,anne,bob}
HOME="$DEMO/server" "$GODOT" --headless --path game --import
HOME="$DEMO/server" "$GODOT" --headless --path game -- --server --port 24680 --password demo --stop-file "$DEMO/stop"   # terminal 1
HOME="$DEMO/anne" "$GODOT" --path game --resolution 1280x720                                                            # terminal 2
HOME="$DEMO/bob" "$GODOT" --path game --resolution 1920x1080                                                            # terminal 3
```

`GODOT` must be an absolute path for the wrapper. There is no per-test filter: to run one suite, temporarily trim `SUITES` in `game/tests/run_tests.gd` and still run it through the wrapper (raw `run_tests.gd` refuses to run without the wrapper's isolated user data, `TORTUGA_TEST_ROOT`). Expected invalid-ID `ERROR` lines in test output are deliberate.

Network suites (`test_protocol.gd`, `test_battle.gd`, `test_session.gd`): session nodes stay **out of the SceneTree** (they poll themselves); tests drive `poll()` / `advance_tick()`, `free()` every node, and use one UDP port per case in 24760–24775 (smoke uses 24690). Connect clients one at a time when a case asserts slot order (auth arrival order decides the slot). Expected `ERROR` lines also come from deliberate bad `bytes_to_var` input.

Multi-client UI suite (`test_multiplayer_ui.gd`, port 24790): a real in-process `SessionServer` (process/physics off) plus several `main.tscn` clients (`anne`, `bob`, `offline`), each with its own `user://test_mp_<key>.cfg`. `_pump(n)` is the single clock (server `poll` + `advance_tick`, then every client's `session.poll` + `advance_tick`); `_until(done, limit)` pumps until a condition holds; keys go through `main._input` (`_press` / `_hold`), never `Input`. All clients share one viewport, so a `grab_focus` assertion is only meaningful in the synthetic (offline) cases. `_teardown()` also asserts `user://multiplayer.cfg` was never written.

## Tests

`game/tests/run_tests.gd` is a dependency-free runner (`extends SceneTree`). Suites are registered explicitly in its `SUITES` array — a new suite does nothing until added there. Each suite is a `RefCounted` script with `func run(t) -> bool` that calls `t.check(ok, label)` / `t.near(actual, expected, eps, label)` and **must `return true` at the end**; a GDScript runtime error aborts `run()` silently and returns null, which the runner counts as a failure. Suites run on the runner's first frame so scenes added to `t.root` get `_ready`. UI/wiring suites instantiate `res://main.tscn`, disable physics processing, and drive ticks manually via `main.advance_tick()`. The runner's isolation guard requires `user://` under `TORTUGA_TEST_ROOT` (set by the wrapper); suites that write `user://settings.cfg` must delete it and restore the InputMap/bus state they found.

## Architecture (`game/`)

Strict sim / controller / presentation split:

- **`boot.gd` / `boot.tscn`** — main scene; overlays the installed update pack from `user://updates/`, then loads `res://main.tscn`. Preloads nothing from the game.
- **`sim/naval_simulation.gd`** — pure `RefCounted` state: no SceneTree, nodes, physics, input, drawing or audio. `reset(preset_id, vessel_id)` (offline) and `reset_battle(preset_id)` (multi-captain, only `Definitions.BATTLE_PRESETS`) and `step(dt, commands, ops := [])` where `commands` is keyed by ship ID (`turn`, `toggle_sails`, `fire_port/starboard`, `cycle_port/starboard`). State: `ships` (int id → Dictionary; offline player is id 1, opposition ≥ 2, battle captains ≥ `FIRST_CAPTAIN_SHIP_ID`), `projectiles`, `events` (current step only), `elapsed`, `result`, `wind_heading`, `battle_mode`, `outcomes`. Every ship also carries `escape_armed`, `escape_clear_ticks`, `lingering`, `linger_ticks`. Intra-step order: see `step()`'s doc comment. A non-empty `result` freezes `step()`. Deterministic: identical command+ops tapes give identical checkpoints (tests assert this).
  - **Battle mode:** `ops` are `add_captain` / `linger` / `reclaim` / `abandon` (by `ship_id`); an invalid op is `push_error` + skipped, and offline ops are ignored. Drop-in: a later captain spawns on the arena edge, outside gun range of every active AI ship. Linger: a left captain's ship keeps sailing with `{}` commands for 30 s of battle time, can be hit but not escape, then is removed as `abandoned`. `outcomes[id]` is `{outcome, elapsed}` per captain (`sunk` / `disabled` / `escaped` / `abandoned` / `victory`). The battle `result` (`victory` / `draw` / `lost`) is set only after a captain has joined.
- **`sim/definitions.gd`** — all tuning data: `VESSELS` (sloop/brig/frigate), `PRESETS` (incl. the multiplayer-only group presets `brig_squadron`, `frigate_escort`), `BATTLE_PRESETS`, `LINGER_SECONDS`, `MAX_CAPTAINS` / `MAX_BATTLES`, `DROP_IN`, arena, wind, `AMMO`, and `AI` tuning. Put new tuning constants here, not inline.
- **`sim/ai_controller.gd`** — deterministic opposition AI. Takes a copied `sim.ai_observation()` and returns ordinary commands (same shape a player issues); targets the nearest active enemy, sticky; never touches the sim, nodes or input. Its own sim-time clock is the only time source.
- **`main.gd`** — mode controller (offline: `selection` / `sailing` / `paused` / `result`; multiplayer: `connect` / `harbor` / `battle` / `battle_result`). Owns `sim` and `ai`, collects input into per-tick commands (edge-triggered actions queue once per tick; held keys never repeat), and runs exactly one fixed 1/60 s step per `advance_tick()` with no accumulator/catch-up. The SceneTree is never paused (menus keep running); pausing just gates ticks. Signals `practice_started` (after reset — views resync) and `mode_changed`. `return_to_selection()` replaces `sim`, so views must read `main.sim` fresh each time. Views never assume ship ids 1/2/3: `own_ship_id` (1 offline; the captain's ship in a battle), `focus_ship_id()` (camera/audio target: `spectate_id` while it is in `sim.ships`, else `own_ship_id`) and `captains` (ship id → `{name, slot}`; empty offline) are the identity API, reset by `_reset_identity()`.
  - **Multiplayer modes:** the child `SessionClient` opens no socket, and nothing reads `user://multiplayer.cfg`, until Multiplayer is pressed. In a `battle`, `main.sim` is `buffer.mirror` (never stepped); `advance_tick()` branches to `_advance_battle()` (steer every tick, advance the buffer, events through `Presentation.normalize_events`). `_can_command()` is the single gate for steering and actions (battle mode, menu closed, no own outcome, own ship active). A battle never pauses: Esc opens `battle_menu` (the ship keeps sailing, held input is cleared) and focus-out only clears input. Sunk/disabled → defeat panel → Watch allies (`spectate_id`, A/D cycle) or Return; escaped/abandoned → harbor with a notice; `battle_result` shows the shared result.
- **`update/update_service.gd`** — owned by main (child "UpdateService"). Network only on click (Check / Update and Restart), never at startup; `disabled` for `dev` builds. Reads version/base from `res://version.cfg`, downloads pack to `user://updates/<file>.part`, verifies SHA-256, renames, writes `installed.cfg`, then restarts. Signals `state_changed(state, detail)`, which main forwards to the selection menu.
- **Server release** — no export preset (base ID): `build_release.sh` packs the stock `linux_release.arm64` template, the linux pack and `override.cfg` (live stdout) as `tortuga-server-linux-arm64.tar.gz` (+ `.sha256`). Box kit: `tools/update_server.sh`, `tools/tortuga-server.service`; graceful stop = `ExecStop` touching `/run/tortuga-server/stop`, SIGTERM is abrupt.
- **`net/protocol.gd`** — static wire protocol, no RPCs: every packet is `send_bytes` and byte 0 is the kind (`0` = `var_to_bytes(Dictionary)` with a String `"t"`, `1` = compact little-endian battle snapshot). Channel 0 reliable (control, actions, events), channel 1 snapshots (unreliable) and steering (unreliable ordered). Holds the constants (port 24680, snapshot every 3rd tick = 20 Hz, steer stale 500 ms), `parse_cli`, `steer_turn`, `result_hash`. Decoders never allow object decoding.
- **`net/battle.gd`** — server-side wrapper of one battle: a `NavalSimulation` plus the captain id → ship map, queued membership ops, and the barred set (a captain who sank, escaped or was abandoned cannot re-enter). `tick` counts completed steps.
- **`net/session_server.gd`** — `Node` owning its own `SceneMultiplayer` + `ENetMultiplayerPeer`, polled by itself (`poll()` receives, `advance_tick()` steps), so one process can host a server and several clients; set `root_path = /root` on every `SceneMultiplayer` or all `send_bytes` packets are silently dropped. Handshake (version, password, full; same captain id replaces), harbor, up to 4 concurrent battles, authority = peer → captain → ship. Ticks run only while at least one captain is connected. Actions are queued per captain and applied one per tick (FIFO, none lost); steering is the latest value, neutral once older than 500 ms. `set_timeout(32, 2000, 4000)` drops a silent peer in under 5 s.
- **`net/session_client.gd`** — `Node` mirror of the server with the same self-polling and `root_path`; emits signals for harbor, snapshots, events, outcomes, refusals and `connection_ended` (`server_stopped` / `connection_lost` / `replaced`). Views and bots read it, never the sim.
- **`net/snapshot_buffer.gd`** — client-side buffer of one battle: orders 20 Hz snapshots and events, refills a `NavalSimulation` `mirror` every 60 Hz tick `DELAY_TICKS` = 6 (~100 ms) behind the newest snapshot (ships and projectiles interpolated by id; holds at the newest, never extrapolates; resyncs when more than `MAX_LAG_TICKS` behind) and releases each event once, in tick order. No nodes, no network.
- **`net/multiplayer_config.gd`** — `RefCounted` model of `user://multiplayer.cfg` (captain id, name, host, port, password): a field that fails its check falls back to its default and the repaired file is saved. Touched only after Multiplayer is pressed.
- **`net/server_main.gd` / `.tscn`** — `--server` entry (`main._ready` redirects before settings/input/UI exist; `boot.*` is untouched). `Engine.max_fps = 60`, prints `SRV` log lines. Graceful stop is **stop-file only**: Godot's SIGTERM kills the process at once (exit 143) and SIGINT is ignored, and GDScript sees neither, so a deploy touches the stop file and the server notifies captains, waits up to 1 s and exits 0. The server never writes or deletes that file.
- **`net/bot_main.gd` / `.tscn`** — `--bot` headless client for the smoke and soak plans: steers, fires, optionally `--join` / `--loop` / `--idle` / `--seconds`; always prints exactly one `BOT summary` line; exit 0 on success, 1 on refusal, connection loss or no joinable battle.
- **`view/arena_view.gd`, `ui/*.gd`** — presentation built in code (menus, HUD, theme are created in `main._ready`, not in `.tscn`). They read `main.sim` and must never mutate it; events are deep-copied before use.
- **`ui/multiplayer_menu.gd`, `ui/harbor_menu.gd`, `ui/battle_menu.gd`** — connect form (address/name/password, refusal texts), harbor (battle rows with Join / Reclaim / Closed; Start with a preset + vessel picker) and the in-battle menu (Resume / Settings / Help / Leave, plus the defeat panel). Menus validate and emit signals; `main` owns the session and feeds results back. HUD in battle: roster cards are slots (own, opposition 1, 2), card 1 becomes a compact list for three opponents, and an `ally_panel` card comes last.
- **`input_bindings.gd`** — default action map installed at startup (A/D steer, W sails, Esc pause, plus fire/cycle/reset actions) and remapping of the 8 gameplay actions (logical keycodes; Escape and `ui_*` reserved).
- **`settings.gd`** — `RefCounted` settings model owned by main: load → apply at startup. ConfigFile `user://settings.cfg` holds only version, the 8 keys, 3 bus gains and window mode; an invalid file means all defaults + a notice and is never rewritten. Buses come from `default_bus_layout.tres` (Master/Effects/Ambient).
- **`ui/settings_menu.gd`** — draft-edit overlay opened from selection/pause; while open, main routes all input to it first. Apply = save, then apply.

Changing a base-ID file (`project.godot`, `export_presets.cfg`, `default_bus_layout.tres`, `boot.*`, `class_name` lines) or the engine forces players to do a full download. Use `res://` paths, not `uid://`, in load/preload.

Ship art is SVG in `game/assets/ships/` (see `ATTRIBUTION.md`); `game/.godot/`, `build/phase-2/` and `build/phase-3/` are gitignored.

## Conventions and process

- Each plan ends with a verification record in `docs/phase-2/` (commands run, check counts, what was and wasn't verified). Keep headless/automated evidence distinct from native/real-display evidence; a Linux export is not proof it runs on macOS.
- No network imports in `game/`.
- Every push to main publishes v0.N (9 assets, incl. the linux-arm64 server archive) via .github/workflows/release.yml; local build: tools/build_release.sh. Server ops: docs/phase-3/server-ops.md.
