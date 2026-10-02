# Plan 08.02 — CI releases: runbook and verification record

Issue: https://github.com/dnldxn/tortuga/issues/13 · Engine: Godot 4.7.2 stable, Compatibility renderer.
Date: 2026-10-01 (owner local, PDT); CI timestamps are UTC, 2026-10-02.
Verified commit: `691d2689c4b97841049c9fd01747e71edb92faf8` (tag `v0.1` points here).

The Velopack updater experiment (#12) is removed (#12 closed as not planned) and every push to
`main` now publishes a numbered GitHub release.

| Commit | Subject |
|---|---|
| `0cf2152` | chore: remove Velopack updater experiment (#12) |
| `1c7deb7` | build: add windows/linux export presets and version.cfg |
| `4b52c3c` | build: add tools/build_release.sh |
| `15dde6b` | ci: publish v0.N releases on every push to main |
| `691d268` | docs: describe CI releases in CLAUDE.md |

## Release builds

- `.github/workflows/release.yml` runs on every push to `main` except docs-only pushes
  (`paths-ignore: docs/**, **.md`) and on manual dispatch. Steps: restore or download Godot
  4.7.2 (SHA-512 pinned), run `bash game/tests/run_settings_checks.sh`, pick the next `v0.N`
  from `gh release list`, run `tools/build_release.sh`, then `gh release create` as latest.
- Each release has 7 assets: `Tortuga-0.N-macos.zip`, `Tortuga-0.N-windows.zip`,
  `Tortuga-0.N-linux.tar.gz`, `tortuga-0.N-{windows,macos,linux}.pck` and `update.json`
  (version, base ID, per-platform pack file and SHA-256).
- Local build of all assets (repo root; absolute `$GODOT` and the 4.7.2 export templates
  installed, per `sailing-playground.md`): `bash tools/build_release.sh 0.N build/phase-2/release`.
  The script restores `game/version.cfg` on exit.
- macOS: download `Tortuga-0.N-macos.zip` from the latest release, unzip, then
  `xattr -dr com.apple.quarantine Tortuga.app` and `open Tortuga.app`. The app is ad-hoc signed,
  not notarized.

## 1. Local headless evidence (Linux container on the owner's Mac)

These checks did **not** run on the Linux dev host. They ran on the owner's Mac (arm64, macOS)
inside a linux/amd64 Ubuntu 24.04 Docker container (Docker Desktop emulation) with the repo and
toolchain bind-mounted at their host paths and the `CLAUDE.md` toolchain exports set. The
toolchain was set up per `sailing-playground.md` into `~/.cache/tortuga-godot-4.7.2`; both
downloads printed `VERIFIED` against the godotengine/godot-builds `SHA512-SUMS.txt` (linux zip
`9aa00f7a…ed54c65`, templates `ca4d71c4…ccb84079`, the same values pinned in `release.yml`), and
`$GODOT --version` printed `4.7.2.stable.official.ed1daf0bf`. Headless runs validate logic and
exports only, not rendering. Baseline before any change: `run_settings_checks.sh` exit 0.

### Task 1 — remove Velopack (`0cf2152`)

19 files (3972 lines) deleted: `native/`, `tools/release/`, `game/native/`,
`docs/phase-2/01-native-updater-feasibility.md`, `docs/phase-2/release-contracts.md`.

| Command | Result |
|---|---|
| `git grep -n -i -E 'velopack\|godot-cpp\|gdextension\|tortuga_updater\|bootstrap_toolchain\|toolchain-lock\|release-contracts\|native-updater\|tools/release'` | exit 1 (no matches) |
| `bash game/tests/run_settings_checks.sh` | exit 0; output ends with probes restore 1 and read-defaults 14, `Settings process probes: OK` |
| Local cleanup of #12 leftovers | none present on this Mac (checked `build/`, `$TMPDIR/velopack.log`, `/var/tmp/velopack`, `~/Library/Logs/velopack*`; no Velopack directories in the fresh toolchain cache) |

The Task 1 run was recorded by the tail of its output only. The full wrapper output, with
check counts, was captured at the release commit:

| Command | Result |
|---|---|
| `bash game/tests/run_settings_checks.sh` at HEAD `691d268` | wrapper exit 0; `Guard rejection: OK`; 17 suites; `Tests: 3037 checks, 0 failures`; probes write 7, read 13, corrupt 2, fallback 8, restore 1, read-defaults 14 checks, all 0 failures; `Settings process probes: OK` |

### Task 2 — `version.cfg` and export presets (`1c7deb7`)

`game/version.cfg` (`version="dev"`, `base="dev"`) and `game/export_presets.cfg` with presets
`macos`, `windows`, `linux`; each includes `version.cfg` in the pack; no hardcoded export path.

| Command | Result |
|---|---|
| `for p in windows macos linux; do "$GODOT" --headless --path game --export-pack "$p" "$PWD/build/phase-2/presets/$p.pck" && grep -qa 'base="dev"' "build/phase-2/presets/$p.pck" && echo "$p ok"; done` | `windows ok`, `macos ok`, `linux ok` |
| `bash game/tests/run_settings_checks.sh` | exit 0; probes read 13, corrupt 2, fallback 8, restore 1, read-defaults 14 checks, 0 failures; ends `Settings process probes: OK` |

### Task 3 — `tools/build_release.sh` (`4b52c3c`)

| Command | Result |
|---|---|
| `bash tools/build_release.sh 0.999 build/phase-2/release` | exit 0; 45.4 s real (emulated x86_64); no `ERROR`/`WARNING`/`SCRIPT ERROR` in the ANSI-stripped build log |
| `git status --porcelain` after the run | only the new `tools/` script; `game/version.cfg` restored to `dev`/`dev` (trap works) |
| `bash tools/build_release.sh 0.x /tmp/x` | prints `version must be 0.N`, exit 2; `/tmp/x` not created |
| `sha256sum build/phase-2/release/*.pck`, compared with `update.json` | all three `8730285714271d61c198a8e57daf4302aa28f51da9ae818e147a1c130e350c75`; the three JSON hashes equal the file digests (container and host agree) |
| `grep -qa 'version="0.999"' build/phase-2/release/tortuga-0.999-linux.pck` | exit 0 |
| `tar -xzf Tortuga-0.999-linux.tar.gz -C build/phase-2/smoke; build/phase-2/smoke/Tortuga.x86_64 --headless --quit-after 30` | exit 0 (output: Godot banner only) |

Assets for version `0.999` (7):

| Asset | Bytes |
|---|---:|
| `Tortuga-0.999-linux.tar.gz` | 29,204,249 |
| `Tortuga-0.999-macos.zip` | 61,241,471 |
| `Tortuga-0.999-windows.zip` | 38,850,618 |
| `tortuga-0.999-linux.pck` | 799,580 |
| `tortuga-0.999-macos.pck` | 799,580 |
| `tortuga-0.999-windows.pck` | 799,580 |
| `update.json` | 479 |

- `update.json`: `version` `0.999`, `base` `afb8b703838cb625` (16 lowercase hex, regex-checked).
- Archive contents: `windows.zip` = `Tortuga.exe` + `Tortuga.pck`; `linux.tar.gz` = `Tortuga.x86_64`
  (mode 755) + `Tortuga.pck`; `macos.zip` = `Tortuga.app/Contents/...` including
  `Resources/Tortuga.pck`, `MacOS/Tortuga` and `_CodeSignature/CodeResources`.
- The three `.pck` files are byte-identical (all presets share one filter), so `update.json`
  lists the same hash for each platform.
- The base ID hashes `$GODOT --version`, the startup files (`project.godot`,
  `export_presets.cfg`, `default_bus_layout.tres`, `boot.gd`, `boot.tscn`, each if present)
  and the sorted `class_name` lines (including `game/tests/*.gd`). It changes when the
  engine version, any of those files, or any `class_name` line changes.

### Task 4 — `.github/workflows/release.yml` (`15dde6b`)

| Command | Result |
|---|---|
| `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest -color .github/workflows/release.yml` | exit 0, no output (actionlint is not installed locally; run via its Docker image) |
| `python3 -c 'import yaml…'` YAML parse | skipped: PyYAML not installed on the host |

The commit was amended once to correct the `Co-Authored-By` trailer. The amend changed only
the commit message; the content diff against the pre-amend commit was empty.

### Task 5a — `CLAUDE.md` (`691d268`)

| Command | Result |
|---|---|
| `git show --stat 691d268` | `CLAUDE.md` only, 2 insertions and 2 deletions; the old `--export-release macos …` command became `bash tools/build_release.sh 0.N build/phase-2/release`, and the rolling-`v0.1` bullet became the CI-release bullet; `Co-Authored-By` trailer correct |

### Whole-branch review (`aa55a5d..691d268`, separate reviewer)

Every added file is byte-identical to the plan text. In a fresh `git clone` inside the
container with fresh editor settings and only the four release templates: `--import` exit 0
with no `ERROR`/`WARNING`; `--export-release linux` and `--export-release windows` exit 0;
the pack is the same 799,580 bytes.

## 2. CI and GitHub evidence

Task 5 (cutover) was run from the owner's Mac with the owner confirming each outward step.
Work was committed directly on `main` (no `plan-08.02` branch; nothing was pushed before the
cutover), so the plan's merge step became `git push origin main`.

| Step | Command | Result |
|---|---|---|
| Secret review (paths) | `git log --all --oneline -- config.json status.md .agents .superpowers` | empty |
| Secret review (patterns) | `git log -p --all \| grep -n -i -E 'api[_-]?key\|secret\|token\|password\|PRIVATE KEY'` | 9 hits, each reviewed by the owner as benign: the workflow's `GH_TOKEN: ${{ github.token }}` and a test fixture named "secret" in the removed `native/tests/test_toolchain.py` |
| Secret review (token formats) | scan for `ghp_`, `github_pat_`, `sk-`, `AKIA`, `xox`, `AIza`, `-----BEGIN` | 0 hits |
| Make public | `gh repo edit dnldxn/tortuga --visibility public --accept-visibility-change-consequences` | `gh repo view --json visibility` → `PUBLIC` |
| Delete legacy release | `gh release delete v0.1 --repo dnldxn/tortuga --cleanup-tag --yes` | `gh release list` empty |
| Check no leftover tag | `git ls-remote --tags origin 'refs/tags/v0.*'` | empty (added check: GitHub ignores `--target` if the tag already exists) |
| Version-pick dry run | the workflow's `jq` filter against the empty release list | `VERSION=0.1` |
| Legacy skill dir | `rm -rf .agents/skills/claptrap/ct-tortuga-replace-test-release` | not present on this Mac |
| Push | `git push origin main` | `aa55a5d..691d268`, no tags |
| CI run | https://github.com/dnldxn/tortuga/actions/runs/36966313815 | success; Test, Pick version, Build and Publish all succeeded; created 2026-10-02T04:50:38Z, finished 04:52:08Z |
| CI Test step | `bash game/tests/run_settings_checks.sh` | `Guard rejection: OK`; `Tests: 3037 checks, 0 failures`; `Settings process probes: OK` (check total and per-probe counts identical to the local container run at HEAD) |
| Cache | first run | miss: step `Download Godot (cache miss)` ran (1.28 GB templates plus editor) and `sha512sum -c` passed |
| Release | `gh release view v0.1 --json name,isDraft,isPrerelease,assets --jq '{name,isDraft,isPrerelease,n:(.assets\|length)}'` | `{"isDraft":false,"isPrerelease":false,"n":7,"name":"Tortuga 0.1 — Test build"}`; tag `v0.1` → `691d268` |
| Anonymous manifest | `curl -fsSL https://github.com/dnldxn/tortuga/releases/latest/download/update.json` | exit 0; `version` `0.1`, `base` `afb8b703838cb625`, windows/macos/linux each `sha256` `0687d8e35aabfaea5d81b1941ba9ebea298a40375b56627ea0eb617d0523a598`, files `tortuga-0.1-<platform>.pck` |
| Anonymous pack | download of `…/releases/download/v0.1/tortuga-0.1-linux.pck` | sha256 `0687d8e3…a598` (matches `update.json`); contains `version="0.1"` |
| Close #12 | `gh issue close 12 --repo dnldxn/tortuga --reason "not planned" --comment "Superseded by #13 (CI releases + pack-swap updates)."` | CLOSED, NOT_PLANNED |
| Local tag | stale lightweight tag `v0.1` (→ `4f6edd8`, legacy) | deleted locally and refetched (→ `691d268`) |

Assets of release `v0.1` (7):

| Asset | Bytes |
|---|---:|
| `Tortuga-0.1-linux.tar.gz` | 29,203,875 |
| `Tortuga-0.1-macos.zip` | 61,241,141 |
| `Tortuga-0.1-windows.zip` | 38,850,290 |
| `tortuga-0.1-linux.pck` | 799,580 |
| `tortuga-0.1-macos.pck` | 799,580 |
| `tortuga-0.1-windows.pck` | 799,580 |
| `update.json` | 471 |

- The CI base ID `afb8b703838cb625` equals the local container build's base ID (same engine
  and inputs). The three CI packs are byte-identical.
- The CI pack hash differs from the local `0.999` pack hash, as expected, because the
  stamped `version.cfg` differs (`version="0.1"` vs `"0.999"`).
- This docs-only commit does not trigger a release (`paths-ignore`).

## 3. Owner macOS real-display evidence

Observer: project owner, on their Mac.

| Step | Result |
|---|---|
| `gh release download v0.1 --pattern 'Tortuga-0.1-macos.zip'` into `~/Downloads/tortuga-0.1`, `unzip`, `xattr -dr com.apple.quarantine Tortuga.app`, `open Tortuga.app` | Owner reported "The game worked as expected": the selection menu appeared and the owner sailed briefly |

The CI-built macOS archive launched natively. Machine and OS version, display resolution and
individual observations were not recorded. This is a launch-and-brief-sail check, not a
playtest, performance or audio pass.

## Not verified

- Windows and Linux builds on a real display. No Windows or Linux machine was used; the Linux
  build ran only headless (`--quit-after 30`) in the emulated container and the Windows build
  was exported but never launched.
- The Linux dev host itself. Local checks ran in the emulated linux/amd64 container on a Mac.
- Gatekeeper behavior beyond Godot's ad-hoc signing (no notarization). The owner launched
  after removing the quarantine attribute.
- The CI cache-hit path. Only the first run (a cache miss) has happened.
- Pack updates, which belong to plan 08.03 (#14). The `.pck` files and `update.json` are
  published and checked for consistency; no consumer loads them yet.

## Remaining for the owner

- Clean up the #12 leftovers on the Linux dev host where the experiment ran: the Task 1
  cleanup list, including `build/phase-2/feasibility/`, the Velopack, .NET, godot-cpp and
  squashfs-tools directories under `~/.cache/tortuga-godot-4.7.2/downloads/`, the Velopack logs,
  and `.agents/skills/claptrap/ct-tortuga-replace-test-release` if present there. Keep the
  Godot editor zip, templates, `bin/`, `unpacked/` and `xdg/`. The Linux dev host was not
  reachable from this session, so none of it was done.
