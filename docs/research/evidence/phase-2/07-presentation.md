# Plan 07 presentation — evidence log

Issue: https://github.com/dnldxn/tortuga/issues/10 · Task 7. Source workspace includes uncommitted tasks 1–6; no commit/build ID is claimed for these changes. Engine pinned: Godot 4.7.2 stable, Compatibility renderer. Linux development host is headless; there is no available X11/Wayland/native audio listening result here.

## Headless / automated (2026-10-01)

| Command / check | Result |
|---|---|
| `"$GODOT" --headless --path game --script res://tests/presentation_demo.gd -- --case=two-enemies --smoke` | 5 labelled snapshots visited, 0 fixture failures; exit 0; true corner edges checked north/east |
| Same command with `--case=aim-cues --smoke` | 6 labelled snapshots visited, 0 fixture failures; exit 0 |
| Same command with `--case=conditions --smoke` | 8 labelled snapshots visited, 0 fixture failures; exit 0; Hull −16, Sails −12 and Crew −10 aggregated damage cues checked settled and live after six visual-only ticks |
| `python3 game/tools/generate_audio.py --check` | `audio assets: 4 verified`, exit 0; four source WAVs total 419,126 bytes (`du -cb`) |
| `GODOT="$HOME/.cache/tortuga-godot-4.7.2/bin/Godot_v4.7.2-stable_linux.x86_64" bash game/tests/run_settings_checks.sh` | Guard rejection OK; 3037 registered-suite checks, 0 failures; six fresh-process probes: write 7, read 13, corrupt 2, fallback 8, restore 1, read-defaults 14 checks, each 0 failures; wrapper exit 0 |
| `GODOT=... bash game/tests/run_settings_checks.sh --self-test-failure` | 3038 checks, deliberate 1 failure, wrapper exit 1; probes did not run |
| `"$GODOT" --headless --path game --import` | Editor import exited 0 |
| Unknown case, `--case=unknown --smoke` | Godot prints unknown-case error; exit 1 confirmed by shell check |
| `git diff --check` | exit 0 |

**2026-10-01 follow-up:** initial smoke captures `/tmp/opencode/tortuga-p07-before-conditions.log` and `/tmp/opencode/tortuga-p07-before-two-verbose.log` reported leaked `AudioStreamWAV`/`AudioStreamPlaybackWAV` objects (conditions also held `splash.wav` at exit). The demo now calls existing `combat_audio.clear()` on smoke teardown, asserts stopped voices, and waits ten SceneTree frames after queueing the scene free. The suite had three headless WAV instances at immediate process exit; an isolated presentation suite probe still leaked after 1–4 post-suite frames but not after ten. The runner now allows ten frames for stopped playback cleanup before exit; the wrapper's deliberate-failure exit was retested. Captured final output `/tmp/opencode/tortuga-p07-final-{two,aim,conditions}.log` and `/tmp/opencode/tortuga-p07-suite-after-drain.log` contains **no exit-time leak/resource warnings**. This verifies these headless invocations only; it does not establish engine-wide leak freedom. Existing invalid-ID/bad-config ERROR lines in the wrapper are expected negative-test output. Headless snapshots check structure and data paths only. They do **not** validate visible pixels, click-free sea loops, hearing any effect, a physical 1080p panel, game reachability or player understanding. No screenshots or listening notes were produced by these checks.

## Native rendered / human / audio — BLOCKED; owner action required

Owner: run all six resolution/case combinations and the playable encounter on a real-display Mac using [the runbook](../../../phase-2/07-presentation.md); attach genuine screenshots at both actual display resolutions and grayscale crops. Record monitor native resolution, windowed/fullscreen dimensions, 1280×720 logical canvas, zoom/readability/overlap, bow/sail identification at minimum zoom and 30-second framing observations. Do not label a scaled smaller monitor as native 1080p.

| Build SHA / Godot / OS / GPU / tester / date | Physical display & screenshot dimensions | Case, snapshot/play action and observation | Outcome / defect |
|---|---|---|---|
| Pending owner real-display pass | Not observed | All fixture cases + playable frigate/two-sloop and practice paths | Blocked |

Owner: record named physical audio device/listener, actual volume settings and heard/unheard result for cannon, impact, splash and at least three sea wraps; simultaneous volleys, decisive hit transition, pause/focus/explicit resume, replay, and Master/Effects/Ambient zero/draft/apply/restore. In the current controller, result entry clears sound immediately after consuming decisive-tick events: a terminal impact may be cut; listen and record whether that tradeoff is acceptable. Bus routing/dispatch counters cannot stand in for listening.

| Build / OS / output device / listener / date | Sound or settings sequence | Observation (including wrap/click/overlap) | Outcome / defect |
|---|---|---|---|
| Pending owner physical-device listening | Not observed | No listening evidence collected | Blocked |

Owner-approved CC0-1.0 authorization for the original generated audio is recorded in `game/assets/ATTRIBUTION.md` and its license file. No device, screenshot, measured quality or packaged footprint is asserted by this log.
