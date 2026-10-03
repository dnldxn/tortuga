# Plan 01 — Multi-captain battle simulation: verification record

Issue: https://github.com/dnldxn/tortuga/issues/21 · Spec: https://github.com/dnldxn/tortuga/issues/20
(simulation layer only; no network, server or UI, which are Plans 02–05). Engine: Godot 4.7.2 stable,
Compatibility renderer.
Date: 2026-10-02 (owner local, PDT).

Base commit: `5800bb6` (HEAD of main when the work started). The plan's six per-task commits became
one commit on main, at the owner's request, so there are no per-task SHAs; the table below is by task.

| Task | Subject |
|---|---|
| 1 | Test wrapper isolates `user://` on macOS (`HOME`) |
| 2 | Group presets, `reset_battle`, `add_captain` and the drop-in rule |
| 3 | `linger` / `reclaim` / `abandon`, per-captain escape, outcomes, battle result |
| 4 | Nearest-sticky AI targeting |
| 5 | Determinism tape and group-preset battles to a result |
| 6 | CLAUDE.md Architecture and this record |

## What was built

- **Battle mode** in `game/sim/naval_simulation.gd`: `reset_battle(preset_id)` and
  `step(dt, commands, ops := [])` with four membership ops (`add_captain`, `linger`, `reclaim`,
  `abandon`; captain ids start at `FIRST_CAPTAIN_SHIP_ID`, 100). Invalid ops `push_error` and are
  skipped. Captains drop in on the arena edge outside gun range, linger for 30 s of battle time,
  escape, sink or abandon independently, and the battle ends with a `victory` / `draw` / `lost`
  result carrying per-captain `outcomes`. The intra-step order is in `step()`'s doc comment.
- **Offline is unchanged:** `reset(preset_id, vessel_id)`, player id 1 and the Phase 2 results.
  Ships gain four keys (`escape_armed`, `escape_clear_ticks`, `lingering`, `linger_ticks`); offline,
  ship 1 mirrors the top-level escape fields.
- **Definitions:** group presets `brig_squadron` and `frigate_escort` (multiplayer-only),
  `BATTLE_PRESETS`, `LINGER_SECONDS`, `MAX_CAPTAINS`, `MAX_BATTLES`, `DROP_IN`, `AI.retarget_ratio`.
- **AI:** targets the nearest active enemy, sticky until another is closer than 0.7 x the current
  target's distance. With one enemy (offline) behaviour is identical.
- **Tests:** new suites `test_battle_mode.gd` and `test_ai_targeting.gd`, registered right before
  `test_updater.gd`. The wrapper `game/tests/run_settings_checks.sh` now isolates via `HOME` on macOS.

## 1. Local headless evidence (native macOS)

Owner's Mac (arm64), natively, not the Linux dev host and not a container. This is headless evidence,
kept separate from the CI (Linux) evidence in section 2.

Every direct Godot command ran as `HOME="$P/home" "$GODOT" ...`; the wrapper sets `HOME` itself.
`$GODOT --version` printed `4.7.2.stable.official.ed1daf0bf`.

**Baseline.** At `5800bb6` the wrapper gives `Tests: 4408 checks, 0 failures` on macOS. The earlier
3145 figure was for `d30be39`; `5800bb6` is one commit later and added suites.

**Task 1: wrapper on macOS.**

| | Result |
|---|---|
| RED (`HOME=/tmp/opencode/red-home bash game/tests/run_settings_checks.sh`, before the change) | `Guard rejection: OK`, then `Settings tests require isolated user data. Run: bash game/tests/run_settings_checks.sh`, exit 1 |
| GREEN (wrapper) | exit 0; `Guard rejection: OK`; `Tests: 4408 checks, 0 failures`; `Settings process probes: OK` |
| GREEN (`--self-test-failure`) | exit 1; `Tests: 4409 checks, 1 failures` |
| `find "$HOME/Library/Application Support/Godot" -newer /tmp/opencode/tortuga-marker -print` | no output: the real profile was untouched |

**Check counts per task** (wrapper, all suites, 0 failures each time):

| After | Checks |
|---|---|
| Baseline (`5800bb6`, Task 1 wrapper) | 4408 |
| Task 2: presets, `reset_battle`, drop-in | 4584 |
| Task 3: linger, reclaim, abandon, escape, result | 4663 |
| Task 4: nearest-sticky AI | 4684 |
| Task 5: determinism tape, group-preset battles | 4705 |

**Final controller run** (after Task 6's doc edits; no game code changed since Task 5):

| Command | Result |
|---|---|
| `bash game/tests/run_settings_checks.sh` | exit 0; `Guard rejection: OK`; `Tests: 4705 checks, 0 failures`; `Settings process probes: OK` |
| `bash game/tests/run_settings_checks.sh --self-test-failure` | exit 1; `Tests: 4706 checks, 1 failures` |
| `find "$HOME/Library/Application Support/Godot" -newer /tmp/opencode/tortuga-marker -print` | no output |
| `HOME="$P/home" perl -e 'alarm 120; exec @ARGV' "$GODOT" --headless --path game --quit-after 30 2>&1 \| grep -c "SCRIPT ERROR"` | `0` |

**Group-preset battles.** The Task 5 test fights each group preset to a result (captains join at
ticks 0, 300 and 900 and fire every 180 ticks; the AI commands the fleet). The full run printed:

```
brig_squadron: lost at tick 10663
frigate_escort: lost at tick 12515
```

Both are `lost`, with outcomes for captains 100, 101 and 102. The ticks are not pinned by any check;
they are the 0-based tick whose step set the result. The same values appeared in both full runs.

**Offline unchanged.** `git status --short -- game/tests` and `git diff --name-only -- game/tests`
(5800bb6 against the working tree) list only the wrapper (`run_settings_checks.sh`), `run_tests.gd`
(two suite registrations), `run_escape_witnesses.gd` (its `_matrix()` now skips `multiplayer_only`
presets) and the two new suites with their `.uid` files. No existing suite was edited, and all pass.

**Mutation checks** (each reverted and confirmed byte-identical):
- Task 2: dropping the `TYPE_INT` id check and qualifying every drop-in candidate gave 5 failures.
- Task 3: not neutralising lingering commands, accepting a second `linger`, and recording outcomes at
  the pre-step `elapsed` each failed checks (2, 1 and 8 failures). Removing the lingering branch from
  the per-captain escape pass failed 3 checks in `_test_linger_no_escape`.
- Task 4: leaving `commands_for_tick` unwired from the sticky target failed `sticky ticks`.

**Findings.**
- **Expected `ERROR` lines:** the deliberate ones only: `reset_battle` with `practice` / an unknown
  id, ops given offline, and the invalid `add_captain` / `linger` / `reclaim` / `abandon` / unknown
  / non-Dictionary ops. The ConfigFile parse error comes from the existing corrupt-settings probe.
- **Runtime errors inside a test** abort only that helper, so every `_test_*` in `test_battle_mode.gd`
  ends `return true` and `run()` checks `test.call(t) == true` for each.
- **Time:** the two group-preset battles add about 3.3 s to the wrapper run (about 23k ticks with the
  AI running every tick).
- **Self-hit:** on Task 5's tape, ship 100 is hit by its own shot at tick 421 after it leaves its
  owner's circle (`owner_cleared`) and the ship turns into it. This is Phase 2 behaviour, outside
  this plan; determinism holds either way.

## 2. CI evidence (Linux, GitHub Actions)

Pending until the owner pushes. After the push: the run URL, and the Test step's three lines
(`Guard rejection: OK`, `Tests: N checks, 0 failures`, `Settings process probes: OK`).

## Not verified

- **Plans 02 and 03.** Nothing networked, no server, no client views of battle mode.
- **Real display.** Nothing here draws; the offline views were not run for this plan.
- **Cross-platform tape equality.** Only same-process determinism is claimed: two sims given the same
  command+ops tape give identical checkpoints. The Linux CI run is not compared against macOS values.
- **The Linux wrapper path.** Task 1 changed the shared script; Linux behaviour is unchanged by
  construction (`HOME` is inert there) but not run locally. CI will prove it.
- **The stale escape witnesses.** `game/tests/run_escape_witnesses.gd` already failed before this plan
  (12 cases, 33 failures: stale fixture) and still does; this plan only kept its matrix offline-only.
- **Tape robustness.** Task 5's tape ops stay valid because of emergent AI behaviour (nearest-AI distances
  were 1200-1609 at the op ticks); retuning the AI could invalidate the membership assertion.
