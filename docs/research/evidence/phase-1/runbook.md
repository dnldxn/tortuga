# Phase 1 runbook — bounded inventory and source checks

Companion: [research dossier](../../phase-1.md). Inventory/source commands executed 2026-09-30, approximately 06:28–06:31 UTC, in `/home/ddixon/projects/tortuga` on current `main`. Sections A–E record **actual commands and selected outputs**, including failures; section F separately attributes the subsequent access report. Sections A–F describe the first slice, which had no engine, build, benchmark, or footage observation; sections H and I add the footage inspection and the Godot probe.

Only model/capacity/policy metadata was collected. Commands filter out PCI addresses before printing; system-file reads select safe attributes, not serials, UUIDs, EDID, network addresses, or complete environments. System snapshots are **measured inventory**, not application resource/performance samples. Rerun inventory immediately before future measurements.

## A. Authority and preservation baseline

Commands executed:

```sh
git status --short --branch
git rev-parse HEAD
git diff -- MASTER-PLAN.md
git hash-object MASTER-PLAN.md
date -u +%Y-%m-%dT%H:%M:%SZ
gh issue view 1 --repo dnldxn/tortuga --json number,title,body,url,updatedAt
gh issue view 2 --repo dnldxn/tortuga --json number,title,body,url,updatedAt
```

Results: `main...origin/main`; only ` M MASTER-PLAN.md` at entry; HEAD `d1a9880254fe9280d7de939e8b065cf24df82153`; master blob `945e960829f276162a50d03313ac96d63e6cdde9`; UTC `2026-09-30T06:28:23Z`. Full issues read successfully; #1 updated `05:57:02Z`, #2 `06:08:33Z` on that date. Both roadmap files read through dedicated file tools. Later pre-edit `git hash-object README.md MASTER-PLAN.md` returned README `2fa0bf61010a9999fc2ccce21083a30dc87cb6fd` and the same master hash. No repository-local `AGENTS.md` found.

## B. LNX-01: CPU, memory, storage

Exact shell commands:

```sh
uname -srmo
lscpu --json | jq '.lscpu | map(select(.field | test("^(Architecture|CPU op-mode\\(s\\)|CPU\\(s\\)|On-line CPU\\(s\\) list|Vendor ID|Model name|Thread\\(s\\) per core|Core\\(s\\) per socket|Socket\\(s\\)|CPU max MHz|CPU min MHz|Virtualization):$")))'
free -b
lsblk -d -b -o NAME,TYPE,SIZE,ROTA,TRAN,MODEL
df -B1 --output=fstype,size,used,avail,pcent /home/ddixon/projects/tortuga
```

Selected results, with units as reported:

```text
Linux 7.2.4-200.fc44.x86_64 x86_64 GNU/Linux
Architecture: x86_64; CPU op-modes: 32-bit, 64-bit
CPU(s): 16; online: 0-15; GenuineIntel
Model: Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz
Threads/core: 2; cores/socket: 8; sockets: 1
CPU max MHz: 2300.0000; CPU min MHz: 800.0000; Virtualization: VT-x

free -b          total         used          free      shared  buff/cache    available
Mem:      33457631232   3999285248   24889815040   130211840  5177749504  29458345984
Swap:      8589930496            0    8589930496

NAME    TYPE         SIZE ROTA TRAN   MODEL
sda     disk            0    0 usb    SD/MMC
zram0   disk   8589934592    0
nvme0n1 disk 512110190592    0 nvme   INTEL SSDPEKNW512G8

Type     1B-blocks         Used        Avail Use%
btrfs 335511814144 201603391488 131532595200  61%
```

The reported CPU maximum is the current utility/kernel view, not a verified processor turbo specification. RAM is OS-visible capacity (~31.16 GiB), not a DIMM audit. Btrfs filesystem capacity is not the physical disk capacity. The zero-size SD/MMC reader and zram are not additional physical storage. No throughput, thermal, loading, or application-memory conclusion follows.

## C. GPUs and session

Exact command (outputs no PCI addresses or display-address values):

```sh
python3 -c 'import os,subprocess; r=subprocess.run(["lspci","-mm"],capture_output=True,text=True,check=True); print("Display-controller rows (PCI addresses omitted):"); print("\n".join(s.split(" ",1)[1] for s in r.stdout.splitlines() if any(x in s for x in ("VGA compatible controller", "3D controller", "Display controller")))); print("Session environment:"); print({k:("set (value omitted)" if os.environ.get(k) else "unset") for k in ("DISPLAY","WAYLAND_DISPLAY")}); print("XDG_SESSION_TYPE="+os.environ.get("XDG_SESSION_TYPE","unset"))'
nvidia-smi --query-gpu=name,driver_version,memory.total,power.draw,power.limit,pstate --format=csv,noheader
rpm -q mesa-dri-drivers mesa-vulkan-drivers libglvnd-egl kernel-core
```

Results:

```text
"VGA compatible controller" "Intel Corporation" "CometLake-H GT2 [UHD Graphics]" -r05 -p00 "AIstone Global Limited" "Device 108b"
"VGA compatible controller" "NVIDIA Corporation" "TU106M [GeForce RTX 2070 Mobile / Max-Q Refresh]" -ra1 -p00 "AIstone Global Limited" "Device 108b"
{'DISPLAY': 'unset', 'WAYLAND_DISPLAY': 'unset'}
XDG_SESSION_TYPE=tty
NVIDIA GeForce RTX 2070, 610.57.04, 8192 MiB, 5.87 W, [N/A], P8
mesa-dri-drivers-26.1.8-1.fc44.x86_64
mesa-vulkan-drivers-26.1.8-1.fc44.x86_64
libglvnd-egl-1.7.0-9.fc44.x86_64
kernel-core-7.1.5-201.fc44.x86_64
kernel-core-7.1.12-200.fc44.x86_64
kernel-core-7.2.4-200.fc44.x86_64
```

NVIDIA power/P-state is a single telemetry sample, not an idle/active benchmark or overall power-mode determination. Package inventory includes older installed kernels; `uname` identifies the running one. Driver-only content searches (`^DRIVER=` in `uevent`) returned `nvidia` for `/sys/class/drm/card0/device` and `i915` for `/sys/class/drm/card1/device`.

Prior `vulkaninfo --summary` / `eglinfo -B` success is **inherited** from the user's context, the uncommitted master addition and recalled prior verification. Neither command was rerun. Hardware context availability does not prove engine rendering, Intel selection, game correctness, frame pacing, display presentation, or input-to-display latency.

## D. Direct system-file reads: model, policy, display, input

The dedicated Read tool inspected the following attributes; this table is the exact path/result record, not a claim that a shell `cat` script ran. Initial globbing did not traverse DRM/power-supply symlinks; directory reads followed by explicit attribute reads did succeed.

| Path or operation | Result |
|---|---|
| `/etc/os-release` | Fedora Linux 44 (KDE Plasma Desktop Edition); `VERSION_ID=44`, `VARIANT_ID=kde` |
| `/sys/class/dmi/id/sys_vendor` | `Eluktronics Inc.` |
| `/sys/class/dmi/id/product_name` | `MAX-17` |
| `/sys/class/dmi/id/product_version` | `Standard` |
| `/sys/devices/system/cpu/cpufreq/policy0/scaling_driver` | `intel_pstate` |
| `/sys/devices/system/cpu/cpufreq/policy0/scaling_governor` | `powersave` |
| `/sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference` | `power` |
| `/sys/class/power_supply/AC0/online` | `1` |
| `/sys/class/power_supply/BAT0/status` | `Not charging` |
| `/sys/class/power_supply/BAT0/capacity` | `98` (percent) |
| `/sys/firmware/acpi/platform_profile` | File not found |
| Shell `powerprofilesctl get` | Exit 127: `powerprofilesctl: command not found`; nothing installed or changed |
| `/sys/class/drm/card1-eDP-1/status`, `/enabled`, `/modes` | `connected`; `enabled`; two `1920x1080` lines |
| `/sys/class/drm/card0-eDP-2/status`, `/enabled`, `/modes` | `disconnected`; `disabled`; empty modes |
| `/sys/class/drm/card0-DP-1/status`, `/sys/class/drm/card0-DP-2/status`, `/sys/class/drm/card0-HDMI-A-1/status` | All `disconnected` |
| Dedicated Grep, `^N: Name=` in `/proc/bus/input/devices` | 19 name rows: AT Translated Set 2 keyboard; UNIW0001:00 093A:0255 Mouse and Touchpad; sleep/power/lid/video-bus controls; PC Speaker; HDA NVIDIA/Intel audio endpoints. No gamepad-named row |

Kernel connector modes do not establish active desktop resolution or refresh. Display is physically enumerated despite the current tty/no-display-variable session. Input enumeration does not establish physical usability or delivered events. Only policy0 was read; no claim all CPU policies or firmware modes match it.

## E. Primary-source provenance and locators

The pre-existing temporary manual files were read, not edited. A Webfetch call on `https://store.steampowered.com/manual/3920` returned binary PDF text and was unsuitable for reading; its header indicated a different 73-sheet revision. A byte-preserving retrieval was therefore used to authenticate the actual local reading source. Exact successful command:

```sh
python3 -c 'import urllib.request,hashlib,subprocess,datetime; u="https://store.steampowered.com/manual/3920"; r=urllib.request.urlopen(u,timeout=60); b=r.read(); h=hashlib.sha256(b).hexdigest(); local=subprocess.check_output(["sha256sum","/tmp/opencode/tortuga-pirates-2004-manual.pdf"],text=True).split()[0]; print("retrieved_utc="+datetime.datetime.now(datetime.timezone.utc).isoformat()); print("status="+str(r.status)); print("resolved_url="+r.url); print("content_type="+str(r.headers.get("Content-Type"))); print("bytes="+str(len(b))); print("remote_sha256="+h); print("local_sha256="+local); print("identical="+str(h==local)); extracted=subprocess.check_output(["pdftotext","-layout","/tmp/opencode/tortuga-pirates-2004-manual.pdf","-"]); text_hash=subprocess.check_output(["sha256sum","/tmp/opencode/tortuga-pirates-2004-manual.txt"],text=True).split()[0]; print("text_sha256="+text_hash); print("text_matches_fresh_layout_extraction="+str(hashlib.sha256(extracted).hexdigest()==text_hash))'
pdfinfo /tmp/opencode/tortuga-pirates-2004-manual.pdf
```

Results:

```text
retrieved_utc=2026-09-30T06:29:46.419474+00:00
status=200
resolved_url=https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/3920/manuals/manual.pdf?t=1777585034
content_type=application/pdf
bytes=1315110
remote_sha256=d335ca09a46a071206d05ccb93d80af770cc7c5c2606077f1df422cde7c640f1
local_sha256=d335ca09a46a071206d05ccb93d80af770cc7c5c2606077f1df422cde7c640f1
identical=True
text_sha256=235e8ebb152e6c86326101b41e8b1d9382c4a68ae96dade657960c1c97294f59
text_matches_fresh_layout_extraction=True
```

`pdfinfo`: 72 sheets, 1,315,110 bytes, PDF 1.4, producer Acrobat Distiller 7.0 for Macintosh; creation June 6, 2005 and modification October 11, 2006. Producer platform is not the game's edition; Windows installation instructions and PC controls identify the manual's PC subject. Layout header says `6/6/05`. It does not identify a tested game patch version.

The resolved CDN was independently checked with this command, returning HTTP 200, the same byte count and SHA-256 at `2026-09-30T06:30:58.895952+00:00`:

```sh
python3 -c 'import urllib.request,hashlib,datetime; u="https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/3920/manuals/manual.pdf?t=1777585034"; r=urllib.request.urlopen(u,timeout=60); b=r.read(); print("retrieved_utc="+datetime.datetime.now(datetime.timezone.utc).isoformat()); print("status="+str(r.status)); print("bytes="+str(len(b))); print("sha256="+hashlib.sha256(b).hexdigest())'
```

This proves the local source matches the bytes actually obtained through Steam in this pass; it does not explain why the text-mode fetch exposed another revision. Recheck hashes on future retrieval. Temporary files are disposable; locators/URLs/hashes are retained rather than redistributing the copyrighted PDF in the repository.

Page mapping command executed (parses extraction in memory):

```sh
python3 -c 'import subprocess,re; s=subprocess.check_output(["pdftotext","-layout","/tmp/opencode/tortuga-pirates-2004-manual.pdf","-"],text=True); wanted={12,16,18,20,30,32,34,36,38,80,82,134}; print("PDF sheet (1-based) -> printed spread header:"); print("\n".join(str(i)+" -> "+m.group(0) for i,p in enumerate(s.split("\f"),1) if (m:=re.search(r"PiratesPC_ManInt.*Page (\d+)",p)) and int(m.group(1)) in wanted))'
```

| Printed pages used | PDF sheet(s), 1-based | Extracted text lines read for claims |
|---|---|---|
| 12 | 7 | 267–275 |
| 17–21 | 9–11 | 375–528 |
| 22–23 | 12 (spread header also read in text) | 534–571 |
| 32–39 | 17–20 | 797–1007 |
| 81–82 | 41–42 | 2196–2273 |

The two-page spread extraction interleaves left/right columns; claims are attached to printed headings rather than blindly treating adjacent text as one paragraph. No images or footage were treated as watched behavior.

Wikipedia was retrieved by Webfetch at the dossier's R2 URL in Markdown format. The returned content exposed permanent revision `1368363894`; only the introduction and named naval/gameplay sections were used. The manual/Wikipedia surrender wording conflict remains unresolved. R1 and R4–R7 were not reopened.

Tool versions actually queried: `git --version` → 2.55.0; `gh --version` → 2.100.0 (2026-09-03); `python3 --version` → 3.14.7; `pdftotext -v` → 26.01.0. These pin source/inventory reproduction context, not a chosen game toolchain.

## F. Reported footage access and main-agent confirmation

Source: user's verified handoff of the footage-access subagent findings and main-agent confirmation; no exact other-agent command lines or retrieval times supplied. No download, extraction, or image-read command is reconstructed here. The dossier's F01–F03 ledger retains source URLs and edition caveats.

| Reported operation | Result / evidence boundary |
|---|---|
| Public YouTube metadata lookup | `_aFLduBaVeU`: 10min Gameplay, 10:01, title PC2004 / description Windows XP and Elgato. `Maj8TjrkVd4`: Thrym865 naval Ship of Line fight, 3:36, PC unconfirmed. Neither visually authenticated |
| Archive.org G4 download | `https://archive.org/download/g4tv.com-video15505/xp7030sidmeierspirates_flv.mp4` → `/tmp/opencode/pirates-g4-review.mp4`, approximately 19.99 MB |
| ffprobe inspection | 192.708 seconds; 640×480; 24 fps; H.264 video and AAC audio. **Reported measured media metadata**, not observed gameplay or heard audio |
| Overview generation | `/tmp/opencode/pirates-g4-overview.jpg`; samples every 10 seconds, 0 through 190. Generated frame positions are not watched intervals |
| Image reads by subagent and main agent | Both returned `ERROR Cannot read image (this model does not support image input)`. Main confirmation establishes the same modality blocker, not visual confirmation of contents |
| Tool availability | ffmpeg, ffprobe and Pillow present; yt-dlp absent, per report |

**No frames visually observed; no audio heard; actual contents and edition unverified.** Gate B/C now has a concrete image-input limitation rather than only an unidentified source gap. Next choose a vision-capable session or attributed user-assisted observations. Demonstrate a short inspectable segment, establish edition/UI provenance, then record observer, timestamp interval, editing/modification/difficulty/playback uncertainties and audio coverage before using behavioral claims. Independent desk research may continue under Gate A.

Review reconciliation: the handoff reports the main agent rechecked `free -b`: swap total `8589930496`, exactly the existing dossier value `8,589,930,496` and runbook value above. The alleged mismatch requires no inventory correction.

## H. Footage retrieval and frame inspection (supersedes the section F blocker)

Executed 2026-09-30, retrieval finished `06:55:49Z`, in a session-temporary directory that no longer exists; the media was not retained and is not in the repository. `yt-dlp` was run through `uvx` without installing it. Commands as run, `$id` being `_aFLduBaVeU` (F01) or `Maj8TjrkVd4` (F02):

```sh
uvx yt-dlp -q --no-warnings -f 'bv*[height<=480]+ba/b[height<=480]/b' --merge-output-format mp4 --write-info-json -o '%(id)s.%(ext)s' "https://www.youtube.com/watch?v=$id"
uvx yt-dlp -q --no-warnings -f 'bv*[height<=720]/b[height<=720]' -o '%(id)s-hd.%(ext)s' "https://www.youtube.com/watch?v=_aFLduBaVeU"
uvx yt-dlp -q --no-warnings -f '232/136' -o '%(id)s-hd.%(ext)s' "https://www.youtube.com/watch?v=Maj8TjrkVd4"
ffmpeg -v info -i $id-hd.mp4 -vf "select='gt(scene,0.35)',showinfo" -an -f null -
# overview sheets: step 10 s for F01, 5 s for F02
ffmpeg -v error -y -i $id.mp4 -vf "scale=480:-2,drawtext=text='%{pts\:hms}':x=6:y=6:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.7,fps=1/$step,tile=4x3" -q:v 3 sheet-$id-%02d.jpg
# dense sheets from the 720p file for a chosen start, length, and step
ffmpeg -v error -y -ss $ss -t $t -copyts -i $id-hd.mp4 -vf "scale=640:-2,drawtext=text='%{pts\:hms}':x=6:y=6:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.7,fps=1/$step:start_time=$ss,tile=3x4" -q:v 3 dense-%02d.jpg
```

`drawtext` sits before `fps` so each stamp is the source frame's own time. The first 720p attempt on F02 failed with `HTTP Error 403: Forbidden` for the default format; format `232` succeeded. The session's first sheets stamped after `fps` and were discarded.

| File | Stream | Duration | SHA-256 |
|---|---|---|---|
| `_aFLduBaVeU.mp4` | VP9 480×360, 30 fps, Opus | 600.094 s | `7a7982a81285f3429c89b267d1bc51e100ef0ddc1bdfe2886a88b59bc659e83b` |
| `_aFLduBaVeU-hd.mp4` | H.264 960×720, 30 fps, video only | 600.067 s | `baf18c5f5fb73dc79d50e16976cd742e7a10a42f2634c71c91e86d13abadb2ce` |
| `Maj8TjrkVd4.mp4` | VP9 480×360, 30 fps, AAC | 215.295 s | `8595375182a52d5abbe402bbb8764549f18dc49f366e15ec2af032c5ad9cfd3b` |
| `Maj8TjrkVd4-hd.mp4` | H.264 960×720, video only | 215.200 s | `ca3113e629e3b382e66de7322edb9bff0823ef01d8e7c535251fd99491580faf` |

YouTube re-encodes on demand, so a later download may hash differently; the hashes identify what was inspected, not a stable artifact.

Scene-cut times above 0.35, in seconds. F01: 3.5, 44.2, 54.2, 65.2, 71.2, 75.2, 186.1, 209.6, 253.6, 268.8, 270.8, 272.7, 278.6, 317.3, 335.7, 339.1, 354.2, 355.5, 359.1, 400.4, 431.2, 434.7, 435.3, 441.5, 443.7, 454.0, 524.7, 526.5, 543.8, 556.3, 560.3, 566.2, 596.8, 598.4. F02: 172.9, 186.0. This test finds hard cuts only; the F01 edit at 91.7–94.2 s is a dissolve and was found by eye.

Frames inspected: every overview sheet for both recordings (F01 at 10 s, F02 at 5 s), plus dense sheets for F01 9–27 s, 27–45 s, 62–86 s, 168–204 s, and 88.5–96.5 s at 0.5 s, F01 19.9–22.3 s at 0.2 s, F02 0–12 s, and F02 138–192 s. Date stamps were read from enlarged crops of the map's lower-left corner. The F02 plunder-screen damage figures stayed illegible in their second digit at 720p. The G4 file was inspected only through the existing `/tmp/opencode/pirates-g4-overview.jpg`.

Not done: no audio was decoded or heard, no clip was viewed in motion, and no captures were copied into the repository because the frames are third-party copyrighted footage.

## I. Godot 4.7.2 probe: build, render path, and measurements

Executed 2026-09-30, about 07:15–08:00 UTC, in the disposable workspace `/tmp/opencode/tortuga-phase-1-probe/` (RAM-backed tmpfs). Probe sources, scripts, logs, and gzipped frame traces are kept in [`captures/`](captures/); raw rows are in [`measurements.csv`](measurements.csv) and [`assets.csv`](assets.csv).

**Pinned inputs.** `Godot_v4.7.2-stable_linux.x86_64.zip` (77,860,424 bytes), `Godot_v4.7.2-stable_export_templates.tpz` (1,281,349,702 bytes), and `godot-4.7.2-stable.tar.xz`, all from the [4.7.2-stable release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable) and all passing `sha512sum -c` against the release's `SHA512-SUMS.txt`. Engine reports `4.7.2.stable.official.ed1daf0bf`. Kenney Pirate Pack zip SHA-256 `91a0a43446910357e38b877971a94c06e6b3d9d28c035e51c107a1731e84f76a`.

**Isolation.** `captures/probe-src/env.sh` points `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` into the workspace, so templates, the app user directory, and Godot and Mesa shader caches never touch the home directory. Only the x86_64 Linux and Windows templates and `macos.zip` were unpacked.

**Assets and audio.**

```sh
# sprites: PNG/Retina/{Ships,Ship parts,Effects,Tiles} copied with spaces and parentheses removed from names
ffmpeg -v error -y -f lavfi -i "anoisesrc=d=0.7:c=brown:a=0.9:seed=7" -af "lowpass=f=900,afade=t=out:st=0.05:d=0.65,volume=2.5" -ar 44100 -ac 1 cannon.wav
ffmpeg -v error -y -f lavfi -i "anoisesrc=d=20:c=pink:a=0.5:seed=3" -af "lowpass=f=1200,tremolo=f=0.15:d=0.6,afade=t=in:d=1,afade=t=out:st=19:d=1" -ar 44100 -ac 2 -c:a libvorbis -q:a 2 ambient.ogg
```

**Build and export**, from `project/` with `env.sh` sourced:

```sh
$GODOT --headless --import
for p in linux windows macos server; do $GODOT --headless --export-release $p; done
```

**Render path without a desktop session.** The host is a tty session with no display. A virtual KDE compositor gave hardware rendering on the Intel GPU:

```sh
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json   # keep glvnd off the NVIDIA EGL driver
setsid dbus-run-session kwin_wayland --virtual --width 1920 --height 1080 --socket wayland-probe --no-lockscreen --no-global-shortcuts &
WAYLAND_DISPLAY=wayland-probe ./tortuga-probe.x86_64 --display-driver wayland --rendering-driver opengl3 --disable-vsync --fullscreen -- <game args>
```

Every rendered run logged `OpenGL API 4.6 (Core Profile) Mesa 26.1.8 - Compatibility - Using Device: Intel - Mesa Intel(R) UHD Graphics (CML GT2)`. Mesa first prints `failed to create dri2 screen` for the NVIDIA device and then settles on Intel. A screenshot taken through the engine ([`captures/busy-scene.jpg`](captures/busy-scene.jpg)) was read back to confirm the scene actually drew.

**Workload manifest.** 1920×1080 fullscreen, Compatibility renderer, vsync off, uncapped. Normal scene: 4 AI ships plus the player's, each AI ship firing an 8-shot broadside every 3 s. Busy scene: 16 AI ships plus the player's, same firing. Both: a full-screen water shader over one 128-px tile, a 3×3 island, one 40-particle wake emitter per ship, pooled 24-particle smoke bursts, impact sprites, three HUD labels updated every frame, one Ogg loop, pooled WAV shots. The normal scene is heavier than the brief's wording, which did not have ships firing.

**Conditions.** AC online; CPU policy0 governor `powersave`, energy preference `power` (not changed; no root). Load average 0.57 at start. Binary on tmpfs for the frame-time runs and on the NVMe Btrfs root (`/var/tmp`) for the start-up runs.

**Scripts** (all in `captures/probe-src/`): `bench.sh <id> <scene> --warmup=5 --bench=60 --reloads=5` for frame time, RSS at 1 Hz, and reload proxy; `startup.sh <first|cold|warm> 5`; `nettest.sh` for the server scenario. The offline check was:

```sh
unshare -rn sh -c 'ip -o link; curl -s -m 3 https://example.com; ./build/linux/tortuga-probe.x86_64 --display-driver wayland --rendering-driver opengl3 --fullscreen -- --mode=offline --scene=normal --bot=1 --log --shot=shot-offline.png --shot_at=5 --quit_at=8'
```

Inside that namespace the only interface was `lo`, down, and `curl` exited 7.

**Failures and discards, kept on the record.**

- A `pkill -f` pattern matched its own shell and killed the first compositor attempt; nothing was measured in it.
- The first export printed `Couldn't find ... include_filter` errors; the hand-written presets needed `include_filter=""` and `exclude_filter=""`. Builds were re-exported cleanly.
- The benchmark line first tried to print static memory, which a release build reports as 0. The fields were removed and everything re-exported before the recorded runs.
- The first server scenario was discarded: Godot buffers stdout in release builds and the buffered log was lost when the server was stopped with SIGTERM. The recorded run lets the server and some clients quit themselves.
- No audio sink exists in this session (`PulseAudio: sink info error: No such entity`). Audio streams were loaded and played into a device that was not there, so audio mixing cost is probably under-represented.

**Size-optimised template (one follow-up experiment).** Built from the verified 4.7.2 source with SCons 4.11.1 (run through `uvx scons`) and GCC 16.2.1, about two and a half minutes on 16 threads:

```sh
uvx scons -j16 platform=linuxbsd target=template_release arch=x86_64 production=yes use_static_cpp=no optimize=size lto=full \
  disable_3d=yes vulkan=no openxr=no deprecated=no module_text_server_adv_enabled=no module_text_server_fb_enabled=yes \
  module_jolt_physics_enabled=no module_godot_physics_3d_enabled=no module_navigation_3d_enabled=no module_camera_enabled=no \
  module_csg_enabled=no module_gridmap_enabled=no module_gltf_enabled=no module_fbx_enabled=no module_basis_universal_enabled=no \
  module_astcenc_enabled=no module_ktx_enabled=no module_theora_enabled=no module_upnp_enabled=no module_webrtc_enabled=no \
  module_websocket_enabled=no module_webxr_enabled=no module_mobile_vr_enabled=no module_noise_enabled=no module_raycast_enabled=no \
  module_xatlas_unwrap_enabled=no module_lightmapper_rd_enabled=no module_meshoptimizer_enabled=no module_vhacd_enabled=no \
  module_interactive_music_enabled=no
```

The first attempt, without `use_static_cpp=no`, failed at link with `cannot find -lstdc++` because the static C++ runtime package is not installed; the working build therefore depends on the system's `libstdc++.so.6`. The stripped template was set as `custom_template/release` in a fifth export preset. The resulting client drew the same scene (screenshot compared by eye), passed a one-client server check, and was measured with one 60 s busy run and 15 start-up samples. Only a Linux template was built; no Windows or macOS cross-toolchain is installed.

**What these runs do not show.** Display presentation, vsync pacing, and input-to-photon latency (the output is virtual); sustained thermal behavior (60 s runs); anything on Windows or macOS (those packages were exported and never run); behavior at a performance power profile; synchronized combat (only ship position and heading cross the network); real network latency (all clients were on the same host).

## G. Continuation requirements

- **Linux:** LNX-01 is a test host, not a minimum spec. Section I measured it through a virtual output at the `powersave` governor. Still to do in a real desktop session: display pacing with vsync, a normal power profile, and a run of ten minutes or more. Keep Intel, RTX, and software-renderer results separate.
- **Mac (proposed, never executed):** the universal, ad-hoc-signed package is at `/var/tmp/tortuga-probe-build/tortuga-probe-macos.zip` on LNX-01. Suggested steps for the owner, untested: copy and unzip it; if macOS refuses to open it, clear the quarantine flag with `xattr -dr com.apple.quarantine tortuga-probe.app`; then from Terminal run `./tortuga-probe.app/Contents/MacOS/tortuga-probe --disable-vsync --fullscreen -- --mode=offline --scene=busy --bot=0.3 --warmup=5 --bench=60` and return everything it prints, along with model and chip, macOS version, RAM, display resolution and refresh rate, and whether it was on battery. Serial numbers are not needed.
- **Windows (proposed, never executed):** the package is at `/var/tmp/tortuga-probe-build/tortuga-probe-windows.zip`. It still needs an owner-named machine and tester. The same game arguments apply after `tortuga-probe.exe`; release builds print nothing to a console unless run through the console wrapper, which this export did not include, so add `--out=frames.csv` to capture frame times to a file instead.
- **Reference observation:** done in section H; coverage gaps accepted by the owner on 2026-09-30. No session has heard the audio.
- **Evidence growth:** add raw measurement/asset rows only when real runs or selected assets exist. Later plan gates still require representative client/server, offline/authority/pause-empty evidence, budget approval, wider system assessment and owner acceptance.
