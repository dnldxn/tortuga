# Issue 19 — Visual and audio polish verification

[Approved issue](https://github.com/dnldxn/tortuga/issues/19), implemented 2026-10-02 against `d30be39`, Godot **4.7.2.stable.official.ed1daf0bf**, Compatibility renderer. Working-tree implementation; no publication implied. Base ID remains `ac7791a8f2059d83`. Combat movement, shot launch ticks, damage, gun counts and reload rules remain authoritative in the simulation. Cosmetic arcs select one reference at launch, never home or alter collisions. Current art matches 4/6/8 barrels per broadside; cannon reports dispatch per shot.

## Automated evidence and reproduction

On the repository's configured Linux toolchain, use the absolute pinned `GODOT` and isolated XDG profile described in [the sailing runbook](sailing-playground.md):

```bash
bash game/tests/run_settings_checks.sh
bash game/tests/run_settings_checks.sh --self-test-failure # expected exit 1
python3 game/tools/generate_audio.py --check
python3 game/tests/test_generate_audio.py
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --quit-after 30
bash tools/build_release.sh 0.999 build/phase-2/release
```

The host for this implementation was macOS on Apple M5 (10 cores, 32 GB), rather than the historical headless Linux host. The unmodified Linux settings wrapper correctly rejected macOS user-data placement. Actual test invocation was `/private/tmp/tortuga-19/run-macos-checks > /private/tmp/tortuga-19/task-1-long-prompts-tests.log 2>&1`: **4,408 checks, zero failures, all six settings process probes pass**. Baseline: 3,145/0; intermediate task 1: 3,260/0; task 2: 3,996/0; task 3: 4,399/0. These are full suite counts, not additive counts.

The temporary runner copied `game/`, removed the Linux-only `/tmp/opencode` sentinel, changed temporary roots to `~/Library/Application Support/TortugaIssue19Tests.XXXXXX`, and adapted the guard probe path. `/private/tmp/tortuga-19/godot-isolated` wrote only the copied game's `override.cfg` for a custom isolated user directory and executed the pinned portable editor. It did not change HOME, product `project.godot`, or real Tortuga settings. The tests still exercised the source wrapper's process probes and isolation guard. This is an adapted macOS run, not evidence that the unmodified Linux wrapper succeeds on macOS.

`python3 game/tools/generate_audio.py --check` verified four assets; `python3 game/tests/test_generate_audio.py` passed two tests. Registered suites exercise stable roster/bounds at minimum, 1080p and wider/taller canvases; legal long remaps/notices; partial readiness and ammo/crew changes; indexed muzzle positions at headings and sail states; arc lane entry, ties, near-zero and no-target cases; early/same-tick hit, range expiry and resets; 24/32-shot dispatch and 64 overlapping cannon tails; pause/focus/result/replay/settings isolation; 240 enabled/disabled simulation checkpoints. Expected invalid-ID diagnostics and existing engine shutdown resource warnings are distinct from suite failures. Repeated encounter/reset assertions check bounded state cleanup; they do not certify sustained process RSS stability.

Final full-suite rerun after the shot-only view-sync guard again passed 4,408/0 plus all six settings process probes. Final deliberate-failure invocation returned expected exit 1: 4,409 checks and one deliberate failure (`final-deliberate-failure.log`); four ObjectDB teardown warnings remained. Final import rerun outside the sandbox returned exit 0 without errors/warnings; the earlier sandbox CA-certificate warning was unrelated to assets. Real main-scene headless smoke returned exit 0 cleanly (`final-main-smoke.log`). Demo smoke visited 5 `two-enemies` and 8 `conditions` snapshots with zero failures. Final release build returned exit 0 (`final-release-build.log`), producing seven assets. Exports do not establish platform runtime acceptance.

## Native capture evidence

Native renderer reported OpenGL API 4.1 Metal 90.5, Apple M5 Compatibility. Capture windows and logical canvases were 1280×720; screen scale 2, framebuffer 3420×2214. The 1080p timing window was physical 1920×1080 with logical 1280×720 (`canvas_items` scaling). These were scripted synthetic encounter snapshots using real game views, not owner gameplay or release runtime evidence. Audio used **Dummy**. Enumerating MacBook Air Speakers at 48 kHz does not establish listening through that output.

[Compact evidence manifest](evidence/19/manifest.json) records original PNG SHA-256, destination SHA-256, dimensions and bytes. Fifteen images total **2,259,033 bytes**, converted with bundled Pillow to RGB JPEG, quality 82, optimized, without resizing/retouching; they are documentation assets outside the game export. Original captures were `/private/tmp/tortuga-19/{before,after-models,after-hud,after-fx}/`. Scripts were `capture.gd`, `menu-capture.gd` and the effects capture harness in that temporary directory. Log provenance: `baseline-native.log`, `models-native.log`, `hud-native.log`, `menu-native-fixed.log`, `fx-native.log`. Full/reefed captures of all three ships exist in the original set; compact representatives retain full-sail views.

| Evidence | Baseline | Refined |
|---|---|---|
| Sloop and HUD | [before](evidence/19/before-sloop-full.jpg) | [after](evidence/19/after-models-sloop-full.jpg) |
| Brig and HUD | [before](evidence/19/before-brig-full.jpg) | [after](evidence/19/after-models-brig-full.jpg) |
| Frigate and HUD | [before](evidence/19/before-frigate-full.jpg) | [after](evidence/19/after-models-frigate-full.jpg) |

[Pause](evidence/19/after-hud-pause.jpg), [selection notices](evidence/19/after-hud-selection-notices.jpg), [settings](evidence/19/after-hud-settings.jpg), [result](evidence/19/after-hud-result.jpg), [muzzle puffs](evidence/19/after-fx-round-muzzles.jpg), and [round](evidence/19/after-fx-round-flight.jpg)/[chain](evidence/19/after-fx-chain-flight.jpg)/[grape](evidence/19/after-fx-grape-flight.jpg) provide reviewable examples. Baseline HUD clipped offscreen; corrected snapshots show the top roster and lower panels. Native capture found root sizing and pause-layer overlap defects, subsequently fixed and regression-checked. Long-remap capture initially exposed a one-pixel overlap and was corrected in code/tests. The [confirmed unpaused recapture](evidence/19/after-fx-long-prompts.jpg) shows legal remaps plus LOAD/RESET, empty-ammo and escape guidance; prompt panels start at y=566 and navigation at y=543, below combat viewport bottom y=536. Scripted captures establish that the renderer produced these pixels, not that ship-detail or sound quality meets owner acceptance.

## Asset provenance and sizes

[Attribution](../../game/assets/ATTRIBUTION.md) and adjacent license files retain exact ownership/license notices. No reference-image assets were copied. Headings use a licensed compact DejaVu Serif Latin subset (**37,740 bytes**, versus original subset 28,096, +9,644). Final font embeds the full permission/license in name-table ID 13; only name/head tables changed and every glyph table remained unchanged. The [font metadata verification](evidence/19/task-1-font-license-verification.json) records this. Loading the final macOS content pack yielded a `FontFile.data` exactly equal to the entire source TTF (37,740 bytes; `final-export-font.log`, exit 0), establishing that the embedded license ships with the font. The adjacent text notice remains source provenance. Ornaments, ammunition sprites and smoke are native procedural drawing. Representative GLBs are original AI-assisted procedural Tortuga models generated from `shipyard-gallery/dist/ship-models.js` by `shipyard-gallery/scripts/export-game-models.mjs`. Combined GLB bytes: **1,340,448 → 1,452,188 (+111,740)**; renderable mesh counts remain 26/47/52.

Cannon is **original deterministic procedural synthesis**, not a recording or third-party sample: seed 707, mono 16-bit PCM, 22,050 Hz, 0.65 s, 28,708 bytes. Broadband ignition crack, filtered turbulent pressure/rumble, falling resonances and two short diffuse reflections; DC removal precedes endpoint fades and peak normalization to 0.8. `python3 game/tools/generate_audio.py` reproduces it. Impact/splash/sea are byte-identical to baseline. Tests verify deterministic bytes, corruption detection, attack/decay, DC/endpoints and conservative constructive mix headroom (~0.8391 for 64 cannon + two impact + one splash + sea at unit buses). This bound and Dummy-audio dispatch tests cannot judge convincing sound, device stereo/mono behavior or audible masking.

## Budgets and measurements

Retained budgets: Intel UHD-class **1080p release** p99 ≤16.67 ms and ≤0.1% frames over 16.67 ms; client RSS ≤300 MB; first start ≤4 s, later ≤2 s; encounter/replay ≤250 ms; download ≤50 MB Windows/Linux and ≤80 MB macOS; installed ≤150 MB Windows/Linux and ≤220 MB macOS. No budget revision is inferred from available-host measurements.

Baseline release `0.999` archive/installed bytes: macOS 61,246,646 / 171,842,246; Linux 29,205,561 / 74,325,674; Windows 38,855,794 / 110,074,412. Seven assets were successfully generated using verified official 4.7.2 templates (SHA-512 pinned in CI); outer zsh cleanup returned 1 after the successful baseline build because it assigned reserved `status`, so that outer invocation is not recorded as clean exit 0. Source baseline pack: 805,932 bytes. Final content pack: **889,772 bytes (+83,840)**; all platform packs agree. Final download/installed archive measurements follow; all fit size budgets. Product `version.cfg` remains unchanged.


| Platform | Download before → after (delta), bytes | Installed before → after (delta), bytes |
|---|---:|---:|
| Windows | 38,855,794 → 38,939,366 (+83,572) | 110,074,412 → 110,158,252 (+83,840) |
| Linux | 29,205,561 → 29,289,106 (+83,545) | 74,325,674 → 74,409,514 (+83,840) |
| macOS | 61,246,646 → 61,330,218 (+83,572) | 171,842,246 → 171,926,086 (+83,840) |

Clean baseline diagnostic (`baseline-bench-clean.log`, `/usr/bin/time -l`, `bench.gd`, native editor, Dummy audio, 5 s warmup + 60 s sample): 4,801 frames, p99 **17.166 ms**, **1.04145%** over 16.67 ms, peak RSS **294,207,488 bytes**, 313 draw calls / 39,635 primitives at final sample. An earlier concurrent-capture baseline run was discarded. Matched baseline (`baseline-bench-matched.log`, same final harness, no teardown warnings): 4,828 frames, p99 **22.202 ms**, **4.991715%** over 16.67 ms, peak RSS **296,468,480 bytes**. The earlier clean baseline is retained as a diagnostic but excluded from the final comparison because its harness differs. Final matched source measurement (`after-bench-final.log`): **5,769 frames**, p99 **16.402 ms** (−5.800 ms), **0.936037%** over 16.67 ms (−4.055678 percentage points), peak RSS **295,452,672 bytes** (−1,015,808 bytes). Final sampled draw calls/primitives: 498/52,511. The over-budget-frame fraction remains above the release target even on this local diagnostic; these figures do not certify Intel release performance. Final teardown reported 13 ObjectDB instances and one resource still in use; the matched baseline did not, so sustained process/resource-growth acceptance remains pending. This available-host editor workload issues both sides for all three ships each tick with natural reloads; it is not the Intel release protocol or an actual user session.

Baseline `main._ready` harness time 67.122 ms and encounter initialization 0.245–1.178 ms exclude process startup, OS/cache load and first rendered frame. They cannot satisfy cold/later start budgets. OS cold-cache first/later start remains pending.

## Owner acceptance still pending

Owner: **dnldxn**, on a named physical output and native display. Inspect all vessels/ammo at gameplay zoom, both broadsides, partial reloads, simultaneous opponents, close hits, open-water/moving misses, defeat/decisive tails, replay, pause/focus/resume and settings; all menus and remaps/notices; 1280×720 and physical 1080p, windowed/fullscreen, representative scaling and wider/taller layouts. Record grayscale readability, frame edges/offscreen markers, model clipping, smoke coverage and actual sound placement/clipping/masking. Listen to single/partial/full/opposing volleys and sea wraps, including stereo/mono output and Effects/Master/Ambient isolation. The owner decides subjective visual/sound quality.

Owner: **dnldxn**, for Intel UHD-class sustained release p99/RSS, cold/later process starts using the dossier protocol, encounter/replay, and native Windows/Linux/macOS release runs. Export success, headless assertions, M5 editor timing and screenshots do not close these gates. Any release-budget regression must be optimized before expanding scope or revising a budget. See [presentation runbook](07-presentation.md) for fixture commands; the obsolete `aim-cues` case has been removed.

## Preserved native measurement harnesses

The [benchmark harness](evidence/19/bench.gd) is the exact matched baseline/final workload, including 30-frame teardown and CSV output. Historical earlier harness diagnostics cannot be reconstructed from this version and are excluded from the comparison. [Ship/HUD capture](evidence/19/capture.gd), [menus](evidence/19/menu-capture.gd), [legal long prompts](evidence/19/long-prompts.gd), and [ammunition volleys](evidence/19/volleys.gd) are retained unchanged. They modify synthetic fixture state in a disposable copied project only; do not run them against real saved settings. Captures require a native display, and Dummy audio intentionally produces no physical listening evidence.

This macOS reproduction recipe creates baseline/current copies and a distinct custom profile for each. Replace the engine path if the pinned portable editor has moved; the engine must remain exactly 4.7.2. `git archive` needs the baseline commit available locally. The native override is confined to copied projects and uses Godot's custom-user-directory support; HOME and the source project remain untouched.

```bash
# Run from the repository root in bash; all variables have task-specific names.
T19_REPO="$PWD"
T19_ROOT="$(mktemp -d /private/tmp/tortuga19-reproduce.XXXXXX)"
T19_GODOT=/private/tmp/tortuga-19/portable/Godot.app/Contents/MacOS/Godot
mkdir -p "$T19_ROOT/before" "$T19_ROOT/after"
git archive d30be39 game | tar -x -C "$T19_ROOT/before"
rsync -a --exclude=.godot --exclude=override.cfg game/ "$T19_ROOT/after/game/"
cp -R docs/phase-2/evidence/19 "$T19_ROOT/harnesses"
for T19_VARIANT in before after; do
  T19_PROFILE="$(mktemp -d "$HOME/Library/Application Support/TortugaIssue19Tests.XXXXXX")"
  T19_RELATIVE="${T19_PROFILE#"$HOME/Library/Application Support/"}"
  printf '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="%s"\n' "$T19_RELATIVE" > "$T19_ROOT/$T19_VARIANT/game/override.cfg"
  "$T19_GODOT" --headless --path "$T19_ROOT/$T19_VARIANT/game" --import > "$T19_ROOT/$T19_VARIANT/import.log" 2>&1
  TORTUGA_BENCH_OUT="$T19_ROOT/$T19_VARIANT/frame-us.csv" \
    /usr/bin/time -l "$T19_GODOT" --path "$T19_ROOT/$T19_VARIANT/game" \
    --audio-driver Dummy --resolution 1920x1080 --disable-vsync \
    --script "$T19_ROOT/harnesses/bench.gd" > "$T19_ROOT/$T19_VARIANT/bench.log" 2>&1
  mkdir -p "$T19_ROOT/$T19_VARIANT/captures"
  TORTUGA_CAPTURE_DIR="$T19_ROOT/$T19_VARIANT/captures" \
    "$T19_GODOT" --path "$T19_ROOT/$T19_VARIANT/game" --audio-driver Dummy \
    --resolution 1280x720 --script "$T19_ROOT/harnesses/capture.gd" \
    > "$T19_ROOT/$T19_VARIANT/capture.log" 2>&1
  # Keep logs/captures; remove only the newly-created isolated profile after exit.
  rm -rf "$T19_PROFILE"
done
# Current-only menu, prompt and volley fixtures get a fresh isolated profile.
T19_PROFILE="$(mktemp -d "$HOME/Library/Application Support/TortugaIssue19Tests.XXXXXX")"
T19_RELATIVE="${T19_PROFILE#"$HOME/Library/Application Support/"}"
printf '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="%s"\n' "$T19_RELATIVE" > "$T19_ROOT/after/game/override.cfg"
for T19_HARNESS in menu-capture long-prompts volleys; do
  TORTUGA_CAPTURE_DIR="$T19_ROOT/after/captures" \
    "$T19_GODOT" --path "$T19_ROOT/after/game" --audio-driver Dummy \
    --resolution 1280x720 --script "$T19_ROOT/harnesses/$T19_HARNESS.gd" \
    > "$T19_ROOT/after/$T19_HARNESS.log" 2>&1
done
rm -rf "$T19_PROFILE"
```

Run the before/after timing commands sequentially, without concurrent captures, exports or other heavy workloads. Record OS, GPU/renderer, window/canvas/scaling, audio driver, executable build, all frame samples and `/usr/bin/time -l` RSS. The sample threshold in this harness is `>16667` microseconds; printed label rounds to 16.67 ms. The existing dossier's release/Intel/cold-start measurement protocol remains the acceptance protocol. Retained raw microsecond samples are [baseline](evidence/19/before-frames-matched.csv) and [after](evidence/19/after-frames-final.csv); [baseline log](evidence/19/baseline-bench-matched.log) and [after log](evidence/19/after-bench-final.log) preserve native renderer and timing/RSS output.


Actual matched native timing invocations (same preserved harness; source editor, not release):

```bash
TORTUGA_BENCH_OUT=/private/tmp/tortuga-19/before-frames-matched.csv /usr/bin/time -l /private/tmp/tortuga-19/portable/Godot.app/Contents/MacOS/Godot --path /private/tmp/tortuga-19/game --audio-driver Dummy --resolution 1920x1080 --disable-vsync --script /private/tmp/tortuga-19/bench.gd > /private/tmp/tortuga-19/baseline-bench-matched.log 2>&1
TORTUGA_BENCH_OUT=/private/tmp/tortuga-19/after-frames-final.csv /usr/bin/time -l /private/tmp/tortuga-19/portable/Godot.app/Contents/MacOS/Godot --path /private/tmp/tortuga-19/current/game --audio-driver Dummy --resolution 1920x1080 --disable-vsync --script /private/tmp/tortuga-19/bench.gd > /private/tmp/tortuga-19/after-bench-final.log 2>&1
```

Actual final build: from `/private/tmp/tortuga-19/current`, with its temporary `game/override.cfg` moved out before export and restored afterward:

```bash
GODOT=/private/tmp/tortuga-19/portable/Godot.app/Contents/MacOS/Godot bash tools/build_release.sh 0.999 /private/tmp/tortuga-19/after-release > /private/tmp/tortuga-19/final-release-build.log 2>&1
```


[Exported-font checker](evidence/19/check-export-font.gd) and [its final output](evidence/19/final-export-font.log) preserve the exact source/package comparison. Its two absolute source/pack paths identify this verification checkout; change those paths when reproducing with a different disposable checkout/build destination.

```bash
/private/tmp/tortuga-19/portable/Godot.app/Contents/MacOS/Godot --headless --path /private/tmp/tortuga-19/current/game --script /private/tmp/tortuga-19/check-export-font.gd > /private/tmp/tortuga-19/final-export-font.log 2>&1
```

The metadata-only font correction was checked by byte/table inspection and package loading; native screenshots and the matched timing sample precede that correction. No additional native rendering run is claimed after it; glyph tables are proven identical.
