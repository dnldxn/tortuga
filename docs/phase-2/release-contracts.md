# Plan 08 — Release contracts

Spec: [issue #11](https://github.com/dnldxn/tortuga/issues/11). Plan: [08.01 / issue #12](https://github.com/dnldxn/tortuga/issues/12). This file holds the machine contracts shared by the release plans. Task 1 defines the toolchain lock and receipt. Later tasks add the bridge, recipe and smoke contracts.

## Toolchain lock — `tools/release/toolchain-lock.json`

`bootstrap_toolchain.py verify` checks the lock's shape (schema version 1) without fetching anything. An invalid or structurally malformed lock exits 1 with an `error:` line.

- **`pins`:** `engine` = `4.7.2.stable`, `velopack` = `1.2.161`. Any artifact carrying `"pin": K` must have `version == pins[K]`.
- **`artifacts.<id>`** (id matches `[A-Za-z0-9_][A-Za-z0-9._+-]*`):
  - `url` — `https://` only. The CLI rejects everything else. `file://` is accepted only when tests call the functions with `allow_file=True`.
  - `file` — relative cache path, with no `..` and not absolute.
  - `format` — `zip` | `tar` | `rpm`. A `tpz` or `nupkg` is a `zip`.
  - `algorithm` (`sha256` | `sha512`) and `digest` — full lowercase hex.
  - `size` — exact bytes. A cached or downloaded file of a different size is rejected.
  - `version`, `license` and `provenance` — where the digest came from.
  - Optional: `pin`; `commit` (full SHA for source pins).
- **`platforms.<key>`** (`linux-x86_64`, `macos-universal`, `windows-x86_64`):
  - `host` — `{system, machine[]}`, matched against Python `platform.system()` and `platform.machine()`.
  - `tools.<name>` — `[artifact_id, relative path inside that artifact's extraction]`.
  - `dump_extension_api` (bool).
  - `cmake.<VAR>` — the name of a tool, `extension_api`, `gdextension_interface` or `gdextension_interface_json`.
  - `probes.<name>.argv` — `$tool` means a locked tool. A bare name is looked up on PATH and only *observed*.
  - Optional `expect` substring. When present, the probe fails closed.
  - `compiler_probes[]` and `compiler` — `{requirement, status}`. `requirement` stays `null` until a native build proves a family or minimum version.
- **Never resolved at runtime:** the lock is the only source of URLs and digests. Moving tags or "latest" are never looked up. Changing a pin means editing the lock with newly verified digests.

## Fetch behavior — `bootstrap_toolchain.py fetch`

```text
python3 tools/release/bootstrap_toolchain.py fetch --platform KEY --lock FILE --output ROOT [--cache DIR]
```

1. Validate the lock. The running host must match `platforms[KEY].host`; otherwise exit 1 before any download or write.
2. Delete any stale `ROOT/toolchain.json`.
3. Download or check every artifact the platform needs. Each lands in `--cache` (default `ROOT/downloads`) at `artifact.file`:
   - A **cached file is re-hashed on every run**. A mismatch fails with a clear message. The tool never silently re-downloads; the operator deletes the corrupt file deliberately.
   - A new download goes to `*.partial` and is renamed only after its size and digest match.
   - Extraction later reopens the verified file. A local actor with write access to the cache could swap it in between. This is accepted for a same-user cache (`ponytail:` note in code).
4. Only after **all** digests pass, extract each artifact into `ROOT/.tmp-<id>-*` (a temp directory inside ROOT), then rename it to `ROOT/<id>`:
   - Absolute members, drive-letter members, `..` members and device/fifo members are rejected in every format.
   - **zip/tpz/nupkg:** symlink members are rejected outright. No locked zip contains a link; this was checked with `zipinfo`, including the macOS `.app` zip. Without links, no write can be redirected.
   - **tar:** after the name pre-check, extraction uses Python's stdlib `tarfile.extractall(filter="data", errorlevel=2)`, which confines symlink/hardlink targets to the destination. Filter rejections and unresolved hardlinks become `unsafe archive member` errors.
   - **rpm:** the payload comes from `rpm2cpio` (argv list). It is parsed in-process from cpio newc into an in-memory tar and goes through the same tar path. Hardlinked cpio files are refused.
   - Any rejection removes the temp directory and exits 1.
5. Run checks:
   - Locked templates `version.txt` must equal `pins.engine`.
   - Locked engine `--version` must start with `pins.engine + "."`.
   - If `dump_extension_api` is set, run `<engine> --headless --dump-extension-api --dump-gdextension-interface --dump-gdextension-interface-json` with cwd `ROOT/extension_api`. The API JSON header must equal the engine pin.
   - Run the probes. Every subprocess uses an argv list (never a shell), with `XDG_*` pointed inside `ROOT/xdg` and .NET telemetry disabled.
6. Write `ROOT/toolchain.json` atomically. Exit 0 and print its path.

## Receipt — `ROOT/toolchain.json` (schema 1)

| Field | Content |
|---|---|
| `schema_version`, `platform`, `root` | `1`, platform key, absolute ROOT |
| `lock_sha256` | sha256 of the canonical (sorted-key) lock JSON used |
| `host` | observed `system`, `machine`, kernel `release`, `python` |
| `pins` | copy of lock pins |
| `tools` | name → **absolute** path, plus `extension_api` / `gdextension_interface` / `gdextension_interface_json` when dumped |
| `artifacts` | id → `url, version, algorithm, digest, size, license, [commit], cache_path, extracted` |
| `verified` | `templates_version`, `engine_version` (actual output) |
| `extension_api` | dumped `header` object and sha256 of the three dumped files, or `null` |
| `compiler` | `lock` (requirement/status as locked) and `observed` (`argv, path, exit, identity` per compiler probe) |
| `probes` | every probe's `argv, path, exit, identity` (`path: null` = not found on PATH) |
| `cmake_args` | `list[str]` of `-DVAR=<absolute posix path>` built from `platforms[KEY].cmake` |

## CMake consumption contract (for Task 2)

`native/CMakeLists.txt` accepts `TORTUGA_TOOLCHAIN_ROOT:PATH` and reads `${TORTUGA_TOOLCHAIN_ROOT}/toolchain.json` with `file(READ)` + `string(JSON)`. The receipt's `cmake_args` may also be passed directly. They define:

- `TORTUGA_VELOPACK_ROOT` — extracted `velopack_libc_1.2.161.zip`, containing `include/Velopack.h(pp)`, `lib/`, `lib-static/`.
- `TORTUGA_GODOT_CPP_ROOT` — godot-cpp source tree at the pinned commit (has `CMakeLists.txt`).
- `TORTUGA_GODOT_EXTENSION_API` — `extension_api.json` dumped from the locked 4.7.2 engine. Pass it to godot-cpp as `GODOTCPP_CUSTOM_API_FILE`.
- `TORTUGA_GODOT_EXTENSION_INTERFACE` — matching `gdextension_interface.h`.
- `TORTUGA_GODOT_EXTENSION_INTERFACE_JSON` — matching `gdextension_interface.json`.
  - godot-cpp 507ed9d8 has no cache option for this file. It always reads `${GODOTCPP_GDEXTENSION_DIR}/gdextension_interface.json` (`cmake/godotcpp.cmake:289`).
  - For 4.7.2 the bundled file is byte-identical to the dump. If a future pin differs, set `GODOTCPP_GDEXTENSION_DIR` to a directory containing the dumped file.

Configure godot-cpp as proved in the feasibility record:

```text
-DGODOTCPP_CUSTOM_API_FILE=<TORTUGA_GODOT_EXTENSION_API> -DGODOTCPP_TARGET=template_release
```

CMake must fail configuration if the receipt is missing, has `schema_version != 1`, has a `platform` that differs from the build target, or names a path that does not exist. Tool paths (`engine`, `dotnet`, `vpk`, `mksquashfs`) are read from `tools` by packaging/smoke scripts, never from PATH.

## Native CMake options and install layout (Task 2)

```text
cmake -S native -B <build> -DCMAKE_BUILD_TYPE=Release -DTORTUGA_TOOLCHAIN_ROOT=<receipt root> [receipt cmake_args] [-DTORTUGA_IDENTITY_HEADER=<file>]
cmake --build <build> --config Release
ctest --test-dir <build> -C Release --output-on-failure [-R launcher | -L identity]
cmake --install <build> --config Release --prefix <staging>/native-runtime
```

- **`TORTUGA_TOOLCHAIN_ROOT:PATH`** (required): read as described above.
  - Each receipt `cmake_args` entry sets its `TORTUGA_*` variable unless that variable was already given with `-D`; an explicit `-D` wins.
  - Every such path must exist.
  - The test-only engine path comes from `tools.engine`.
- **`TORTUGA_IDENTITY_HEADER:FILEPATH`** (optional): Plan 02 passes `<staging>/native/generated/release_identity.h`.
  - It is copied to `<build>/generated/release_identity.h`, and the `tortuga_identity` INTERFACE target exposes that directory.
  - If the variable is set but the file does not exist, configuration fails.
  - When it is absent, `native/common/development_identity.h` is used.
- **Identity header macros** (Plan 02 must define them all):

  | Macro | Development default |
  |---|---|
  | `TORTUGA_IDENTITY_SCHEMA` | `1` |
  | `TORTUGA_APP_ID` | `"org.tortuga.game"` |
  | `TORTUGA_PACKAGE_VERSION` | `"0.0.0-dev"` |
  | `TORTUGA_CHANNEL` | `"dev"` |
  | `TORTUGA_IS_RELEASE` | `0` |

  - A release header sets `TORTUGA_IS_RELEASE 1` and a `0.N.0` version (N ≥ 1). The `identity` CTest enforces this.
  - The development identity can never equal a release version.
  - Task 3 added no macro: the build platform comes from CMake (`TORTUGA_BUILD_PLATFORM` compile definition on the extension), so Plan 02 headers stay platform-neutral.
- **Install layout:** `<prefix>/bin/<launcher>` and `<prefix>/native/bin/<extension library>`. The second mirrors `res://native/bin/` and is named by godot-cpp's suffix: `libtortuga_updater.linux.template_release.x86_64.so` on Linux.
  - Launcher names: `Tortuga` (Linux, macOS) and `Tortuga.exe` (Windows).
  - Plan 02 places the launcher next to the exported Godot, renamed to the prototype sibling: `Tortuga.godot.x86_64` (Linux), `Tortuga.godot.exe` (Windows), `Contents/MacOS/Tortuga.godot` (macOS).
  - These names are prototypes until Task 6 validates them with `vpk`.
- **Launcher contract:**
  - argv[1..] is forwarded byte-exact; no `--` boundary is ever added.
  - The working directory is preserved.
  - POSIX hands off with `execv`, so the Godot PID equals the launcher PID.
  - On Windows, exit 0 means only that Godot was *created*.
  - A missing or non-executable game produces a stderr diagnostic and exit 1.
  - `--veloapp-{install,updated,obsolete,uninstall} <ver>` exits 0 inside Velopack startup without launching Godot.

## Updater bridge (Task 3)

These are Tortuga wrapper names, not upstream Velopack names. The source is `native/updater/`. Plan 03 consumes this API; Plan 02 owns the final manifest schema.

**Extension file.** `res://native/tortuga_updater.gdextension`:

- `entry_symbol = "tortuga_updater_init"`, `compatibility_minimum = "4.7"`.
- `linux.x86_64` points to `res://native/bin/libtortuga_updater.linux.template_release.x86_64.so`. That is the only entry; macOS and Windows entries are added once those libraries are actually built.
- The source tree ships `res://native/.gdignore`, so dev/editor/test runs never load it. Package staging works on a disposable staging copy of `game/`: it copies `<install prefix>/native/bin/*` into that copy's `native/bin/` and deletes the copy's `.gdignore`. The source tree is never modified.
- Compiled libraries are never tracked in `game/`.

**Class:** `TortugaUpdaterBridge : RefCounted`.

| Method | Returns |
|---|---|
| `get_identity()` | `{available: bool, reason: String, identity: {schema, app_id, package_version, channel, platform, is_release}, platform_key: String, os: Dictionary}` |
| `begin_check(target: Dictionary, request_id: int)` | `Error` |
| `begin_download(target: Dictionary, request_id: int)` | `Error` |
| `prepare_apply(request_id: int, restart_args: PackedStringArray)` | `Error` |
| `poll_events()` | `Array[Dictionary]` — new copies, main thread only |
| `is_busy()` | `bool` |
| `request_shutdown()` | `void` — non-blocking |

**`get_identity` fields:**

- `identity` holds the compiled `release_identity.h` macros. `platform` comes from the CMake build target (`TORTUGA_BUILD_PLATFORM`).
- `os` holds observed values: `system`, `machine`, `release` (uname), and on Linux `glibc` (`gnu_get_libc_version`).
- `available` is true only when all of these hold:
  - it is a release build;
  - the running platform equals the build platform;
  - Velopack's default locator succeeds inside this process;
  - the installed `sq.version` id, version and channel equal the compiled identity;
  - the package directory is known.

  Otherwise `reason` names the first failing check.

**Target Dictionary:** a frozen copy is taken at `begin_check`. All keys are required, with the exact types shown:

| Key | Type | Rule |
|---|---|---|
| `app_id`, `channel`, `platform` | String | must equal the compiled identity |
| `version` | String | release line `0.N.0`, N ≥ 1 |
| `base_url` | String | must equal `https://github.com/dnldxn/tortuga/releases/download/v0.<N>/`. Task 4 adds the validated loopback test source. |
| `full_filename` | String | safe basename `*.nupkg` |
| `sha256` | String | 64 lowercase hex characters |
| `size` | int | > 0. It must be a Variant `int`: Plan 03 converts the manifest's JSON number (a float after `JSON.parse`) to an exact int and rejects fractional or out-of-range values first. A float is `ERR_INVALID_PARAMETER`. |
| `minimum_os` | String | `""` or `glibc X.Y` (1–4 digits each) today. Any other value is `ERR_INVALID_PARAMETER`. A well-formed requirement above the observed glibc gives `checked{compatible:false}`. |

**Return codes and events:**

- `ERR_INVALID_PARAMETER` — a malformed or invalid target, a request/target mismatch, or a missing earlier step. Target validation runs first, without locating or touching state.
- `ERR_BUSY` — an operation is running.
- `ERR_UNAVAILABLE` — shut down, apply already prepared, or `get_identity` unavailable. The busy/shutdown/applied checks run under the lock **before** locating, so no second `UpdateManager` is built while a worker is inside the SDK.
- Any of the three codes above is **synchronous with no event and no state change**.
- `OK` from `begin_*` means a worker was started. Its failures arrive later as `error` events.
- `prepare_apply` runs synchronously. `OK` comes with `apply_prepared`. `FAILED` (bytes failed re-verification, unsafe cache, or helper launch failed) comes with exactly one `error` event, and the next attempt needs a new download.
- An unexpected exception inside a worker becomes an `error` event (`internal error…`), never `std::terminate`.

**Sequence:**

1. `begin_check`.
2. `begin_download` with the **same `request_id` and an identical target**, after a `checked` event with `update_available:true`.
3. `prepare_apply` with the same `request_id`, after `downloaded`.

Any failed step clears the later ones.

**Events** have the shape `{request_id: int, kind: String, payload: Dictionary}`.

| kind | payload |
|---|---|
| `checked` | `{compatible: bool, requirement: String, update_available: bool, target: Dictionary}`. No feed request is made when the target is incompatible or not newer than the installed version. |
| `progress` | `{percent: int}`, emitted only when the value changes |
| `downloaded` | `{cached: bool, path: String, target: Dictionary}`. The size and SHA-256 were checked by the bridge. |
| `apply_prepared` | `{silent: false, restart_args: PackedStringArray, target: Dictionary}`. The helper was launched with `--waitPid` = this Godot PID, and the caller must quit within 60 s. |
| `error` | `{message: String}` — for example `feed missing expected release 0.N.0`, a feed/target mismatch, or a cached/downloaded size/SHA mismatch (the selected file is removed) |
| `worker_stopped` | `{}`. Polled once after `request_shutdown`, once the worker has finished and been joined. It carries the last admitted request ID. |

**SDK use** (real adapter): one `UpdateManager` per operation:

- source: `HttpSource(base_url, HttpOptions{TimeoutMilliseconds = 30000 for check | 600000 for download | 0 for apply})`
- options: `UpdateOptions{AllowVersionDowngrade=false, ExplicitChannel=target.channel, MaximumDeltasBeforeFallback=-1}`
- locator: default (none passed)

The cache path is `PackagesDir/<full_filename>`. The bridge refuses to read, reuse or delete the package unless all of these hold:

- every component of the cache directory is a real directory (no symlink);
- each parent is owned by this user or root, and is group/world-writable only if it is a root-owned sticky directory;
- the packages directory itself is owned by `geteuid()` and is not group/world-writable;
- the package file is a regular file (checked with `lstat`; a symlink is refused).

An unsafe directory that already exists makes `get_identity` unavailable. The defaults are Linux `/var/tmp/velopack/<id>/packages`, macOS `~/Library/Caches/velopack/<id>/packages`, and Windows `<root>\packages`.
