# Plan 04 — Deliberate escape: runbook and verification record

Issue: https://github.com/dnldxn/tortuga/issues/7
Spec: https://github.com/dnldxn/tortuga/issues/3 (§§2–3, 5, 8–9)
Engine: Godot 4.7.2 stable (Compatibility renderer), `$GODOT` = verified absolute editor path.
Evidence: `docs/research/evidence/phase-2/04-escape.md`.

## Rule (constants in `game/sim/definitions.gd`)

| Constant | Value | Meaning |
|---|---|---|
| `ESCAPE_ARM_DISTANCE` | 900 | Arms once ship centers are `<=` 900 from ANY active enemy (no hit/shot needed). |
| `ESCAPE_DISTANCE` | 1400 | Progress only while `>` 1400 from EVERY active enemy. Equality resets. Greater than the longest gun range (round 900). |
| `ESCAPE_SECONDS` | 8.0 | 480 consecutive fixed 1/60 s steps complete the escape. |

State lives in the sim (`escape_armed`, `escape_clear_ticks`); `reset()` clears both.
`_update_escape()` runs after `_resolve_combat_result()` in `step()`, so victory, defeat
and draw on the same tick take precedence. Practice never arms, never counts and never
produces a result. Inactive ships are ignored for both arming and blocking. The result is
`{outcome: "escaped", reason: "pursuit_broken", elapsed, defeated}`. `defeated` uses the
same sorted helper as combat results.

Geometry: the arena is 6000×4200. Safe centers are x∈[160+r, 5840−r] and
y∈[160+r, 4040−r], with radii 22/28/34. The duels start 1000 apart and unarmed:
sloop (2500,2100)/0 vs (3500,2100)/π with wind 0; brig (3000,1500)/π/2 vs
(3000,2500)/−π/2 with wind 0; frigate uses the sloop positions with wind π/4.

## Presentation

- HUD: a new top-centre panel, shown in duels, with a rule line, a status line and a
  countdown bar. The states are unarmed, armed, counting ("Breaking pursuit: x / 8.0 s —
  nearest enemy N"), reset ("Pursuit resumed — progress reset; escape remains armed.")
  and practice ("Escape unavailable…"). Text is derived from sim state, and rounded
  numbers are display only.
- Pause menu (duels): adds the tactical hint (chain shot, sails above zero, wind/open
  sea), with prompts built from the live bindings. There is no escape hotkey.
- Result menu: title "Escaped" plus the reason line "Escaped — you broke pursuit while an
  opponent remained operational." Replay and return use the existing actions.

## Commands (repo root, before plan 06)

```bash
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --script res://tests/run_tests.gd
"$GODOT" --headless --path game --script res://tests/run_escape_witnesses.gd
"$GODOT" --path game   # real display only
```

After plan 06 lands, replace the full-suite command with `bash game/tests/run_settings_checks.sh`.
The witness runner is separate and does no settings I/O. After plan 05, the same runner
and fixture must cover 12/12 cases. The runner derives the matrix from `PRESETS`, so the
new preset makes it demand three more cases automatically.

## Automated results (2026-09-30, Linux headless, base c0816f9 + working tree)

| Check | Result |
|---|---|
| `--import` | exit 0 |
| Full harness | **1622 checks, 0 failures**, exit 0 (baseline before plan 04: 1512) |
| `-- --self-test-failure` | 1623 checks, 1 failure, exit 1 (runner sanity) |
| `test_escape.gd` with `_update_escape` call removed | 26 failures, exit 1 (suite detects missing behavior) |
| `--quit-after 30` smoke | exit 0, no errors |
| Escape witnesses | **9/9 escaped**, each replayed twice from reset with identical metrics, exit 0 |
| Witness runner negative checks | truncated `max_ticks`, missing case, non-increasing tick, and tick ≥ `max_ticks` each exit 1 |

`test_escape.gd` covers:

- Arming boundaries: 900.001 / 900 / 899.999.
- Clearance boundaries: 1399.999 / 1400 / 1400.001.
- Countdown: no result at 479 ticks, escaped at 480.
- Interruption: progress resets and arming persists.
- Arming and blocking by ANY enemy, and clearance from EVERY enemy, in both insertion orders.
- Inactive ships, inactive player, no enemies and existing results.
- Practice: approach/depart, target defeat and reset.
- Real-step precedence with 479 ticks already counted: victory by hull/sails/crew,
  sunk-first classification, defeat, draw, escape.
- Freeze after an escape.
- Three-ship case: a pursuer resets progress, and defeating it restarts progress at 1, not 479.
- Reset equality across all 9 combinations, after partial progress and after escape,
  plus changed-selection and practice resets.
- Pause: 10 s of controller ticks leave everything frozen; focus loss pauses; focus
  return stays paused; resume replays no buffered edges.
- Headless HUD/result/pause text wiring.

## Tuning

No tuning was needed: all nine routes succeed with the initial constants. Vessel, ammo,
AI and arena values are untouched. Per the owner (2026-09-30), escape constants may be
tuned freely, but any other tuning must go back to the owner with evidence.

## Rendered / owner verification

Headless runs cannot verify readability or playability. The checklist for a real display:

- Every HUD state and the result/replay flow at 1280×720 and 1920×1080. Check in
  particular that the 520 px top-centre panel does not collide with the corner panels
  at 1280.
- A playable demo: unarmed start → approach within 900 → chain the pursuer without
  disabling it → leave beyond 1400 → watch progress → re-engage to see the reset →
  escape.
- Keyboard and mouse replay/return.
- Pause and focus loss mid-countdown.
- Practice shows no escape.
- All nine tactics with ordinary controls, and the owner's feedback on understanding.

| Build / Godot | Combination(s) | Resolution | Tester / machine | Observations |
|---|---|---|---|---|
| v0.1 plan-04 macOS archive (`93fbcfc`, SHA-256 `3cc1ac1e…ca37797`) / Godot 4.7.2 | Not specified | Not specified | Project owner / Mac (details not specified) | Features validated; individual observations not supplied |

**Owner report, 2026-09-30:** The features were validated on the v0.1 plan-04 macOS
build. This confirms a native real-display run. The owner did not provide per-combination
observations, resolutions, machine details, tactics or screenshots, so those fields remain
open.

This record makes no claim about native runtime, enjoyment or learnability, and does not
claim Phase 2 completion. Plan 08 keeps the newcomer, packaged-build and performance
acceptance.
