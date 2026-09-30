# Broadside target practice — demo and evidence

This is the plan 02 playable increment, not full Phase 2 acceptance. Record actual results below after executing each check. Numeric weapon values are starting tuning, not measured balance.

## macOS test archive

The owner requested replacement of the earlier `v0.1` sailing-playground tag/release with
this plan-02 build. Download `Tortuga-v0.1-macos.zip` from the GitHub `v0.1` release, unzip it,
and launch `Tortuga.app` on a Mac. The Linux Godot 4.7.2 export completed and its ZIP passed
`unzip -t`. SHA-256: `3a3313478d79ff4ab3db2a974c712af0ce88a2e8aa4f9976c0e120d258500823`.
The export check alone did not constitute a native macOS or rendered test; the owner later
reported that the features were validated on macOS (see the record below). The original
plan-01 archive
(SHA-256 `5d69a9c3840b19f21cb5a601b66d924c373602872545a7b971caf7cc2ec8932f`)
was the one the owner previously tested on macOS; it is not the current download.

## Automated logic checks

From repository root, set `GODOT` to the verified Godot 4.7.2 editor binary, then run:

```bash
"$GODOT" --version
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --script res://tests/run_tests.gd
```

After plan 06 changes the test entry point, use `bash game/tests/run_settings_checks.sh` instead of the raw harness.

- [x] Version verified: `4.7.2.stable.official.ed1daf0bf` on Linux x86_64, 2026-09-30.
- [x] Import completed without script errors, exit 0.
- [x] Seven registered suites: **1057 checks, 0 failures**, exit 0. The two logged invalid-ID errors are expected rejection fixtures.
- [x] Harness failure self-test: **1058 checks, 1 deliberate failure**, exit 1; headless main scene `--quit-after 30`: exit 0.
- [x] Weapon, projectile, contact, practice reset, controller and view seams reviewed. These checks do not prove native key delivery or rendered clarity.

## Rendered/playable checks — macOS owner report

Launch `"$GODOT" --path game`. Choose **Target practice** and each vessel, first by keyboard, then by mouse. Use the on-screen bindings; the target initially lies due east, outside both broadsides. Turn to acquire it, fire, and inspect projectile travel, muzzle/hit/splash cues, target condition and gun reload progress. Fire a partial volley, compare the other side, cycle one side, and try firing with no loaded guns and firing without aim assist. Reset while shots travel; verify there are no ghost impacts.

For every vessel, sink the brig using Round (hull), disable sails using Chain and disable crew using Grape. Check that the practice session stays open after defeat and the defeated target no longer blocks sailing. Pause during flight/reload, press fire/cycle/reset while paused, and confirm nothing advances or defers; after focus loss, explicitly resume. Test pause restart/return. At **1280×720** and **1920×1080**, inspect all text, corner panels, both range arcs, the on/offscreen target markers, and mouse/keyboard menu access.

- [ ] Keyboard and mouse selection, pause menu, focus/resume: ____
- [ ] All three vessels and three ammo defeat routes: ____
- [ ] Independent sides, partial volley, feedback, reset-in-flight: ____
- [ ] Pause freezes effects; offscreen marker points toward target: ____
- [ ] Both resolutions: readable without hiding the gameplay center: ____

**Owner report, 2026-09-30:** The features were validated on macOS. This confirms a native
real-display run of the plan-02 build; the owner did not provide per-scenario observations,
resolution, machine details, or a breakdown of the checks above, so those fields remain open.

| Build / Godot version | Vessel / ammo | Resolution | Tester / machine | Observed result / failures |
|---|---|---|---|---|
| v0.1 plan-02 macOS archive / Godot 4.7.2 | Not specified | Not specified | Project owner / Mac (details not specified) | Features validated on macOS; individual observations not supplied |
| Pending | Pending | 1280×720 | Pending | Pending |
| Pending | Pending | 1920×1080 | Pending | Pending |

## Tuning evidence

Before changing a value in `game/sim/definitions.gd`, record the starting value, scenario, and observed issue. After the change, replay the same scenario and log the result. Leave blank if no tuning is performed.

| Scenario / vessel / ammo | Before value and observation | After value and observation | Tester / build |
|---|---|---|---|
| Pending | Pending | Pending | Pending |

Plan 03 consumes `weapons`, `aim_for`, projectile/event records and `defeat_reasons` with damage resolved after same-tick firing. Plan 07 owns further presentation polish. Full duel balance, three-platform native packages and broad Phase 2 acceptance remain later gates.
