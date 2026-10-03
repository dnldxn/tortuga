# Plan 02 — Dedicated server and session protocol: verification record

Issue: https://github.com/dnldxn/tortuga/issues/22 · Spec: https://github.com/dnldxn/tortuga/issues/20
(the network half of spec sections 1-3; the UI is Plan 03, packaging Plan 04, soak and cost Plan 05).
Engine: Godot 4.7.2 stable, Compatibility renderer, headless.
Date: 2026-10-02 (owner local, PDT).

Base commit: `e90f8e1` (HEAD of main when the work started). Commits are local and **not pushed**; the owner
decides when (a push to main publishes a release).

| Task | Commit | Subject |
|---|---|---|
| 1 | `c628051` | Wire protocol and compact snapshots (`game/net/protocol.gd`) |
| 2 | `7082f32` | Server-side battle wrapper (`game/net/battle.gd`) |
| 3 | `2cd8b51` | Session handshake, captains and harbor (`session_server.gd`, `session_client.gd`) |
| 4 | `5b72629` | Battles on the session server: start, join, tick, deliver, resolve |
| 5 | `0a10afc`, `ce2517a` | Linger, reclaim, abandon, escape and drop rules pinned; fixed client connect order in tests |
| 6 | `3a7b366` | `--server` / `--bot` entry, stop file, `run_server_smoke.sh`, CI step |
| 7 | this commit | CLAUDE.md and this record |

(`a4204b7`, the interactive shipyard demo, landed between Tasks 1 and 2 and is not plan work.)

## What was built

- **`game/net/protocol.gd`**: static wire protocol with no RPCs. Byte 0 is the kind: `0` = `var_to_bytes`
  Dictionary (`"t"` String), `1` = compact little-endian snapshot. Channel 0 is reliable, channel 1 carries
  snapshots (unreliable) and steering (unreliable ordered). Decoders never allow object decoding.
- **`game/net/battle.gd`**: one server battle (battle-mode sim + AI), with membership guards so the sim never
  sees an invalid op, the one-ship-per-captain rule and the barred set (no re-entry).
- **`game/net/session_server.gd` / `session_client.gd`**: plain Nodes, each owning a `SceneMultiplayer` +
  `ENetMultiplayerPeer` and polling itself outside the SceneTree. Handshake (version, password, full, same
  captain id replaces), harbor, up to 4 concurrent battles, linger / reclaim / abandon, escape, defeat and
  spectate, shared battle result, pause when no captain is connected, stop notification.
- **`game/net/server_main`, `bot_main`** (`.gd` + `.tscn`): `--server` and `--bot` entries. `main._ready`
  redirects to them before settings, input, audio or UI exist (a 6-line change in `game/main.gd`; `boot.*` is
  untouched). `game/tests/run_server_smoke.sh` drives a real server and two bots; `release.yml` runs it after
  `Test`.
- **Tests:** `test_protocol.gd`, `test_battle.gd`, `test_session.gd`, registered before `test_updater.gd`.

## 1. Local headless evidence (native macOS)

Owner's Mac (arm64), natively, headless. This is not rendering evidence, not Linux evidence and not a real
network. Direct Godot commands ran as `HOME="$P/home" "$GODOT" ...` (or a throwaway `HOME`); the wrapper
isolates `user://` itself.

**Final run (this task, after the last code commit `3a7b366`; no game code changed since):**

| Command | Result |
|---|---|
| `bash game/tests/run_settings_checks.sh` | exit 0; `Guard rejection: OK`; `Tests: 5464 checks, 0 failures`; `Settings process probes: OK` |
| `bash game/tests/run_settings_checks.sh --self-test-failure` | exit 1; `Tests: 5465 checks, 1 failures` |
| `bash game/tests/run_server_smoke.sh` | exit 0; `Server smoke: OK` |
| `git grep -n "class_name\|with_objects\|allow_object_decoding" -- game/net` | no output |
| `git diff e90f8e1 -- game/boot.gd game/boot.tscn game/project.godot game/export_presets.cfg game/default_bus_layout.tres` | empty (0 bytes) |
| `HOME="$(mktemp -d)" "$GODOT" --headless --path game --quit-after 30 2>&1 \| grep -c "SCRIPT ERROR"` | `0` (output is the engine banner only) |

The wrapper's `Tests:` line counts all suites, offline ones included. Plan 01 ended at 4705 checks and no
existing suite was edited, so the offline suites are unchanged and green; the 759 extra checks are the three
new suites.

**Check counts per task** (wrapper, all suites, 0 failures each time):

| After | Checks |
|---|---|
| Plan 01 final / baseline | 4705 |
| Task 1: protocol + snapshot codec | 5149 |
| Task 2: server battle wrapper | 5182 |
| Task 3: handshake, harbor, stop | 5235 |
| Task 4: battles on the server | 5332 |
| Task 5: leave / drop / reclaim / abandon (after fix round) | 5439 |
| Task 6: server_options, stop file, bot_options | 5464 |

**Measurements.**

- **Snapshot size:** `snapshot frigate_escort + 4 captains + 12 projectiles: 616 bytes` (printed by
  `test_protocol.gd`; the fixed ship record is 4+1+1+1+1+1+1+1+2+2+7*4 bytes plus per-gun loads, projectiles
  are 17 bytes each). At 20 Hz that is about 12 KB/s per subscriber for this worst-case group preset.
- **Silent-client drop:** `silent client dropped after 3670 ms` in the final run (11 earlier runs: 3163-3695
  ms), inside the 5000 ms requirement. Setting: `set_timeout(32, 2000, 4000)` on every peer.
- **Smoke, this Mac:** `Server CPU% / RSS KiB:   5.6 139936` (the Task 6 run printed `6.3 140880`); both bots
  exit 0, e.g. `BOT summary name=Anne exit=0 seconds=4.4 ... snapshots=85 events=30 actions_sent=2
  actions_applied=2 disconnects=1 bytes_in=42017 bytes_out=17774 ... rtt_ms=16`, then `SRV stopped
  host_bytes_in=34872 host_bytes_out=81631`. The server's CPU% is the share of one core over the run (two
  bots, one 2-captain battle); RSS is the editor binary's, not a release export's.
- **Stop latency (separate processes):** touching the stop file to server and bots all exited: 0.70 s, including
  up to 500 ms of check interval. `SRV leave` lines come before `SRV stopped`, so out-of-process clients ack
  `server_stopping` inside `stop()`'s 1 s wait.
- **Wall time:** the wrapper takes about 21 s; the session suite about 8 s of that (3 s of it the in-process
  stop case, 3.4 s the silent-client case, both bounded by ENet timeouts, not CPU).

**Re-confirmed ENet / SceneMultiplayer facts** (measured while planning, re-checked during the build):

- A standalone `SceneMultiplayer` needs `root_path = NodePath("/root")` even with no RPCs. Removing it from
  both nodes dropped every packet (`Multiplayer root was not initialized`, scene_multiplayer.cpp:216) and
  failed 8 checks; the auth handshake itself still worked, because `send_auth` does not use the path.
- A refusal `send_auth` followed by `peer_disconnect_later()` reaches the client before the disconnect: each
  refused client gets exactly one `auth_refused` and no `connection_ended`.
- An unpolled client is dropped after about 2.7-3.3 s with `set_timeout(32, 2000, 4000)`.
- Byte counts exist only as host totals (`HOST_TOTAL_*`); per-captain counts in the logs are payload sizes.
- **New:** `ENetMultiplayerPeer.close()` sends `disconnect_now` only to CONNECTED peers; a peer already in
  DISCONNECT_LATER (as `stop()` leaves them) gets nothing from `close()`.
- **SIGTERM kills the process at once (exit 143) and SIGINT is ignored; GDScript sees neither.** Hence the
  stop file.

## 2. CI evidence (Linux x86_64, GitHub Actions)

Pending until the owner pushes: nothing was pushed. To be recorded after the push: `gh run view --log` for the
run id, the Test step's three lines (`Guard rejection: OK`, `Tests: N checks, 0 failures`,
`Settings process probes: OK`) and the Server smoke step's `Server smoke: OK` with its CPU/RSS line.

## Chosen values

| Value | Setting | Why |
|---|---|---|
| Port | server: required, `--port N` or `TORTUGA_SERVER_PORT` (no default; exit 2 otherwise); `Protocol.DEFAULT_PORT` 24680 is the bot's default and the conventional server port; smoke 24690; session tests 24760-24775 | an explicit server port avoids a silent clash; the ranges keep tests, smoke and a real server apart |
| Snapshot rate | every `SNAPSHOT_EVERY_TICKS` = 3 ticks (20 Hz); sim steps at 60 Hz | spec section 2 |
| Steering staleness | `STEER_STALE_MS` 500 | a silent steerer goes neutral quickly; the drop itself comes later |
| Harbor refresh | `HARBOR_REFRESH_TICKS` 60 (also on any membership change) | keeps the harbor listing (elapsed time, lingering state) fresh without a message every tick |
| Peers | `MAX_PEERS` 8 against `MAX_CAPTAINS` 4 | room to refuse or replace without ENet rejecting the socket |
| Timeouts | `TIMEOUT_LIMIT` 32, `TIMEOUT_MIN_MS` 2000, `TIMEOUT_MAX_MS` 4000; client connect 5000 ms; server auth 3 s | silent peer gone in < 5 s |
| Limits | `NAME_MAX` 24, `CAPTAIN_ID_MAX` 64, `ACTION_QUEUE_MAX` 64 | bound untrusted client input: names and ids stay short, and a flood of reliable actions cannot grow a captain's queue without limit |
| Server frame rate | `Engine.max_fps = 60` in `server_main`/`bot_main` | sends queued in physics are flushed by the same frame's poll |
| ENet throttle / bandwidth | Godot's defaults (no `throttle_configure`, no bandwidth limit) | tuning belongs to Plan 05 with real networks; the hook is marked in `session_server.gd` |
| Stop-file check | every 500 ms; `stop()` waits up to 1000 ms | |

## Rule to check

`_test_` prefix dropped; all in `test_session.gd` unless noted.

| Rule (spec #20) | Check |
|---|---|
| Section 1: own ship only; tick-stamped snapshots and events; `fire_rejected` owner-only | `steering_actions_events` |
| Section 1: actions reliable, none lost, one per tick | its burst block |
| Section 1: steering = latest held; silent client goes neutral | `steer_turn` (protocol), `silent_client` |
| Section 1: configurable port; `--server` after boot | `server_options` (protocol); smoke |
| Section 1: handshake (version, password, full) | `auth_refusals`, `full_and_replaced` |
| Section 2: at most 4 battles, 60 Hz steps, 20 Hz snapshots | `four_battles`, `steering_actions_events` |
| Section 2: pause when empty; linger frozen; silent drop within 5 s | `pause_and_reclaim`, `silent_client` |
| Section 2: membership ops in tapes; deterministic | `tape_replay` (battle) |
| Section 3: harbor; start disabled at 4; drop-in join | `harbor_captains`, `battle_join_and_harbor`, `four_battles` |
| Section 3: defeat leads to spectating; escape to harbor; no re-entry | `defeat_and_victory`, `escape` |
| Section 3: leave or drop lingers, reclaim, abandon | `leave_reclaim_abandon`, `pause_and_reclaim`, `linger_expiry` |
| Section 3: shared identical result; battle closes | `defeat_and_victory`, `lost` |
| Section 3: stop vs. sudden loss | `server_stop`; smoke |
| Identity: same id replaces and reclaims | `full_and_replaced`, `replaced_reclaims` |
| Snapshot codec (ships + projectiles), size | `snapshot` (protocol) |

Mutation checks run during the build (each reverted): `fire_rejected` to every subscriber (1 failure), `while`
instead of `if` in the action queue (3), no harbor refresh on membership events (1); not scoping the client
outcome to the current battle shows no failure in Task 4's cases and is covered by Task 5's
start-elsewhere-then-abandoned case. Task 5 also pins the same-step `add_captain + abandon` and
`linger + reclaim` orderings through the server.

## Decisions and deviations

- **Stop file only (graceful stop).** Godot terminates on SIGTERM without script involvement and ignores
  SIGINT, so a deploy touches the stop file (`--stop-file`); the server never writes or deletes it. A stop file
  that already exists at start is ignored until its mtime changes (1 s resolution; harmless under systemd's
  fresh `RuntimeDirectory`).
- **`stop(0)` takes about 3 s in one process (R6).** `stop()` puts peers in DISCONNECT_LATER and waits for the
  ack; in-process test clients are not polled during the wait, so the clients end `server_stopped` only after
  the ENet timeout. The test pump was raised to 6 s. A `peer_disconnect_now()` fallback was rejected (ENet can
  drop `server_stopping` when both datagrams land in one client service call). Separate-process clients ack
  within the 1 s wait (0.70 s end to end). Alternative if needed: close the client on `server_stopping`.
- **`flush_stdout_on_print` handed to Plan 04 (R12).** It is not set in `project.godot` (a base-ID file), and
  Godot only flushes stdout on print in debug builds, so an exported release server piped to the journal may
  buffer `SRV` lines. The smoke uses the editor binary, which flushes.
- **Harbor dirty on membership events (R8).** Start, join and the membership events refresh the harbor
  immediately; otherwise it would list `captains: []` for up to 60 ticks.
- **Outcome/result scoped to the current battle (R9).** An abandoned outcome for the old battle arrives after
  `joined` for the new one and must not clear it.
- **Only the owner gets an outcome (R4).** Defeated captains each receive their own `sunk` outcome; others none
  until the shared `battle_result`.
- **Test captains connect one at a time (Task 5 fix).** Slots follow auth arrival order; connecting clients
  together flaked the slot assertions about 3 times in 9 runs. The server was correct; the tests were fixed.
- **`--captain-id` and `BOT error` (R3, R10).** `parse_cli` keeps option names verbatim; the bot prints one
  extra `BOT error <msg>` line before its single summary on bad arguments or no joinable battle.
- **`--seconds` (R11).** The bot leaves, then waits up to 2 s for a harbor showing it back at battle 0, so the
  last `actions_applied` is final.
- **No push (R5).** Commits are local; CI evidence is recorded after the owner pushes.
- **Unrelated work.** `docs/phase-2/shipyard-demo.md` and its evidence were uncommitted before this plan and
  are not part of any plan commit.

## Not verified

- **Real or bad networks.** Everything ran over loopback, in-process or between local processes; no latency,
  loss, jitter or NAT. ENet throttle and bandwidth knobs are untouched.
- **Other platforms.** arm64 Linux, Oracle Linux and systemd (journald, `RuntimeDirectory`, a real stop-file
  deploy) are Plan 04; Linux x86_64 CI has not run yet (section 2).
- **Exported builds.** All runs used the editor binary; stdout buffering and RSS of a release export are open.
- **Server cost and bandwidth.** One 2-captain smoke is not a soak; per-battle CPU, memory over time and
  4-battle bandwidth belong to Plan 05. The 616-byte figure is a codec size, not a measured link rate.
- **UI.** No client view; Plan 03.
- **`--loop`** re-entry after a battle ends was reviewed but not exercised (a battle takes minutes).
- **Drop-in placement and draw** are covered by Plan 01's sim tests, not re-proven through the server.
- **Deferred minor items** (reviewed, not fixed): untested validation paths (bad vessel on start/join,
  non-int `battle_id`, queue cap, bad steer), the client's final snapshot (unreliable) can be dropped when
  `battle_result` (reliable) arrives first so Plan 03 must not rely on it; the smoke does not grep for
  `SCRIPT ERROR`; `--idle --seconds` always waits 2 s; fire/cycle catch-up bursts after a hitch; an
  intermittent `4 ObjectDB instances were leaked at exit` warning that predates these suites.
