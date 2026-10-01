# Plan 05 — Two-opponent battle: verification record

Issue: https://github.com/dnldxn/tortuga/issues/8 · Godot 4.7.2 stable, Compatibility renderer.

## Implementation and balance

`two_sloops` places the selected player vessel at (2400, 2100), heading 0, and ordinary team-1 sloops at (3400, 1700) and (3400, 2500), heading π, with wind heading 0. They use the same movement, weapons, damage, contact, defeat and escape rules as the duel presets. The owner chose to retain the established sloop full speed **162** rather than the issue's proposed 180; no vessel or AI tuning constants changed. With owner approval, shared closest-approach avoidance now treats a nearby ship as a threat even at closest-approach time zero. The previous `t > 0` guard ignored equal-speed allies inside the existing clearance. Both AI ships receive independently keyed commands from the copied observation; the current aim lane suppresses an AI firing edge when an active ally intersects first, but actual later projectile contacts still apply friendly damage.

The selection offers “Two-ship encounter — two sloops” with all three player vessels. The HUD and arena identify Sloop A (ID 2) and Sloop B (ID 3), retain defeated identities, show both conditions and results, and indicate assisted-target identities. Escape requires clearance from **every active enemy**. Existing replay, return, pause, and focus-loss controller paths apply.

## Automated checks (Linux headless)

From the repository root using the pinned editor at `$HOME/.cache/tortuga-godot-4.7.2/bin/Godot_v4.7.2-stable_linux.x86_64`:

| Command | Result |
|---|---|
| `"$GODOT" --version` | `4.7.2.stable.official.ed1daf0bf` |
| `"$GODOT" --headless --path game --import` | exit 0, clean import |
| `"$GODOT" --headless --path game --script res://tests/run_tests.gd` | **2601 checks, 0 failures** after avoidance correction; deliberate invalid-ID ERROR lines from existing tests |
| `"$GODOT" --headless --path game --script res://tests/run_tests.gd -- --self-test-failure` | deliberate failure: 2602 checks, 1 failure, exit 1 (runner sanity) |
| `"$GODOT" --headless --path game --script res://tests/run_escape_witnesses.gd` | **12 named PASS rows, 12 cases, 0 failures**; each replayed twice with identical state |
| `"$GODOT" --headless --path game --quit-after 30` | exit 0, no errors |

The registered `test_two_opponent.gd`, `test_combat_roster.gd`, and `test_two_opponent_escape.gd` suites cover resets, shared sloop fairness, copied AI observations, active-ally avoidance and firing lanes, swept friendly hits, target switching, combat outcome precedence, bounded traffic fixtures, twelve lifecycle pairs, replay/selection resets and two-enemy escape boundaries. The twelve roster outcome fixtures establish **outcome plumbing**, not tactical feasibility. Practice target contact remains a normal separation and reset restores its spawn.

## Legal escape witnesses

The single `game/tests/fixtures/escape_witnesses.json` contains the nine existing duel cases and three `two_sloops` cases. The existing `run_escape_witnesses.gd` replays ordinary reset states, production AI and legal per-tick player commands. The table gives zero-based armed/completion ticks, elapsed simulation time, full-interval strict minimum live-enemy center separation, and final hull/sails/crew tracks (P = player; E2/E3 = opponents). Distances shown are rounded **for display only**; validation compares squared distances strictly against 1400² on every one of the last 480 steps. All listed opponents remain active at escape.

| Preset / vessel | Armed | Escaped | Time (s) | Min distance | Final tracks P; E2; E3 | Live enemies |
|---|---:|---:|---:|---:|---|---:|
| duel_sloop / sloop | 35 | 4047 | 67.47 | 1401.1 | 68/70/60; 100/46/60 | 1 |
| duel_sloop / brig | 41 | 2775 | 46.27 | 1400.7 | 160/100/90; 100/22/60 | 1 |
| duel_sloop / frigate | 49 | 9938 | 165.65 | 1400.2 | 104/140/140; 100/16/60 | 1 |
| duel_brig / sloop | 21 | 3168 | 52.82 | 1400.3 | 100/70/60; 160/100/90 | 1 |
| duel_brig / brig | 24 | 9794 | 163.25 | 1401.0 | 112/100/90; 160/52/90 | 1 |
| duel_brig / frigate | 27 | 4447 | 74.13 | 1400.7 | 240/140/140; 160/28/90 | 1 |
| duel_frigate / sloop | 31 | 1316 | 21.95 | 1400.1 | 100/70/60; 240/140/140 | 1 |
| duel_frigate / brig | 35 | 5111 | 85.20 | 1400.3 | 160/100/90; 240/104/140 | 1 |
| duel_frigate / frigate | 41 | 4157 | 69.30 | 1400.5 | 48/140/140; 240/50/140 | 1 |
| two_sloops / sloop | 76 | 22560 | 376.02 | >1400 (display 1400.0) | 36/70/60; 100/46/60; 100/58/60 | 2 |
| two_sloops / brig | 92 | 12033 | 200.57 | 1400.2 | 128/100/90; 100/34/60; 100/34/60 | 2 |
| two_sloops / frigate | 113 | 7838 | 130.65 | 1400.4 | 184/140/140; 100/22/60; 100/22/60 | 2 |

These tapes prove legal **simulation** escape reachability. They do not prove the same routes are easy to execute manually or enjoyable; the sloop trace takes 376 simulated seconds and ends with 36 hull. Neither an unprepared healthy ship's getaway nor a fixed encounter duration is promised. Circling, stern attacks, kiting and ammunition dominance remain questions for plans 07/08.

## Real-display handoff

No display is available on this Linux host. Native screenshots and owner play observations have **not** been collected for this slice. On macOS, check 1280×720 and 1920×1080: select the fourth preset with mouse/keyboard and each vessel; read both status rows, shapes, edge markers and assisted targets; damage either enemy and continue after the first defeat; inspect both defeat reasons, replay and return to a duel with no B residue. Verify friendly blocking/hits, pause/focus/resume without buffered actions, and the escape countdown resetting when either live pursuer returns inside the clearance distance. Demonstrate a legal tactical escape with a live opponent for each vessel. Record actual build ID, resolution, machine, screenshots, and observations here when performed.

| Build / resolution / tester | Observation |
|---|---|
| Pending owner real-display verification | No rendered observations claimed from headless checks. |

Plan 08 still owns native three-platform runs, Intel real-display budgets, newcomer usability, and owner fun/tactics acceptance. In the equal-speed 80-unit two-ally fixture, minimum observed separations were 79.99 (normal) and 80.00 (weakened). After the shared avoidance correction, separation first exceeded the 144-unit recovery-exit threshold at ticks 74 and 92 respectively, with recovery exiting at ticks 91 and 93. The unchanged duel AI suite and all twelve witness tapes passed after this adjustment; native tactical feel is still unmeasured.
