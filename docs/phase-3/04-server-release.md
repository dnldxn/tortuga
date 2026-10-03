# Plan 04 — Server release and OCI deployment: verification record

Issue: https://github.com/dnldxn/tortuga/issues/24 · Spec: https://github.com/dnldxn/tortuga/issues/20
(§1 "Server build" and the open question on OCI firewall and systemd setup; protocol and server logic are
Plan 02, the client UI Plan 03, soak, cost and acceptance Plan 05).
Engine: Godot 4.7.2 stable (stock `linux_release.arm64` template for the server).
Date: 2026-10-03 (owner local, PDT).

Verified SHA: `e0df45b` → release **v0.5** (https://github.com/dnldxn/tortuga/releases/tag/v0.5).
Work was done directly on `main` (no `plan-p3-04` branch, owner's choice); the owner approved the push.

| Task | Commit | Subject |
|---|---|---|
| 1 | `1f3c303` | build: publish a linux-arm64 server archive with each release |
| 2 | `8805c9d` | feat: add server update script, systemd unit and OCI runbook |
| 2 (follow-up) | `e0df45b` | fix: stop the server before swapping files; fail when it does not start |
| 6 | this commit | this record |

## How it works

- **No new export preset** (`export_presets.cfg` is a base-ID input). `tools/build_release.sh` copies the
  stock `linux_release.arm64` template as `tortuga-server`, the linux pack byte for byte as
  `tortuga-server.pck` (Godot loads `<exe>.pck` beside the executable), and writes an `override.cfg` with
  `application/run/flush_stdout_on_print=true` so `print()` reaches journald live.
- **One fixed-name asset** with its `.sha256`: `tortuga-server-linux-arm64.tar.gz`, single top dir
  `tortuga-server-0.N/`. `update.json` and the base ID are untouched. Release assets: 7 → 9.
- **On the box**, `tortuga-update-server [0.N]` (`tools/update_server.sh`) downloads and verifies the archive,
  stops `tortuga-server.service`, swaps `/opt/tortuga/server`, starts it, and exits 1 unless it is `active`.
  Rollback = rerun it with an older version. Runbook: `docs/phase-3/server-ops.md`.
- **Graceful stop via a stop file:** the unit passes `--stop-file /run/tortuga-server/stop`; `ExecStop`
  touches it and waits. SIGTERM only follows if `TimeoutStopSec=10` runs out (abrupt, "Connection lost").

## 1. Build script (native macOS)

- `bash -n tools/build_release.sh`: no output.
- Missing template fails fast: `HOME="$(mktemp -d)" bash tools/build_release.sh 0.999 build/phase-3/x` →
  `missing …/Library/Application Support/Godot/export_templates/4.7.2.stable/linux_release.arm64`, `exit=2`;
  `build/phase-3/x` not created, `git status --porcelain game/version.cfg` empty. Re-run independently by the
  final reviewer with the same result.
- The optional local build (1.28 GB templates) was **skipped** by the owner's choice; CI's build is the evidence.

## 2. CI and GitHub (Linux x86_64, GitHub Actions)

Run: https://github.com/dnldxn/tortuga/actions/runs/37126254829 (head `e0df45b`).

- Steps all `success`, including `Download Godot (cache miss)` (not `skipped`: the cache key bump to `v2`
  forced the download and the new `unzip` of `templates/linux_release.arm64`), `Test`, `Server smoke`,
  `Build`, `Publish`.
- `gh release view v0.5`: **9 assets** — the 3 client builds, 3 packs, `update.json`,
  `tortuga-server-linux-arm64.tar.gz`, `tortuga-server-linux-arm64.tar.gz.sha256`.
- Anonymous download from `releases/latest/download/` (as the box does), into `build/phase-3/v0.5`:
  - `sha256sum -c` → `tortuga-server-linux-arm64.tar.gz: OK`.
  - `tar -tvzf`: 4 entries — `tortuga-server-0.5/` (`drwxr-xr-x`), `tortuga-server` (`-rwxr-xr-x`, 67,079,432 B),
    `override.cfg` (46 B), `tortuga-server.pck` (2,913,612 B).
  - `file tortuga-server` → `ELF 64-bit LSB executable, ARM aarch64 … for GNU/Linux 5.15.0, stripped`.
  - `pck-matches`: the server `.pck` SHA-256 equals `update.json`'s `packs.linux.sha256`.
  - `base-unchanged`: v0.5's `update.json` `base` equals v0.4's.

## 3. Packaged server in a linux/arm64 container (Docker on the Mac)

Docker 29.7.2, image `tortuga-ol9` (`oraclelinux:9` + `procps-ng`; Oracle Linux Server 9.8, glibc 2.34,
`aarch64`, native arm64). Server started with runbook §7 (`--user 1000:1000`, password from env, port 24680).

- **Live stdout:** within 3 s `docker logs` showed the `Godot Engine v4.7.2.stable.official.ed1daf0bf` banner
  and `SRV listening port=24680 version=0.5 max_captains=4 max_battles=4`. `docker logs` reads a pipe, so
  `override.cfg` is honored, the pack loads on arm64, and the password came from env.
- **Bots** (release macOS app `Tortuga-0.5-macos.zip` and a dev bot from source):

  | Bot | Exit | Key lines |
  |---|---|---|
  | MacBot (`--preset brig_squadron --seconds 60`) | 0 | `BOT connected name=MacBot slot=0 version=0.5`, `BOT joined battle=1 ship=100 preset=brig_squadron`, summary `seconds=60.2 snapshots=1110 events=226 actions_sent=42 actions_applied=42 disconnects=0 rtt_ms=22`; server `SRV auth accept … captain=MacBot slot=0 client_version=0.5` |
  | PwBot (`--password nope`) | 1 | `BOT refused auth reason=wrong_password server_version=0.5 client_version=0.5` |
  | DevBot (source, `client_version=dev`) | 1 | `BOT refused auth reason=version_mismatch server_version=0.5 client_version=dev`; container still `Up` |

- **Graceful stop via the stop file**, IdleBot (`--idle --seconds 100`) connected: `docker exec tortuga-srv touch
  /tmp/stop` → server exited in **0.48 s** (touch to `docker wait`), `docker wait` printed `0`; log has
  `SRV stopping reason=stop-file`, `SRV leave captain=IdleBot …`, `SRV stopped host_bytes_in=121838
  host_bytes_out=447175`; bot `BOT ended reason=server_stopped`, `exit=0`.
- **Costs:** archive 30,442,604 B (29 MiB); extracted 67 MiB. RSS 88,968 KiB at 14 s idle (CPU 1.8 %),
  89,868 KiB at 85 s, just after the 60 s MacBot battle (CPU 3.8 %, lifetime average). Well under the 150 MB
  flag. (A strict 60-s-idle-before-any-client sample was not taken.)
- `docker stop` (SIGTERM, the abrupt path) was not measured. Container removed; image `tortuga-ol9` kept for
  Plan 05.

## 4. OCI (owner)

Not yet run — the owner runs runbook §1–§3 on the box, then the checks below from the Mac
(`$BOT` = the v0.5 macOS app). Instance shape: _____ · Observer: _____ · Date: _____

| # | Step | Expected | Result |
|---|---|---|---|
| 1 | Install: runbook §1–§3 (box) | OL 9.x, `aarch64`, glibc 2.34, `Enforcing`; `tortuga-server-0.N: active`; journal `SRV listening port=24680 version=0.N` | |
| 2 | Bot over the internet (Mac → box) | `BOT connected … version=0.N`, `BOT joined …`, `exit=0`; journal `SRV auth accept … captain=OwnerBot` | |
| 3 | Dev bot (`--host <public-ip>`) | `BOT refused auth reason=version_mismatch server_version=0.N client_version=dev`, `exit=1` | |
| 4 | `time sudo systemctl restart tortuga-server`, idle bot connected | real < 3 s (not ~10); bot `BOT ended reason=server_stopped`, exit 0; journal `SRV stopping reason=stop-file`; `systemctl is-active` → `active` | |
| 5 | `sudo systemctl reboot` with an idle bot connected; wait ~2 min | bot exits 0 with `server_stopped`; service `active` after boot; a new bot connects | |
| 6 | Costs: after 5 min idle, `ps -o rss=,pcpu= -C tortuga-server`; `sudo du -sh /opt/tortuga/server` | RSS MB, CPU %, installed size recorded | |

## Decisions and deviations

- **No branch:** work landed directly on `main` (owner's choice); the push was owner-approved.
- **`tools/update_server.sh` differs from the plan's text** (owner's request after review): it runs
  `systemctl stop` before replacing `/opt/tortuga/server` and `systemctl start` after (the plan replaced the
  files under the running server, then restarted), and exits 1 unless the service is `active` (the plan always
  exited 0). The stop is still graceful (`ExecStop`). Runbook §4 says so.
- **Optional local build skipped** (owner's choice); CI's build is the evidence.

## Not verified

- The unit, update script, SELinux and firewalld anywhere but OCI (no local systemd rehearsal) — §4 pending.
- SIGTERM timing; the arm64 binary in CI (CI only packs it); x86_64/Windows servers.
- Load, soak, bandwidth and the friends session (Plan 05); Linux/Windows clients against the server.

**Remaining for Plan 05:** loaded RSS/CPU and bandwidth on OCI.
