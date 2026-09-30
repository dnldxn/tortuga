# Plan 04 escape witnesses — evidence

- Build: base commit `c0816f9` plus the plan 04 working tree (see the commit that adds this file).
- Engine: Godot 4.7.2.stable.official.ed1daf0bf, headless on Linux.
- Constants: arm 900, clear 1400 (strict), 8.0 s = 480 ticks at dt 1/60.
- Command: `"$GODOT" --headless --path game --script res://tests/run_escape_witnesses.gd`, which exits 0.
- Fixture: `game/tests/fixtures/escape_witnesses.json`. It contains 9 cases of player
  commands only. `turn` holds until it is replaced; booleans are one-tick edges.

## How the traces were found

A throwaway exploration script (not committed) played the player's side against the real
sim and the real `AIController` from an ordinary reset, and recorded the commands it
issued. The tactic in every cell:

1. **Engage:** cycle both sides to chain. Orbit the pursuer at a broadside radius of ~420.
   Fire a side only when aim assist has a target, and only if the pursuer's sails would
   still stay ≥ 8 after this volley plus any chain shot already in flight. This means the
   pursuer is never disabled.
2. **Flee:** once the pursuer's maximum speed after pending damage falls below 0.7–1.0×
   the player's (depending on the cell; see below), set full sails. Each tick, steer
   toward the best of 32 headings, scored by predicted distance from the pursuer 6 s
   ahead, with a penalty for passing within 260 of the safe bounds and for large course
   changes. Steering uses full ±1 turn.

The committed runner independently replays the stored commands from reset, with the AI
on the same pre-step call path as `main.advance_tick()`. No state is edited, there is no
teleporting and no pre-damage.

## Results (runner output, repeated twice per case with identical metrics)

| Duel / player | Flee ratio | Armed tick | Escaped tick (s) | Final-interval min distance | Player h/s/c | Enemy h/s/c |
|---|---|---|---|---|---|---|
| sloop / sloop | 0.85 | 35 | 4047 (67.5) | 1401.1 | 68/70/60 | 100/46/60 |
| sloop / brig | 0.7 | 41 | 2775 (46.3) | 1400.7 | 160/100/90 | 100/22/60 |
| sloop / frigate | 1.0 | 49 | 9938 (165.7) | 1400.2 | 104/140/140 | 100/16/60 |
| brig / sloop | 0.85 | 21 | 3168 (52.8) | 1400.3 | 100/70/60 | 160/100/90 |
| brig / brig | 0.7 | 24 | 9794 (163.3) | 1401.0 | 112/100/90 | 160/52/90 |
| brig / frigate | 0.7 | 27 | 4447 (74.1) | 1400.7 | 240/140/140 | 160/28/90 |
| frigate / sloop | 0.7 | 31 | 1316 (21.9) | 1400.1 | 100/70/60 | 240/140/140 |
| frigate / brig | 0.7 | 35 | 5111 (85.2) | 1400.3 | 160/100/90 | 240/104/140 |
| frigate / frigate | 0.7 | 41 | 4157 (69.3) | 1400.5 | 48/140/140 | 240/50/140 |

Routes, from a replay of the fixture traces. "Off-downwind" is the player heading
relative to the wind, where 0° is dead downwind and 180° is into the wind. The mean is
taken over ticks with countdown progress. The duel wind is 0 (east), or π/4 in the
frigate duel. "Wall ticks" counts ticks the player spent within 150 of its safe bounds.

| Duel / player | Player chain volleys | Mean / final off-downwind | Wall ticks | Escape position |
|---|---|---|---|---|
| sloop / sloop | 1 | 96° / 112° | 185 | (2951, 3184) |
| sloop / brig | 5 | 69° / 77° | 469 | (5394, 1959) |
| sloop / frigate | 11 | 92° / 92° | 0 | (3869, 1424) |
| brig / sloop | 0 | 90° / 122° | 0 | (5022, 3245) |
| brig / brig | 5 | 92° / 92° | 1105 | (2082, 1612) |
| brig / frigate | 7 | 94° / 120° | 555 | (5517, 3413) |
| frigate / sloop | 0 | 132° / 156° | 0 | (677, 3541) |
| frigate / brig | 15 | 133° / 133° | 1286 | (5553, 973) |
| frigate / frigate | 15 | 87° / 99° | 987 | (5303, 2238) |

What the routes show:

- Most final runs are on a beam reach (~90° off the wind). That keeps the wind
  multiplier near 0.95 while opening distance sideways from the pursuer.
- Six cells ran along or turned at an edge. The heading scorer's 260-unit wall penalty
  steered them back inward.
- Faster player ships (brig/sloop and frigate/sloop) fired no volleys at all.

Every case ended `escaped` with one operational enemy and positive player tracks. Every
per-tick nearest-enemy sample in the final 480-tick interval was > 1400.

Observations:

- Final-interval minimums sit just above 1400. The countdown only survives once the
  pursuer's closing speed has dropped, so completion happens right at the edge.
- The sloop-duel/frigate and brig/brig cells take ~2.7 minutes. They need repeated chain
  volleys, and some attempts fail and restart the countdown.
- Where the player is already faster, the pursuer's sails stay untouched and the escape
  is a pure outrun (brig/sloop, frigate/sloop).

Failures and reruns: the first exploration pass used a latched engage→flee switch at a
fixed 0.7 ratio. It got 7/9: sloop duel/frigate was defeated at 156 s, and brig/brig
timed out hovering at ~590. Two changes followed: the switch was made non-latching (fall
back to engaging when the pursuer recovers relative speed), and a small grid was searched
per cell (orbit 420/520/300 × ratio 0.7/0.85/1.0/0.55 × reserve 8/14/3). The first
succeeding setting was kept, giving 9/9. No simulation constants changed.

## Rendered gameplay

Owner report, 2026-09-30: the features were validated on the v0.1 plan-04 macOS build
(`93fbcfc`). No details were supplied on which combinations were played, which tactics
were used, or how play differed from the scripted routes.
