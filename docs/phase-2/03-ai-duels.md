# Plan 03 — Replayable AI duels: verification record

Issue: https://github.com/dnldxn/tortuga/issues/6
Spec: https://github.com/dnldxn/tortuga/issues/3 (Design §§2, 5–8)
Engine: Godot 4.7.2 stable (Compatibility renderer), `GODOT` = verified absolute editor path.

## Commands

From repository root with `$GODOT` the verified 4.7.2 editor binary (before plan 06
lands, the raw harness is canonical):

```bash
"$GODOT" --version
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --script res://tests/run_tests.gd
"$GODOT" --path game   # playable demo
```

## Automated results (2026-09-30, Linux headless)

| Check | Result |
|---|---|
| `--version` | 4.7.2.stable.official.ed1daf0bf |
| `--import` | exit 0, no parse/resource errors |
| Full harness before plan 06 wrapper | **1465 checks, 0 failures**, both new suites (`test_ai_duels.gd`, `test_duel_ui.gd`) included |
| Upstream suites (sailing/contact/controller/view/weapons/projectile/practice) | green throughout |

Suite additions: `test_ai_duels.gd` (reset matrix, observation/AI purity, steering,
ammo hysteresis/cycling, fire gating, avoidance/recovery, combat results, nine
lifecycles with two-run checkpoint equality, replay-after-result, AI-vs-AI
diagnostics) and `test_duel_ui.gd` (selection→duel→result→replay/return wiring,
enemy HUD block, input isolation, pause freezing). `test_contact.gd` fixtures were
updated for the new terminal-no-op contract: a resolved `result` now freezes
`step()` (plan 03 task 5); the old "result marker survives stepping" fixtures clear
the marker before stepping and assert the new freeze behavior separately.

## Nine-lifecycle matrix (3600-tick deterministic tape)

Tape: player turn +0.5 for 240 ticks then neutral, both sides fired every 60 ticks,
AI opposition live. Two runs per pair; checkpoints every 60 ticks compared equal.

| Preset / vessel | Automated reset/outcome/replay | Outcome under tape | Notes |
|---|---|---|---|
| duel_sloop / sloop | pass (identical runs) | no result at 60s, both hulls full | smoke need not win |
| duel_sloop / brig | pass (identical runs) | defeat at 47.9s | tape player defeated |
| duel_sloop / frigate | pass (identical runs) | no result at 60s (player hull 72) | — |
| duel_brig / sloop | pass (identical runs) | no result at 60s | — |
| duel_brig / brig | pass (identical runs) | no result at 60s (player hull 112) | — |
| duel_brig / frigate | pass (identical runs) | no result at 60s | — |
| duel_frigate / sloop | pass (identical runs) | no result at 60s | — |
| duel_frigate / brig | pass (identical runs) | no result at 60s (player hull 160, enemy 224) | — |
| duel_frigate / frigate | pass (identical runs) | no result at 60s (enemy hull 192) | — |

Replay-after-result: every pair resolved (tape or lethal fixture), reset equals a
freshly reset sim exactly (IDs/spawns/wind, full tracks, side ammo/loads, elapsed 0,
empty events/projectiles/result), and the reset controller's next 120 commands match
a fresh controller (no hidden memory leakage).

## Matching-vessel AI-vs-AI diagnostics (up to 240 simulated seconds)

Test-only mirror: a second AI instance observes IDs/teams swapped and its ship-2
command maps back to player 1. No production autopilot exists.

| Pair | First firing opportunity | Contacts / wall pins ≥12s | Outcome |
|---|---|---|---|
| duel_sloop / sloop | tick 163 (2.7s) | none (worst 0 ticks) | victory at 111.6s |
| duel_brig / brig | tick 142 (2.4s) | none (worst 0 ticks) | draw at 44.5s |
| duel_frigate / frigate | tick 216 (3.6s) | none (worst 0 ticks) | victory at 45.8s |

No passive orbiting observed: all three pairs resolved well inside 240s with active
firing from the opening minutes. 2–4 minute comparable-vessel duels remain a
new-player tuning target, not a forced timer; no timer was added.

## Playable demo (rendered evidence)

**Not yet executed on this headless Linux box.** The commands are recorded above;
the owner must run `"$GODOT" --path game` at 1280×720 (and 1920×1080) on a
display-capable machine to verify: broadside maneuvering, readable enemy
condition/distance, opponent maneuver/return fire, projectile misses, ordinary
win/loss reasons, keyboard and mouse replay, all nine combinations, off-screen edge
arrow, pause/focus behavior, and recorded screenshots/observations. Headless
success cannot establish rendered usability — this table stays open until then.

| Build / Godot version | Vessel / ammo | Resolution | Tester / machine | Observed result / failures |
|---|---|---|---|---|
| — | — | — | — | pending owner play |

## Tuning notes

All AI values are initial, unmeasured (centralized in `Definitions.AI`): orbit radii
520/380/190, radial gain 160, turn dead band 3°, reef 35°/full-sail 15°, ammo
hysteresis 1.0s candidate + 10.0s switch cooldown, avoidance look-ahead 0.75s,
ship clearance 60, boundary inset 50 (tested against 0.75s predicted position), stuck
8 units/1s above speed 20, recovery minimum 1.5s, exit separation 100.
Damaged crews reload slower than the dwell; watch for wasteful resets and tune
with evidence. Practice and plan-02 behavior is untouched; plan 04 adds escape
resolution at the same `_resolve_combat_result` seam; plan 05 extends the shared
avoidance path to allies and a second enemy without a second algorithm.
