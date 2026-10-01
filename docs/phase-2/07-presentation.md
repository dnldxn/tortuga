# Plan 07 — Combat presentation: runbook and verification

Issue: https://github.com/dnldxn/tortuga/issues/10 · Godot 4.7.2 stable, Compatibility renderer. This record covers the development-only Task 7 driver and the integrated checks; the other plan-07 implementation is present as uncommitted workspace changes.

## Setup and commands

From the repository root, use the pinned editor and isolated local profile:

```bash
export P="$HOME/.cache/tortuga-godot-4.7.2"
export XDG_DATA_HOME="$P/xdg/data" XDG_CONFIG_HOME="$P/xdg/config" XDG_CACHE_HOME="$P/xdg/cache"
export GODOT="$P/bin/Godot_v4.7.2-stable_linux.x86_64"
python3 game/tools/generate_audio.py --check
bash game/tests/run_settings_checks.sh
"$GODOT" --headless --path game --import
for case in two-enemies aim-cues conditions; do
  "$GODOT" --headless --path game --script res://tests/presentation_demo.gd -- --case="$case" --smoke
done
```

For a real-display pass (on macOS use the corresponding pinned 4.7.2 Godot executable), use each case at **both** window sizes; Space advances labelled snapshots and Escape quits:

```bash
"$GODOT" --path game --resolution 1280x720 --script res://tests/presentation_demo.gd -- --case=two-enemies
"$GODOT" --path game --resolution 1920x1080 --script res://tests/presentation_demo.gd -- --case=two-enemies
"$GODOT" --path game --resolution 1280x720 --script res://tests/presentation_demo.gd -- --case=aim-cues
"$GODOT" --path game --resolution 1920x1080 --script res://tests/presentation_demo.gd -- --case=aim-cues
"$GODOT" --path game --resolution 1280x720 --script res://tests/presentation_demo.gd -- --case=conditions
"$GODOT" --path game --resolution 1920x1080 --script res://tests/presentation_demo.gd -- --case=conditions
"$GODOT" --path game
```

The script instantiates `main.tscn`, uses its arena, HUD and audio, and disables automatic fixed steps while presenting synthetic snapshots. It has no release menu entry. Each snapshot starts from a fresh encounter; modifications are local fixture data, **not gameplay evidence**. Raw per-gun `shot` fixtures pass through `Presentation.normalize_events()` *for that snapshot/tick* before `combat_audio.consume()`, preserving one volley per ship/side/tick. The round/chain/grape hit snapshots include two same-track hits and advance presentation effects six ticks (not the simulation) so the aggregated `Hull/Sails/Crew −n` text is eligible for drawing. The corner fixture checks the true north and east indicator edges and nonoverlapping boxes. Unknown `--case` fails with exit 1. Headless `--smoke` walks every snapshot and checks the most important identities/aim/indicator/event properties without claiming pixels or audible playback.

| Case | Snapshots | Inspect |
|---|---:|---|
| `two-enemies` | 5 | near, far, same east edge, adjacent corner, A disabled with both reasons while B stays B |
| `aim-cues` | 6 | both sides assisted, both empty with surviving brackets, outside arc, out of range, no active enemy, practice Target |
| `conditions` | 8 | full/49%/24% hull and sails with round/chain/grape impact examples, sails-only/crew-only/both disable, sunk, missed-shot splash |

## Recorded automated checks

See [the evidence log](../research/evidence/phase-2/07-presentation.md) for dated command output, check counts and any warnings. Numeric/logic checks do not establish native rendering or sound quality. The production controller consumes each tick's normalized audio and visuals before entering result mode; `combat_audio.clear()` on result entry stops effects **including any decisive-tick impact/cannon**. This is the current native tradeoff, not proof that a terminal hit sounds right. The owner should explicitly listen to a decisive hit and decide whether this cut is acceptable.

Audio source consists of four original generated WAVs, six bounded effects voices plus one looping sea voice, and a maximum of 48 visual effect records. Source WAV byte total, hashes and CC0-1.0 owner-authorized dedication are recorded in `game/assets/ATTRIBUTION.md` and `game/assets/audio/LICENSE.txt`; source bytes are not packaged footprint. No third-party sample or invented device credit is used.

## Native gates — blocked on this headless host

**Owner action:** run the six real-display fixture commands and the playable `"$GODOT" --path game` command on the owner's macOS display with a physical audio output; record actual machine/OS/build/device, display size, logical canvas and screenshot dimensions, observations and defects in the linked evidence log. Check fullscreen/windowed at both sizes, grayscale legibility, A/B marker separation, 33×16.5 logical-pixel minimum sloop footprint (length × width), bow and intact/reefed/damaged sails at representative headings, ammo/independent sides/remapped prompts, all reason text, HUD overlap, and 30 seconds of moving near/far framing. A smaller physical panel showing a 1920×1080 window does not prove native 1080p.

Play a frigate against two sloops with real commands (wind, maneuver, both broadsides, partial/empty volleys, ammo cycles, aim/off-arc/out-of-range, A defeat without B renaming, zoom floor/markers); reset practice to inspect all tracks and complete an outcome/replay. Practice target has ordinary contact separation and no propulsion. Confirm escape rule/progress stays visible. Fixture-only edits cannot satisfy this gate.

Listen on a named physical output to cannon, ship impact, missed-shot splash, at least three sea wraps and simultaneous volleys. Check clipping/clicking/masking and the decisive-tick sound cut; pause/focus-loss silences, focus-in alone stays paused, explicit resume resumes sea without stale effects, replay starts one sea voice. Use Settings → Apply → Back → explicit Resume to check Master 0 (all silent), Effects 0 (sea only), Ambient 0 (effects only), draft-only changes, and restored 1/.8/.35 across a fresh process. Capture actual observations, not inferred passes.

Plan 08 still owns packaged builds and sizes, sustained Intel 1080p budgets/frame pacing, three-platform native checks, newcomer use and owner tactical acceptance. Recheck presentation in the final packages.
