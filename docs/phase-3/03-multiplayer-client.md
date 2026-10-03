# Plan 03 — Multiplayer client: harbor and shared battles — runbook and verification record

Issue: https://github.com/dnldxn/tortuga/issues/23 · Spec: https://github.com/dnldxn/tortuga/issues/20
(the client half of spec sections 3 and 4, plus the headless multi-client checks of section 5; no server
internals, packaging, relay or own-ship prediction). Requires Plans 01-02. Engine: Godot 4.7.2 stable,
Compatibility renderer.
Date: 2026-10-02 (owner local, PDT).

Base commit: `b0e145f` (HEAD of main when the work started). Nothing was pushed; the owner decides when
(a push to main publishes a release).

| Commit | Subject |
|---|---|
| (this commit — `git log --grep "multiplayer client: harbor"`) | the whole plan, as one commit (owner choice): Tasks 1-8 |

The plan's per-task commits became one commit at the owner's request, so the tasks below have no SHAs.
Each task was reviewed against off-branch snapshot refs while the work stayed uncommitted.

| Task | Subject |
|---|---|
| 1 | Ship identities without fixed ids (`own_ship_id`, `focus_ship_id()`, `captains`, `opposition_ids`, labels, badges, shapes) |
| 2 | Ally presentation (slot colors, rings, labels, edge markers, HUD ally rows, "hit ally" notice) |
| 3 | `user://multiplayer.cfg` model (`game/net/multiplayer_config.gd`) |
| 4 | Snapshot buffer and mirror (`game/net/snapshot_buffer.gd`) |
| 5 | Multiplayer entry, connect form and harbor (`multiplayer_menu.gd`, `harbor_menu.gd`) |
| 6 | Shared battle mode (`battle_menu.gd`, battle input, steering, actions, leave and reclaim) |
| 7 | Defeat, spectating and battle results |
| 8 | This record and the CLAUDE.md update |

## How it works

- **Modes.** `main.gd` gains `connect`, `harbor`, `battle` and `battle_result`. The offline modes are
  untouched. Multiplayer is a button on the selection screen. There is no socket, and nothing reads
  `user://multiplayer.cfg`, until it is pressed; `_teardown` in the UI suite asserts the file is never written
  by the suite.
- **Identity.** Views no longer assume ship ids 1/2/3. `main.own_ship_id` (1 offline) is the commanded ship,
  `main.focus_ship_id()` is the camera and audio target (`spectate_id` while it is in `sim.ships`, else the own
  ship) and `main.captains` maps a captain's ship id to `{name, slot}` (empty offline).
  `CombatPresentation.opposition_ids` and `ally_ids` map ids to HUD slots. Offline text and layout are
  byte-identical to before.
- **The mirror.** In a battle `main.sim` is `SnapshotBuffer.mirror`, a `NavalSimulation` that is never stepped.
  Every 60 Hz tick the buffer moves `render_tick` forward and refills the mirror from the snapshots around it,
  `DELAY_TICKS` = 6 (about 100 ms) behind the newest one, interpolating ships and projectiles by id. It holds
  at the newest snapshot (never extrapolates), resyncs when more than `MAX_LAG_TICKS` = 15 behind, and
  releases each event once, in tick order, into the existing `normalize_events` to audio, view and HUD path.
- **Input.** `_advance_battle` sends the steer value every tick (S3). Fire, cycle and sails presses go as one
  reliable action each. `_can_command()` is the single gate: battle mode, battle menu closed, no own outcome,
  own ship active.
- **No pausing.** Esc opens `battle_menu`; the ship keeps sailing under it, held input is cleared, and
  focus-out never pauses. Settings opens over the battle menu and returns to it.
- **Leaving and returning.** Leave battle lingers the ship for 30 s (the server's rule); the harbor shows
  Reclaim, and other captains see "AWAY". Escaped and abandoned outcomes go to the harbor with a notice.
- **Defeat.** Sunk or disabled opens a defeat panel: Watch allies (A/D cycle through live allies, wrapping;
  a watched ally that leaves falls to the next one) or Return to harbor. The shared `battle_result` (Victory,
  Draw, Lost) lists every captain's outcome and the surviving or sunk opposition, and returns to the harbor.
- **Endings.** `server_stopped` and `connection_lost` return to the connect form with "Server stopped." or
  "Connection lost."; a refused connect shows the specific reason ("Wrong password." and so on).
- **HUD (ruling R2, see Decisions).** The current HUD is a top row of equal roster cards, not the corner
  panels the plan was written against. `panels` keeps its indices; the roster card keys are card slots.

## 1. Local headless evidence (native macOS)

Owner's Mac (arm64, macOS), natively, headless. This is not rendering evidence, not Linux evidence and not a
real network: every connection is loopback, in-process or between local processes. Direct Godot commands ran as
`HOME=<throwaway> "$GODOT" ...`; the wrapper isolates `user://` itself (since Plan 01).

**Baseline** (before Task 1): wrapper exit 0, `Tests: 5467 checks, 0 failures`.

**Final runs on the finished working tree** (two consecutive full wrapper runs; raw logs local, not committed):

| Command | Result |
|---|---|
| `bash game/tests/run_settings_checks.sh` (run 1) | exit 0; `Guard rejection: OK`; 30 suites; `Tests: 6568 checks, 0 failures`; `Settings process probes: OK`; no `FAIL`, no `SCRIPT ERROR`, no `WARNING` |
| `bash game/tests/run_settings_checks.sh` (run 2) | the same: exit 0; `Tests: 6568 checks, 0 failures`; probes OK; the same 35 `ERROR` lines as run 1 |
| `bash game/tests/run_settings_checks.sh --self-test-failure` | exit 1; `Tests: 6569 checks, 1 failures` |
| `bash game/tests/run_server_smoke.sh` | exit 0; `Server smoke: OK`; `Server CPU% / RSS KiB:   5.5 150208` |
| `HOME=/tmp/opencode/tortuga-smoke "$GODOT" --headless --path game --quit-after 30` (after a `--import` in that HOME, exit 0, no `ERROR`) | exit 0; output is the engine banner only |
| `grep -rn "uid://" game --include='*.gd'` | no output |
| `git grep -n "^class_name" -- game` | one line, `game/view/ship_3d_view.gd:1: class_name Ship3DView`, which is unchanged since `b0e145f` (the line is in the base commit, so the base ID is unaffected) |
| `git diff --stat b0e145f -- game/project.godot game/export_presets.cfg game/default_bus_layout.tres game/boot.gd game/boot.tscn` | empty |
| `git diff --check` | clean |
| `bash game/tests/run_settings_checks.sh` on an export of exactly the committed tree (this plan's files only; the concurrent session's edits left out) | exit 0; `Tests: 5764 checks, 0 failures` (baseline 5467 + 297 from this plan); `Settings process probes: OK` |

The 35 `ERROR` lines are the deliberate invalid-input probes of older suites (identical to the Task 7 run);
none comes from a suite added here. No `FAIL:` line appeared in either run, so there was nothing to classify
against the concurrent session (see below).

**Four new suites** (registered before `test_updater.gd`, which stays last): `test_battle_presentation.gd`
(identities, then allies), `test_multiplayer_config.gd`, `test_snapshot_buffer.gd`, `test_multiplayer_ui.gd`.
Existing suites changed by this plan only where they asserted the old menu order:
`test_duel_ui.gd` (the focus order gains Multiplayer) and `test_updater.gd` (`_locked_buttons` gains the
button). Every other pre-existing suite passes untouched by this plan.

**Check counts per task** (full wrapper, 0 failures each time). These totals also include checks that the
concurrent session added to older suites, so the steps between tasks are not all this plan's:

| After | Checks |
|---|---|
| Baseline | 5467 |
| Task 1: identities | 5495 |
| Task 2: allies | 5518 |
| Task 3: multiplayer config | 5579 |
| Task 4: snapshot buffer | 5630 |
| Task 3-4 fix round 1 | 5658 (10 failures, all concurrent-session; see Concurrent work) |
| Task 5: connect and harbor | 6496 |
| Task 6: shared battle | 6536 |
| Task 7: defeat, spectating and results | 6568 (twice) |
| Task 8: final two runs | 6568, 6568 |

**TDD evidence.** Every task has a recorded RED (a named `FAIL:` or a script error, usually from a trimmed
`SUITES`, always through the wrapper) before its GREEN. Examples: Task 1 `Nonexistent function
'opposition_ids'`; Task 3 and 4 `suite loads` failures with the implementation absent; Task 5 `Preload file
"res://ui/multiplayer_menu.gd" does not exist`; Task 6 `FAIL: mp battle: Anne's start enters battle with her ship
mirrored`; Task 7 `Nonexistent function 'show_battle_result'` and `FAIL: mp defeat: ...`. Three first REDs (Tasks 1, 5 and 6)
failed for a test-side parse error instead (multi-line lambdas in call arguments, which GDScript rejects); each was
rewritten and re-run to a proper RED.

**What the headless multi-client suite proves** (`test_multiplayer_ui.gd`, a real in-process `SessionServer` on
port 24790 and `main.tscn` clients driven by one `_pump` clock, keys through `main._input`):
- connect with a wrong password and a right one, the harbor listing, Disconnect and reconnect (same slot);
- start, drop-in, mirrored allies, own projectiles, "no loaded guns", steering held and released, no dropped
  actions;
- the battle menu does not pause (server tick and elapsed keep advancing, heading unchanged under a held key),
  Settings round trip, focus loss, Leave, Reclaim (same ship), "AWAY" on the other client;
- defeat panel, Watch, camera on the watched ally, shared Victory identical on both clients
  (`anne.sim.result == bob.sim.result`), per-captain result lines, Return to harbor;
- `server.stop()` returns the client to "Server stopped."; a following offline encounter starts normally.

Synthetic cases cover the buffer, the ally presentation, refusal and outcome texts, and the result lines.

**Measurements** (headless `get_combined_minimum_size`, not pixels on a screen): selection content 639 px
(the 640 px scroll no longer scrolls), selection panel 700x660, connect form 500x455, a 4-battle harbor
660x472, the picker 660x565, the battle menu with help fits 1280x720, the defeat panel fits 1280x720, and
`roster_row` has a minimum width <= 1256 for both a 3-card and a 4-card battle layout.

## 2. CI evidence (Linux x86_64, GitHub Actions)

Pending push. Nothing was pushed. To record after the push: `gh run view --log` for the run id, the Test step's
three lines (`Guard rejection: OK`, `Tests: N checks, 0 failures`, `Settings process probes: OK`) and the
Server smoke step's `Server smoke: OK` with its CPU/RSS line.

## 3. Real-display demo (owner, macOS)

Every item below is **pending — owner, real display**. An agent has no display and ran none of it. Record
OS, the physical display (and its scale) next to each result.

Commands (distinct `HOME`s give distinct captain ids; the first `--import` fills the server's HOME):

```bash
export GODOT="$HOME/.cache/tortuga-godot-4.7.2/bin/Godot.app/Contents/MacOS/Godot"
DEMO=/tmp/opencode/tortuga-demo; mkdir -p "$DEMO"/{server,anne,bob}
HOME="$DEMO/server" "$GODOT" --headless --path game --import
HOME="$DEMO/server" "$GODOT" --headless --path game -- --server --port 24680 --password demo --stop-file "$DEMO/stop"   # terminal 1
HOME="$DEMO/anne" "$GODOT" --path game --resolution 1280x720   # terminal 2
HOME="$DEMO/bob" "$GODOT" --path game --resolution 1920x1080   # terminal 3
```

| # | Check | Result |
|---|---|---|
| 1 | **Connect:** a wrong password shows "Wrong password."; with `demo` both clients reach the harbor | pending — owner, real display |
| 2 | **Drop-in:** Anne starts Brig squadron; Bob joins in a sloop away from the enemies; each sees the other's ring, numbered name, color, HUD row and off-screen indicator | pending — owner, real display |
| 3 | **Helm:** steer, sails, cycle, fire; each fire press gives a volley or "no loaded guns". Note the helm feel at the 100 ms interpolation delay | pending — owner, real display |
| 4 | **Hit ally:** Anne shoots Bob and sees "hit ally Bob!" | pending — owner, real display |
| 5 | **Non-pausing:** the Esc menu (Help, Settings then Back) and clicking another app do not pause the battle; no stale turn afterwards | pending — owner, real display |
| 6 | **Leave / reclaim:** Bob leaves and Anne sees "AWAY"; Bob reclaims within 30 s | pending — owner, real display |
| 7 | **Defeat, spectate, victory:** Bob is sunk, then Watch allies (A/D cycles); Anne wins; both see Victory and return to the harbor | pending — owner, real display |
| 8 | **Endings:** `touch "$DEMO/stop"` shows "Server stopped."; `rm` it, restart the server, reconnect, then `kill -9 <pid>` shows "Connection lost." within about 5 s | pending — owner, real display |
| 9 | **Display:** at 1280x720 and 1920x1080 (note the physical display) every menu, the result screen and the HUD fit without overlap | pending — owner, real display |

Look at these on the real display (all measured headless only, see Not verified):
- the 4-card HUD at 1280 wide (two opponents plus an ally): the card tails "· AWAY", "SUNK" and "FULL SAILS"
  can be ellipsized;
- an ally's name label and edge marker for large hulls and long names (`marker_label_rect` is a fixed 180 px);
- the Settings and Quit buttons sharing a row on the selection screen, and the selection panel height;
- the compact 3-opponent card (a Brig squadron or Frigate escort battle) next to the Allies card.

## Chosen values

| Value | Setting | Why |
|---|---|---|
| Interpolation delay | `DELAY_TICKS` 6 (about 100 ms at 60 Hz), two 20 Hz snapshot intervals | one lost snapshot still leaves a segment to interpolate; helm feel to be judged by the owner |
| Resync | `MAX_LAG_TICKS` 15: behind by more, jump to newest minus 6 | recovers from a stall instead of fast-forwarding visibly |
| Demo / default port | 24680 (`Protocol.DEFAULT_PORT`); the UI suite uses 24790 | Plan 02 uses 24760-24775 and 24690 |
| Captain name | `NAME_MAX` 16; host max 253; password max 64 | bound what the form can send |
| Captain id | 32 lowercase hex chars (validated with a RegEx), created once per `user://` | one identity per install; a distinct `HOME` is a distinct captain |
| Ally slot colors | `SLOT_COLORS` blue, yellow, pink, white by slot (ring, label, HUD row) | the four captains stay distinguishable from the opposition, which keeps its glyph shapes |
| "hit ally" notice | 90 ticks, short name, only when the hit's `owner_id` is the own ship | feedback for friendly fire without noise |
| Short names | `short_name` limit 10 with an ellipsis | keeps labels inside edge markers and cards |
| Linger | 30 s, the server's rule; stated in the Leave notice and the battle help | the one limit a leaving captain must know |

## Decisions and deviations

Rulings made during the work (R1-R5 from the controller, then task rulings):

- **R1: no per-task commits.** One commit for the whole plan, owner's choice. The record's Commits table has a
  placeholder until then.
- **R2: HUD mapping onto the roster cards (owner decision).** The plan's HUD text was written against an older
  corner-panel HUD. The current HUD is a `roster_row` of equal cards, so:
  - `panels` keeps its indices (`[0]` own, `[1]`/`[2]` opposition, `[3]` navigation and escape, `[4]`/`[5]`
    port and starboard) and new panels are appended; `roster_cards` keys 1/2/3 became card slots, not ship ids.
  - With three opponents card 1 becomes a compact list of three single-line 16 px rows (glyph, label,
    condition, distance, state), its stat rows are hidden and card 2 is hidden. The plan's "min height <= 144"
    applies to that compact card.
  - **The allies are a new `ally_panel` card, last in `roster_row`** (`panels[6]`), visible only when there is
    an ally row or the "hit ally" notice. It replaces the plan's "ally rows in the top-left panel".
  - `banner_label` is the first child of the bottom-left navigation and escape panel.
- **R3: Task 1's grep also covers `game/audio`.** `combat_audio.gd` measures its distance gain from
  `main.focus_ship_id()`; `arena_view.readiness_geometry` uses `main.own_ship_id`. Offline both are ship 1.
- **R4: the real-display demo and CI evidence are recorded as pending.** They need a display and a push.
- **R5: concurrent session.** See below.
- **Own-card height (Task 2).** The plan's "`12 + panels[0]` min height <= 160" cannot hold: the own roster
  card is already 164 px at baseline. The check is `ally_panel` <= 160 and the own card <= the top of the
  gameplay rect (184), unchanged versus offline.
- **Ellipsis at 1280 (Task 2, accepted).** With two opponents plus allies there are four equal cards of about
  305 px; the "AWAY" / "SUNK" tail or "FULL SAILS" can be cut. Accepted under R2's equal-width cards; for the
  owner's display check.
- **Battle help says "Esc menu" (Task 7).** `bindings_text(false)` labels the key "menu", because the battle
  never pauses. Offline text (`include_reset` true) is byte-identical.
- **`combat_indicators_visible()` includes `battle` (Task 6).** Without it the ally edge markers and readiness
  strips would never draw online.
- **The waiting HUD hides the cards, side panels and speed/wind row (Task 6)** while the own ship is missing,
  so a previous encounter's numbers never flash before the first snapshot.
- **`_on_battle_result` samples the newest snapshot before freezing (Task 7).** The mirror runs about 6 ticks
  behind; without this the frozen scene could show the last AI ship afloat under "Victory".
- **Esc while defeated opens the battle menu (Task 7)**, so Settings, Help and Leave stay reachable.
- **`ConfigFile.get_value` with a `null` default** prints an ERROR per missing key, so `MultiplayerConfig` uses
  a sentinel default (Task 3).
- **Captain id validation** uses a RegEx after review found that `is_valid_hex_number` accepts a leading `-`
  (Task 3-4 fix round).
- **Escape status.** In battle mode the HUD reads the own ship's `escape_armed` / `escape_clear_ticks`; offline
  it keeps reading the sim's top-level fields, because existing suites set those directly.
- **The test clock.** All client mains share one viewport, so focus assertions in networked cases are limited to
  text and visibility; focus is asserted in the synthetic cases.

## Concurrent work (ruling R5)

Another session edited `game/` in the same checkout while this plan ran: a galleon vessel, `guns_per_row`,
camera zoom constants, `.glb` ship exports, `protocol.gd` `VESSEL_IDS`, `arena_view` `set_view_distance`, and
changes to `ship_3d_view.gd`, `definitions.gd`, `naval_simulation.gd` and several older suites
(`test_view.gd`, `test_presentation.gd`, `test_hud_layout.gd` and others). Its changes are not part of this plan
and are not described as such here. Consequences for this record:

- The intermediate check totals include its checks; only the final two runs (both GREEN, no `FAIL:` line) are on
  the finished tree.
- After Task 3-4's fix round the wrapper showed 10 failures, all in its area (camera zoom, "model camera is 30
  degrees", "invalid op skipped: unknown vessel", the `bot_options` galleon error). They were gone in every
  later run. This plan's own suites had no `FAIL:` line at any time.
- Files both sessions edited (`arena_view.gd`, `combat_presentation.gd`, `hud.gd`, `main.gd`) were re-read before
  each edit and changed with minimal hunks. The commit must separate the two sets of changes (the owner decides).

## Rule to check

`_test_` prefix dropped; suite in brackets.

| Rule (spec #20) | Check |
|---|---|
| Section 3: connect to a password-protected server; refusal reasons shown | `texts`, `connect_and_harbor` (mp_ui) |
| Section 3: harbor: start (preset and vessel), join, reclaim, closed; Start disabled at the cap | `synthetic_harbor`, `connect_and_harbor` (mp_ui) |
| Section 3: drop-in; allies visible with name, slot color, ring, HUD row, indicator | `shared_battle` (mp_ui); `allies` (battle_presentation) |
| Section 3: leave lingers, reclaim returns, "AWAY" for others | `battle_menu`, `shared_battle` (mp_ui) |
| Section 3: defeat leads to spectating; escape and abandon return to the harbor | `defeat_and_result`, `synthetic_results` (mp_ui) |
| Section 3: shared result identical on every client, per-captain lines | `defeat_and_result` (mp_ui) |
| Section 3: stop vs. sudden loss | `server_stop` (mp_ui); real `kill -9` is demo item 8 |
| Section 4: own-ship steering and actions, none dropped; steering neutral after release | `battle_actions` (mp_ui) |
| Section 4: the menu never pauses; focus-out never pauses | `battle_menu` (mp_ui) |
| Section 4: interpolation about 100 ms behind, hold, resync, events once in tick order | `interpolate`, `hold`, `resync`, `events` (snapshot_buffer) |
| Section 4: identities from ship ids, three-opponent card, offline unchanged | `wiring` (battle_presentation), `test_hud_layout`, `test_presentation` |
| Section 4: remembered settings; nothing written before Multiplayer | `test_multiplayer_config`; `_teardown` check (mp_ui) |
| Offline unchanged after multiplayer | `offline_after_multiplayer` (mp_ui) |

## Not verified

- **Everything in section 3 above.** The real-display demo, at both resolutions, is the owner's.
- **CI.** Section 2: the Linux x86_64 run has not happened.
- **Real networks.** Smoothness, loss, jitter and NAT are Plan 05; every run here is loopback. The helm feel at
  100 ms over a real link, and the own-ship prediction decision, are open.
- **The OCI arm64 server** (Plans 04-05); **Windows and Linux clients**.
- **Escape, draw and lost on a real display.** Escape and abandoned go through the harbor in synthetic and
  headless cases; the `lost` result is synthetic only; a draw has no client case.
- **Rendering.** Headless runs prove logic and measured control sizes, not appearance: 3D ship look, ring and
  label legibility, color contrast and the 1920x1080 layout were not seen.
- **Real focus and window events.** Clicking away from the window is simulated by the focus-out notification.
- **Deferred minor findings** (reviewed, not fixed):
  - **Untested paths:** a spectated ally leaving (the fall-through to the next ally or the own wreck), ally
    cycling with more than one ally (wrap), the "Disabled" defeat title, the "No allies left" banner; focus can
    rest on a Watch button that becomes disabled. The code was reviewed for them.
  - **HUD and drawing:** the 1280-wide ellipsis above; an ally label is drawn at a fixed offset and gated by the
    fixed `_ship_label_visible` rect (may clip for big hulls and wide labels); `marker_label_rect` is a fixed
    180 px and "2 Abcdefghi… · AWAY" at 18 px is borderline.
  - **Menus:** `harbor_menu.show_harbor` indexes the server's dictionaries directly (a malformed harbor from a
    non-conforming server leaves a half-built list, with a script error but no crash); Start's confirm ignores
    `can_start` turning false while the picker is open (the server refuses with `battle_cap`); Left and Right do
    not move between the side-by-side Settings and Quit (Up, Down and Tab do); Esc does nothing in `connect` and
    `harbor` modes; a failed `remember()` leaves the old remembered values while the connection uses the new
    ones.
  - **Tests:** a fit check depends on the battle menu's child order; no test pins "an echo press sends
    nothing" or "Esc in the harbor does nothing"; `combat_audio.arena_view` is re-set on every join instead of
    once in `_ready`.
  - **The final snapshot** before `battle_result` is unreliable, so the frozen result scene can be up to two
    ticks stale (cosmetic).
  - **Intermittent `ObjectDB instances were leaked at exit` warning** (about 1 run in 6 on this Mac, 2 or 4
    instances), untraced. Both final runs were clean. It predates this plan (see
    `docs/phase-2/08-updates.md`), and a run in which a test fails skips the runner's cleanup frames, which
    explains one occurrence; the cause of the others is not known and may be ENet teardown in the real-socket
    suites.

## Remaining for the owner

- Run section 3 and fill in the table; record the OS and display.
- Push, then fill in section 2.
- Decide the 1280-wide HUD tails and helm feel (interpolation delay and own-ship prediction, Plan 05) after the
  demo.
- Commit: separate this plan's files from the concurrent session's changes (`git status` also lists galleon,
  ship `.glb`, `shipyard-gallery/` and `docs/phase-2/` work that is not part of Plan 03), then add the commit
  hash to the table at the top.
