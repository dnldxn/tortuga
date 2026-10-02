# Plan 08.03 — One-click pack updates: runbook and verification record

Issue: https://github.com/dnldxn/tortuga/issues/14 · Spec: #11 (Velopack updater replaced by a pack swap) ·
Requires 08.02 (#13). Engine: Godot 4.7.2 stable, Compatibility renderer.
Date: 2026-10-02 (owner local, PDT); CI timestamps are UTC.

| Commit | Subject | Release |
|---|---|---|
| `9598e5a` | feat: one-click pack updates (plan 08.03) | `v0.2`, the first build with the updater |
| `10488bb` | feat: add a sign-off to the selection guidance | `v0.3` (manual step 2: same base, ships as a pack) |
| `252c17d` | chore: note pack updates in project.godot header | `v0.4` (manual step 5: new base, full download) |

The plan's four per-task commits became one implementation commit, at the owner's request.
The two later commits are the manual end-to-end test changes; both stay in.

## How it works

- **Boot:** `res://boot.tscn` is the main scene. `boot.gd` preloads nothing from the game. It
  reads `res://version.cfg` and `user://updates/installed.cfg`, then overlays the pack with
  `ProjectSettings.load_resource_pack` and changes scene to `res://main.tscn`. It overlays only
  when all of these hold:
  - the build isn't `dev`;
  - the bases match;
  - the pack is newer;
  - the pack file exists.

  A pack that fails to load deletes `installed.cfg`.
- **Service:** `game/update/update_service.gd` is a child of main named "UpdateService". It reads
  `res://version.cfg` after the overlay, so it sees the pack's version. It is `disabled` for
  `dev` and touches the network only when the player clicks:
  - **Check for updates** fetches `releases/latest/download/update.json`.
  - **Update and Restart** downloads `releases/download/v<version>/<file>` to
    `user://updates/<file>.part`. It then verifies the SHA-256, renames the file and writes
    `installed.cfg` (via `.tmp` + rename). It deletes other files, ignoring failures, then
    calls `OS.set_restart_on_exit(true)` and `quit()`.
  - On a base mismatch, or a missing platform pack, the button is **Download full update**,
    which opens `releases/latest`.
- **UI:** the selection screen shows the version ("Tortuga 0.N" or "Development build") and a
  status line, with the buttons in a row below Quit. While downloading, the mode buttons,
  Settings and Update are disabled.
- **Base ID** (computed by `tools/build_release.sh`): a hash of `$GODOT --version`, the startup
  files (`project.godot`, `export_presets.cfg`, `default_bus_layout.tres`, `boot.gd`,
  `boot.tscn`) and the sorted `class_name` lines.
  - Changing any of them, or the engine, forces a full download.
  - An engine upgrade needs nothing manual for the base ID, because the version string changes.
    It does need the CI pins: the URLs and SHA-512 sums in `release.yml`, and the cache key.
- **UIDs:** in 4.7.2, `ProjectSettings::_load_resource_pack` refreshes the global class list and
  the UID cache when the project is loaded (`core/config/project_settings.cpp:609-615` at tag
  `4.7.2-stable`). The code still uses `res://` paths only; `git grep -n "uid://" -- 'game/*.gd'`
  prints nothing.

## 1. Local headless evidence (native macOS)

These checks ran on the owner's Mac (arm64, macOS 26.6.2), natively, not on the Linux dev host
and not in a container. This is headless macOS evidence, kept separate from the CI (Linux)
evidence in section 2.

**Toolchain:**
- `Godot_v4.7.2-stable_macos.universal.zip` was downloaded from `godotengine/godot-builds` into
  `~/.cache/tortuga-godot-4.7.2`.
- Its SHA-512 `38aa16e5…7bac69ca` matched `SHA512-SUMS.txt`. That file's linux and templates
  entries equal the hashes pinned in `release.yml`.
- `$GODOT --version` printed `4.7.2.stable.official.ed1daf0bf`.

**Isolation deviation:** Godot on macOS ignores `XDG_*`. `user://` and the editor settings follow
`$HOME/Library/Application Support`, so the repo wrapper's isolation guard (correctly) refused
to run.
- Every local run therefore used a scratch copy of `game/tests/run_settings_checks.sh` with 4
  changed lines: `HOME` set inside the guard and test roots, and the sentinel path moved to
  `$GUARD/home/Library/Application Support/Godot/...`.
- Every other Godot command ran as `HOME=<isolated> "$GODOT" ...`.
- One early `--import`, run before this was found, rewrote the real profile's
  `editor_settings-4.7.tres` and added 3 log files under `app_userdata/Tortuga/logs`. No
  `settings.cfg` was written.

Baseline at `5dcfe6d`: wrapper exit 0, `Tests: 3037 checks, 0 failures`, probes OK (the same
count CI recorded for 08.02).

| Step | RED | GREEN |
|---|---|---|
| Task 1: boot scene and pack loader | `FAIL: suite loads: res://tests/test_updater.gd`, exit 1 | `Tests: 3057 checks, 0 failures`; smoke run has no `SCRIPT ERROR` |
| Task 2: update service | `FAIL: suite loads: res://tests/test_updater.gd`, exit 1 | `Tests: 3097 checks, 0 failures` |
| Task 3: menu UI and wiring | 5 failures, exit 1 (see note) | `Tests: 3150 checks, 0 failures` |
| Task 3, fix round 1: layout | `Tests: 3159 checks, 5 failures` (e.g. "available (778.0 of 720.0 px)") | `Tests: 3159 checks, 0 failures` |
| Final review fixes | mutation: dropping `or code != 200` → exit 1, `Tests: 3173 checks, 3 failures` incl. `no suite scheduled a restart` | `Tests: 3173 checks, 0 failures` |

Note on Task 3's RED: a runtime error inside a `_test_*` helper aborts only that helper, so
`run()` still returned true. The first RED run exited 0 despite 6 `SCRIPT ERROR`s. Every
`_test_*` in `test_updater.gd` now returns `true` and runs through a loop that checks it.

Final controller run on the committed tree:

| Command | Result |
|---|---|
| `"$GODOT" --headless --path game --import` | exit 0, no `ERROR`/`WARNING` |
| wrapper (macOS copy) | exit 0; `Guard rejection: OK`; 18 suites; `Tests: 3173 checks, 0 failures`; `Settings process probes: OK` |
| wrapper `--self-test-failure` | exit 1; `Tests: 3174 checks, 1 failures` |
| `"$GODOT" --headless --path game --quit-after 30` | exit 0; boot → main, no `ERROR`/`SCRIPT ERROR` |
| `git grep -n "uid://" -- 'game/*.gd'` (and plain `grep` incl. untracked) | no output |
| `git diff --check` | clean |

Findings recorded during the work:
- **Expected `ERROR` lines:** only the deliberate ones from older suites. A 16-byte garbage pack
  makes `load_resource_pack` return false silently on 4.7.2, so the corrupt-pack case prints
  nothing.
- **Partial packs:** a pack truncated partway still loads (returns true). A pack truncated
  inside its header hangs `load_resource_pack` at 100% CPU. Verifying the SHA-256 before the
  rename is the only guard, so an unverified file is never named by `installed.cfg`.
- **Layout:** the plan stacked the update block vertically below Quit. That made the mode panel
  778 px tall in `available` against the 720 px viewport, which put Update and Restart
  off-screen. The block is now two rows ([version | status] and [Check | Update | Download]),
  and the panel is 678 px in every update state.
  - With the rare settings-fallback notice also shown, the panel is 749 px (29 px over).
  - A test asserts the panel fits in disabled, available, full_download, downloading and error.
- **Exit-time warning:** an intermittent "2 ObjectDB instances were leaked at exit"
  (`AudioStreamPlaybackWAV` + `AudioStreamWAV`, Ambient bus) appears at runner exit on macOS.
  It predates this plan: 4/10 runs leaked without `test_updater` and 2/10 with it. None of the
  three CI (Linux) runs printed it.
- **Test gate:** if a hash or status guard regressed, the success path's `quit()` would end the
  test process with exit 0. The runner now fails if any suite schedules a restart, clears the
  restart flag, and calls `quit(1)` immediately on any failure.

## 2. CI and GitHub evidence (Linux, GitHub Actions)

| Release | Run | Commit | Result |
|---|---|---|---|
| `v0.2` | https://github.com/dnldxn/tortuga/actions/runs/37027278870 | `9598e5a` | success (cache hit), 15:28:59Z–15:30:16Z |
| `v0.3` | https://github.com/dnldxn/tortuga/actions/runs/37043040604 | `10488bb` | success, 17:46:55Z–17:48:15Z |
| `v0.4` | https://github.com/dnldxn/tortuga/actions/runs/37044084118 | `252c17d` | success, 17:56:22Z–17:57:46Z |

- Each run's Test step printed `Guard rejection: OK`, `Tests: 3173 checks, 0 failures` and
  `Settings process probes: OK`, and no ObjectDB leak warning.
- Each release has 7 assets. The packs are 809,676 bytes for `v0.2` and 809,692 bytes for
  `v0.3`/`v0.4`; the macOS zip is about 61.25 MB.

| Manifest | `base` | macOS pack `sha256` |
|---|---|---|
| `v0.2` | `26d9ac57a7f9de22` (was `afb8b703838cb625` at `v0.1`, before `boot.*` existed) | `942e1001…3919fc9` |
| `v0.3` | `26d9ac57a7f9de22` | `20de7f86…112d6163`; an anonymous download of the pack matched it |
| `v0.4` | `ac7791a8f2059d83` (the `project.godot` comment changed) | `4839ccd2…d3da70f4` |

## 3. Owner macOS real-display evidence

Observer: project owner, on their Mac. Build: CI's `Tortuga-0.2-macos.zip` (`gh release
download`, `unzip`, `xattr -dr com.apple.quarantine`, `open`). The owner reported each step as
working as expected; individual timings and screenshots were not recorded.

| Plan step | Result |
|---|---|
| Install `v0.2`: "Tortuga 0.2", Check → "You're up to date." | Passed |
| 6. Up/Down from Quit through Check and back, skipping hidden Update/Download | Passed |
| 2. After `v0.3` was published: Check → "Version 0.3 is available." → Update and Restart → relaunches on 0.3, and the guidance ends "Good hunting!" | Passed |
| 3. Relaunch from Finder: still 0.3 | Passed |
| 4. Offline: Check → "Couldn't check for updates."; the game still plays | Passed |
| 5. After `v0.4` was published: Check → "Version 0.4 is available." + Download full update → opens the releases page | Passed |

Read-only inspection of `~/Library/Application Support/Godot/app_userdata/Tortuga/updates/`
after steps 2–5:
- It holds exactly `installed.cfg` and `tortuga-0.3-macos.pck`, with no `.part`.
- `installed.cfg` reads `version="0.3"`, `base="26d9ac57a7f9de22"`, `file="tortuga-0.3-macos.pck"`.
- The pack's SHA-256 equals `v0.3`'s manifest.
- Nothing changed after step 5.
- The game logs from these runs have no `ERROR`/`WARNING` lines.

## Not verified

- **Settings across an update.** The owner changed no settings before updating (there is no
  `settings.cfg`), so "settings unchanged" holds only trivially.
- **Windows and Linux on a real display**, including Windows' locked running pack during
  cleanup and restart-on-exit there. No machine was used.
- **The Linux dev host.** Local checks ran natively on macOS with the HOME-isolated wrapper copy;
  the Linux evidence is CI's.
- **Two packs in sequence** (e.g. 0.3 → 0.4 on a 0.2 build). It is covered by the code and the
  final review's trace, but not run, because `v0.4` changed the base.
- **Gatekeeper behavior after a self-restart.** The app was un-quarantined before first launch.
- **Real-display layout** of the `available` + settings-notice case (749 px, measured headless only).

## Remaining for the owner

- **Optional:** make `game/tests/run_settings_checks.sh` set `HOME` inside its test roots, so the
  repo wrapper also isolates `user://` on macOS. Today it refuses to run there.
- **Optional:** the pre-existing audio leak at runner exit (above).
