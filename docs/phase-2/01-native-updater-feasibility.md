# Plan 08.01 — Native updater feasibility record

Plan: [issue #12](https://github.com/dnldxn/tortuga/issues/12). Spec: [issue #11](https://github.com/dnldxn/tortuga/issues/11). Contracts: [`release-contracts.md`](release-contracts.md).

**Gate status: incomplete.** Task 1 (toolchain) is verified on Linux x86_64 only. That includes a godot-cpp static-library build against the dumped 4.7.2 API. Task 2 (launcher handoff) is verified on Linux x86_64 only, using a development (non-installed) launcher. Task 3 (bridge) is verified on Linux x86_64 only: unit tests with a fake SDK, plus an external probe in which the stock 4.7.2 engine loads the extension in a development run. Installed-package locator proof is pending Task 6. Timeout/shutdown hardening (Task 4) and update proof (Tasks 5–6) have not started. No rendered, audio or human evidence is claimed anywhere in this file.

## Task 1 — Pinned toolchain (2026-10-01)

Host: Fedora Linux 44, kernel `7.2.4-200.fc44.x86_64`, x86_64, headless tty (no display), Python 3.14.7.

### Locked inputs and provenance

| Artifact | Version / pin | Digest source | License |
|---|---|---|---|
| Godot editor, Linux x86_64 / macOS universal / win64 zips | 4.7.2.stable | sha512 from `godotengine/godot-builds` release `4.7.2-stable` `SHA512-SUMS.txt`. The file was fetched again with `gh` and is byte-identical to the cached copy. Every downloaded zip was re-hashed and matches. | MIT |
| Export templates `.tpz` | 4.7.2.stable | same SUMS; `templates/version.txt` = `4.7.2.stable` | MIT |
| `vpk.1.2.161.nupkg` (CLI) | Velopack 1.2.161, commit `92d6a1c91716729d449034df5c50307dcce39493` | sha256 from the GitHub release asset digest. Local re-hash matches. `vpk.nuspec` repository commit equals the pin. | MIT |
| `velopack_libc_1.2.161.zip` (native C/C++ SDK) | 1.2.161 | GitHub release asset digest sha256. Local re-hash matches. | MIT |
| godot-cpp archive | tag `10.0.0-stable` → commit `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5` | sha256 computed locally from `github.com/godotengine/godot-cpp/archive/<sha>.tar.gz` | MIT |
| .NET runtime 10.0.12 (linux-x64, osx-arm64, win-x64) | 10.0.12 | sha512 from the official `release-metadata/10.0/releases.json`. All three downloads were re-hashed and match. | MIT |
| squashfs-tools rpm | 4.6.1-8.fc44 | sha256 computed locally. `rpm -K`: digests/signatures OK. | GPL-2.0-or-later |

Notes:

- **godot-cpp archive stability:** GitHub does not guarantee stable bytes for its generated archive tarballs. If GitHub regenerates the archive, fetch fails closed with a digest mismatch. The fix then is to re-verify the tree against the commit and re-pin, never to skip the check.
- **godot-cpp compiles against the 4.7.2 API on Linux** (see the commands table). The repo bundles `gdextension/extension_api-4-7.json`, whose header says 4.7.0.
  - Compared as JSON, that file differs from the API dumped from the locked 4.7.2 engine **only in `header`**.
  - Its bundled `gdextension_interface.json` is byte-identical to the 4.7.2 `--dump-gdextension-interface-json` output.
  - Not yet proved: loading the built extension in the 4.7.2 engine (Task 3), and macOS/Windows builds.
- **.NET and squashfs-tools are build-host tooling only.** `vpk` runs as `dotnet vpk.dll` on the runtime alone; no SDK is needed. Neither is shipped to players.
  - The `mksquashfs` binary extracted from the rpm links host `liblzo2`, `liblz4`, `libzstd`, `liblzma` and `libz`. All are present on this Fedora 44 host. Another distro needs those libraries.
- **Compilers are host-provided and unproved.** The lock records `requirement: null`. Each receipt records the observed identity. On Linux, GCC 16.2.1 + CMake 4.3.0 + Ninja 1.13.2 is proved to build godot-cpp only; that is not a minimum version. A family or minimum version is locked only after the Task 2/3 native builds pass.

### Commands and results (Linux x86_64)

Run from the repo root.

| Command | Result |
|---|---|
| `python3 -m unittest discover -s native/tests -p 'test_toolchain.py'` before `bootstrap_toolchain.py` existed | exit 1. `ModuleNotFoundError` reported as 1 error (expected) |
| same, after implementation | exit 0. **Ran 5 tests, OK** |
| Review fix: a chained-symlink escape was found in the first hand-written link handling (`x -> .`, `q -> x/x/x/../../..`, `q/PWNED_LINK`). Tar/rpm extraction was replaced with the stdlib `data` filter, zip links are now rejected, and fixtures were added: chained symlink, hardlink-through-escaping-symlink, zip symlink, cpio newc `../`/absolute/escaping-symlink, size mismatch, non-https URL and malformed lock. | `python3 -m unittest discover -s native/tests -p 'test_toolchain.py'`: exit 0. **Ran 5 tests, OK** (the cases are subtests within the 5 named tests) |
| Regression check: a scratch copy of the script was made with `filter="data"` replaced by `filter="fully_trusted"` (`sed`), and the suite was run against it | exit 1. Five subtests FAIL and one ERRORs: tar-symlink-out, tar-symlink-abs, tar-hardlink-out, zip-symlink, tar-hardlink-via-symlink, and the chained-symlink check (`PWNED_LINK` created above ROOT inside the test's temp dir). The fixtures detect the regression; the scratch copy was then deleted. |
| `python3 tools/release/bootstrap_toolchain.py verify --lock tools/release/toolchain-lock.json` | exit 0. `lock OK: 11 artifacts, platforms ['linux-x86_64', 'macos-universal', 'windows-x86_64']` |
| `python3 tools/release/bootstrap_toolchain.py fetch --platform linux-x86_64 --lock tools/release/toolchain-lock.json --output build/phase-2/feasibility/linux-x86_64/toolchain --cache "$HOME/.cache/tortuga-godot-4.7.2/downloads"` | exit 0, about 15 s. All inputs came from the re-verified cache, so the 1.28 GB templates were not re-downloaded. Receipt: `build/phase-2/feasibility/linux-x86_64/toolchain/toolchain.json`. Rerun after the review fixes: exit 0. The squashfs `.build-id` symlinks pass the data filter. |
| `cmake -S <tools.godot_cpp> -B build/phase-2/feasibility/linux-x86_64/godot-cpp-probe -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -DGODOTCPP_TARGET=template_release -DGODOTCPP_CUSTOM_API_FILE=<tools.extension_api>` | exit 0, about 1 s. `The CXX compiler identification is GNU 16.2.1`; `GODOTCPP_GDEXTENSION_API_FILE` = the receipt's dumped `extension_api.json`. The option name comes from `cmake/godotcpp.cmake:142`. |
| `cmake --build build/phase-2/feasibility/linux-x86_64/godot-cpp-probe` | exit 0, 153 s on 16 cores. 1092 Ninja steps, 0 `warning:` lines. Output: `bin/libgodot-cpp.linux.template_release.x86_64.a` (78,059,854 bytes, sha256 `b3a5dc0b375f5235d98e5961c32b9200e64a564fdc0a2a9504c810cb06a77fc0`). Generated `gen/include/godot_cpp/core/version.hpp`: `GODOT_VERSION_MAJOR 4`, `MINOR 7`, `PATCH 2`, `STATUS "stable"`. |
| receipt `tools.engine` `--version` | exit 0. `4.7.2.stable.official.ed1daf0bf` |
| `cat <tools.templates>/version.txt` | `4.7.2.stable` |
| `<tools.dotnet> <tools.vpk> --help` | exit 0. `Velopack CLI 1.2.161, for distributing applications.` (`vpk --version` is not a valid command and exits 1) |
| `<tools.dotnet> --list-runtimes` | `Microsoft.NETCore.App 10.0.12` (receipt root) |
| `<tools.mksquashfs> -version` | exit 0. `mksquashfs version 4.6.1 (2023/03/25)` |
| `fetch --platform macos-universal …` and `fetch --platform windows-x86_64 …` on this host | exit 1. `host mismatch: … run fetch on a native <platform> host`. No output directory was created. |

Facts recorded in the receipt:

- **Dumped extension API:** header `4.7.2 stable official, precision single`.
  - `extension_api.json` sha256 `d0e4c08c03b165156dabe6bfb6a906baf0069189f62035341230a246c86d6986`
  - `gdextension_interface.h` sha256 `640b48188708ba0016f8d7ace9e0e1d3279a41fa1226c59ff3193b15538bd254`
  - `gdextension_interface.json` sha256 `7d8c0a039d9743eb8ebf88681ae0c641d8d3aa5ffca11081745a84da803e09a1`
- **Observed host tools:**
  - `c++`/`cc`: GCC 16.2.1 20260819 (Red Hat 16.2.1-2)
  - CMake 4.3.0
  - Ninja 1.13.2
- **`cmake_args`:** `TORTUGA_VELOPACK_ROOT`, `TORTUGA_GODOT_CPP_ROOT`, `TORTUGA_GODOT_EXTENSION_API`, `TORTUGA_GODOT_EXTENSION_INTERFACE`, `TORTUGA_GODOT_EXTENSION_INTERFACE_JSON`, each an absolute path under the receipt root.
- `git check-ignore -v build/phase-2/feasibility/linux-x86_64/toolchain` → `.gitignore:7:/build/phase-2/`. The extracted toolchain, about 2.7 GB, is ignored.

### Unavailable platforms

| Platform | Status | Owner | Next action |
|---|---|---|---|
| macos-universal | **blocked.** The lock entry has real Godot and .NET (osx-arm64) digests, but nothing was executed. The compiler (Xcode/Apple clang) is unproved. No Intel-host .NET runtime is locked. | repository owner | Run `fetch --platform macos-universal` on the provisioned Apple Silicon Mac (owner-run) and record the receipt here |
| windows-x86_64 | **blocked.** The lock entry has real Godot and .NET (win-x64) digests, but nothing was executed. The MSVC compiler is unproved. | repository owner | Provision a Windows 11 x64 build host, run `fetch --platform windows-x86_64` and record the receipt here |
| Ubuntu LTS (Linux runtime target) | **blocked.** Not a build-host fetch; this is a runtime test target for Task 6. | repository owner | Provision Ubuntu LTS x86_64 for the Task 6 AppImage tests |

## Task 2 — Launcher handoff (2026-10-01)

Same Linux host and receipt as Task 1 (GCC 16.2.1, CMake 4.3.0, Ninja 1.13.2). Sources: `native/CMakeLists.txt`, `native/launcher/main.cpp`, `native/common/development_identity.h`, and under `native/tests/`: `test_launcher.cpp`, `fake_game.cpp`, `netguard.cpp`, `capture_args.gd`.

### Prototype sibling names (validated in Task 6)

These are **prototype names, validated in Task 6** against real `vpk` packages. They are not a final layout.

| Platform | Launcher (Velopack main exe) | Stock exported Godot sibling | Status |
|---|---|---|---|
| Linux x86_64 | `Tortuga` | `Tortuga.godot.x86_64` (same directory) | built + tested here |
| Windows x86_64 | `Tortuga.exe` | `Tortuga.godot.exe` (same directory) | **compile-unproved** |
| macOS universal | `Contents/MacOS/Tortuga` (`CFBundleExecutable`) | `Contents/MacOS/Tortuga.godot` | **compile-unproved** |

### Behavior implemented

1. `main` calls `VelopackApp::Build().SetAutoApplyOnStartup(false).Run()` (pinned `Velopack.hpp`) before anything else. Implicit apply is explicitly disabled.
2. The launcher locates itself from the installed executable, never the CWD: `/proc/self/exe` on Linux, `_NSGetExecutablePath` + `realpath` on macOS, `GetModuleFileNameW` on Windows. The game is that file's sibling (`resolve_game_executable`). Symlinked launchers resolve to the real install directory (tested).
3. `forward_arguments` drops only `argv[0]`. All other arguments pass through byte-for-byte in order. The launcher never adds or removes a `--` boundary.
4. `handoff`:
   - **POSIX:** `execv(game, argv-array)`. No shell. Godot keeps the launcher's PID.
   - **Windows:** `CreateProcessW` with an explicitly quoted program path and CommandLineToArgvW-compatible argument quoting (`windows_command_line`). No handle inheritance. Both handles are closed and the launcher returns 0 as soon as the process is created. That 0 means *creation* succeeded, not that Godot later exited 0. Task 5 must track the real Godot PID.
5. A missing or non-executable game prints one diagnostic line to stderr and exits 1. Example: `Tortuga: cannot start the game at "<abs path>": No such file or directory. Reinstall Tortuga to repair the installation.` There is no repair downloader and no supervisor.
6. **Non-UTF-8 argv:** if any argv element (argv[0] included) is not strict UTF-8, Velopack `Run()` is skipped. The launcher then applies the pinned lifecycle match itself (`is_lifecycle`): two or more arguments with a lower-cased `--veloapp-{install,updated,obsolete,uninstall}` first → exit 0, no Godot. Anything else is forwarded byte-exact. Details are in the findings below.
7. **Diagnostics:** `report()` writes one stderr line. On Windows it also shows a `MessageBoxW` with the same text, because the GUI-subsystem launcher has no visible stderr (compile-unproved).

### Velopack startup findings (pinned source + execution)

Pinned source read: `src/lib-rust/src/{app.rs,constants.rs,locator.rs,manager.rs,logging.rs}` and `src/lib-cpp/src/{lib.rs,types.rs}` at `92d6a1c9…`, fetched with `gh api …?ref=92d6a1c91716729d449034df5c50307dcce39493`.

- **Lifecycle arguments are the same on every OS.** `app.rs:130-138` checks `args.len() >= 2` and lower-cases `args[0]` against `--veloapp-install|--veloapp-updated|--veloapp-obsolete|--veloapp-uninstall` (`constants.rs`). The match is not `cfg`-gated.
  - Hook callbacks are only registered on Windows (`lib-cpp/src/lib.rs`), so on Linux no hook runs. `call_fast_hook` still calls `exit(0)` (`app.rs:219-224`) unless `VELOPACK_DEBUG` is set.
  - Executed result: each hook with a version argument (plus the upper-case variant) exits 0 and Godot is **not** launched.
  - A bare `--veloapp-install` with no version is an ordinary launch and is forwarded.
  - With `VELOPACK_DEBUG=1`, a hook invocation does **not** exit, and the launcher then starts the game with the hook arguments (observed). This is upstream behavior and was left as is.
- **No update discovery request:** `Run()` builds `UpdateManager::new(sources::NoneSource {}, …)` (`app.rs:140`), so it never makes a feed/HTTP request.
  - On a non-installed Linux launcher, the locator fails with `NotInstalled("Could not locate '/usr/bin/' in executable path …")` and `Run()` returns early (`app.rs:141-144`). It performs no apply and no cleanup.
  - Executed check: an `LD_PRELOAD` shim (`netguard.cpp`) records any `socket`/`connect`/`getaddrinfo` call. It recorded **none** during a normal handoff or any lifecycle invocation. A positive control confirms the shim does observe a real `getaddrinfo`.
  - Limitation: the shim only sees libc-routed calls, not raw syscalls. The source reading is the primary evidence.
- **Side effect: log file.** `vpkc_app_run` always initializes file logging before `run()` (`lib-cpp/src/lib.rs`, `logging.rs`).
  - On Linux this writes `$TMPDIR/velopack.log` when not installed (observed), or `velopack_<appid>.log` when installed.
  - The file holds the full forwarded argument list (`VelopackApp: Running with args: [...]`), is rotated at 1 MB, and is not deleted.
  - On macOS it goes to `~/Library/Logs`; on Windows to `%LocalAppData%\velopack` (source only).
  - Tests point `TMPDIR` at a disposable directory, so no log was written to the real `/tmp`.
- **Installed-mode effects (source only, not yet executed; Task 6):**
  - `Run()` deletes local full packages other than the current or pending version (`app.rs:193-194`). With auto-apply off, a pending newer package is kept, not applied.
  - It also **removes `VELOPACK_FIRSTRUN`/`VELOPACK_RESTART` from the environment before the exec** (`app.rs:171-175`), so Godot cannot see them. Plan 03 "Updated to 0.N" must confirm through installed identity, not those variables.
- **Non-UTF-8 argv aborts Velopack:** `VelopackApp::build()` always evaluates `env::args()` (`app.rs:40`), even when `SetArgs` is used. Rust's `env::args()` panics on non-UTF-8, and the panic aborts the process ("panic in a function that cannot unwind", exit 134; observed).
  - **Review correction:** the first version claimed it was safe to skip `Run()` because "Velopack only passes ASCII hook args". That was wrong. `env::args()` includes argv[0], so a launcher installed under a non-UTF-8 directory skipped `Run()`, and a genuine `--veloapp-install 0.1.0` then launched Godot (reproduced by the reviewer and by the new CTest).
  - **Fix:** when `Run()` is skipped, the launcher reapplies the `app.rs:130-138` match (≥2 args, ASCII-lower-cased `args[0]` equals a hook) and exits 0 without a handoff. `VELOPACK_DEBUG` is not honored on this path.
  - **Strict validation:** the UTF-8 check now matches Rust's strict rules. It rejects lead bytes C0, C1 and F5–FF, and the second byte must be A0–BF after E0, 80–9F after ED, 90–BF after F0 and 80–8F after F4.
    - Before the fix, `C0 80` (overlong), `ED A0 80` (surrogate), `F4 90 80 80` and `F5 80 80 80` (above U+10FFFF) passed the lax check and Velopack aborted with exit 134 (observed).
  - **Consequence of skipping `Run()`:** a non-UTF-8 launch also skips installed-mode package cleanup, `VELOPACK_FIRSTRUN`/`VELOPACK_RESTART` stripping and the first-run/restart hooks. Velopack itself never sets non-UTF-8 arguments, so the only ordinary trigger is a non-UTF-8 install path; Task 6 should check whether `vpk` even permits one.
  - Plan 03 must not call `SetArgs`/`Run`-dependent APIs with arbitrary user bytes.

### Commands and results (Linux x86_64)

`TR=$PWD/build/phase-2/feasibility/linux-x86_64/toolchain`, `B=build/phase-2/feasibility/linux-x86_64/native`, and `ARGS` = the receipt's `cmake_args`, joined.

| Command | Result |
|---|---|
| `cmake -S native -B $B -G Ninja -DCMAKE_BUILD_TYPE=Release -DTORTUGA_TOOLCHAIN_ROOT=$TR $ARGS` | exit 0 (0.8 s) |
| `cmake --build $B --config Release` (RED: helpers stubbed to return empty/1) | exit 0, 8 Ninja steps |
| `ctest --test-dir $B -C Release --output-on-failure -R launcher` (RED, first run) | exit 8. **0/10 passed.** Eight cases failed assertions. `windows_quoting` and `real_godot` aborted on `std::out_of_range` while parsing empty output; that is a test bug, fixed so those two report assertions too. |
| same (RED, rerun after the harness fix) | exit 8. **0/10 passed.** All ten fail on assertions (e.g. `args exact [] == [<a b><><"q">…]`, `game NOT launched … exit 0 (got 1)`, `real godot --version via launcher:`). |
| build + same ctest after implementing `main.cpp` | exit 8. 9/10. `quotes_and_empty_args` failed because the marker filename contained the label's `/` (test bug; markers now use a counter). |
| same, rerun | exit 0. **10/10 passed.** |
| Added the non-UTF-8 argument case to `quotes_and_empty_args` → ctest | exit 8. 9/10, launcher exit 134 (the Velopack `env::args` abort above) |
| Implemented the UTF-8 guard → `ctest … -R launcher` | exit 0. **10/10 passed.** |
| `ctest --test-dir $B -C Release -V` (full; log `build/phase-2/feasibility/linux-x86_64/task2-ctest-verbose.log`) | exit 0. **11/11 tests** (10 `launcher`, 1 `identity`). Before the review fixes: 91 `ok`, 0 `FAIL`. After the review fixes (clean reconfigure + rebuild, 0 compiler warnings): **152 `ok`, 0 `FAIL`**. |
| `cmake --install $B --config Release --prefix build/phase-2/feasibility/linux-x86_64/staging/native-runtime` | exit 0. Installs exactly `native-runtime/bin/Tortuga`. |
| Configure with `-DTORTUGA_IDENTITY_HEADER=<scratch header: 0.3.0, linux-test, IS_RELEASE 1>`, build `test_launcher`, `ctest -R identity` | exit 0 / 0 / 1/1 passed. The release-identity branch compiles and validates `0.N.0`. |
| Review fix, RED: added a non-UTF-8 install-dir lifecycle case and the strict-UTF-8 argument cases, then `ctest … -R launcher` | exit 8. **8/10.** The four strict-reject sequences exit 134. All six non-UTF-8-dir hook invocations launched the game. |
| Review fix, GREEN: strict `valid_utf8`, `is_lifecycle` fallback, `report()`/MessageBoxW, `narrow()` via `WideCharToMultiByte`, `_n GREATER 0` guard → `ctest … -R launcher` | exit 0. **10/10.** |
| Receipt with `cmake_args: []`, with and without `-DTORTUGA_VELOPACK_ROOT=<sdk>` | exit 1 (`TORTUGA_VELOPACK_ROOT … must contain include/Velopack.hpp`) / exit 0 |
| Configure with a missing identity header / no `TORTUGA_TOOLCHAIN_ROOT` / root without a receipt / receipt with `platform: macos-universal` / `cmake_args` path that does not exist | each exit 1 with a `CMake Error` naming the problem |

The `launcher_paths_and_arguments.*` CTest cases (label `launcher`) start every process with fork+execve (no shell):

| Case | What it proves |
|---|---|
| `helpers` | Sibling resolution under a Unicode path. `forward_arguments` drops only argv[0] and adds no boundary. |
| `windows_quoting` | `windows_command_line` round-trips spaces, empty arguments, quotes, backslash runs, trailing backslashes, tabs, `--` and Unicode through a CommandLineToArgvW-rule parser written in the test. **Model-based** until it runs natively: it checks the quoting against my reading of the documented rules, not against Windows `CommandLineToArgvW` or the MSVC CRT. |
| `unrelated_cwd` | Launched from an unrelated CWD containing a decoy `Tortuga.godot.x86_64`, then through a symlink. The game is always the install sibling, the CWD is preserved, PID equals the launcher PID (exec), no descriptors leak, and there is no network. |
| `unicode_path` | Install directory `Tört ugä ⚓ 船 dir` under a temp root with spaces and `✓`. |
| `quotes_and_empty_args` | `a b`, empty string, `"q"`, `'s'`, `$HOME`, `*`, `` `id` ``, `; echo pwned` and `\` arrive unchanged, and no shell side effect occurs. The non-UTF-8 `\xff\xfe` and the strict-UTF-8 rejects `C0 80`, `ED A0 80`, `F4 90 80 80` and `F5 80 80 80` are forwarded byte-exact (no 134 abort). Valid `U+D7FF U+10FFFF` is forwarded. |
| `user_boundary` | `--headless -- u1 -- u2` arrives unchanged with no boundary added. With no boundary in the input, none is added. |
| `missing_game`, `nonexecutable_game` | Nonzero exit, a stderr diagnostic naming the absolute game path plus "Reinstall", and no game process. |
| `lifecycle_only` | All four `--veloapp-*` hooks with a version (and one upper-case hook) exit 0 with **no game launched** and no network. A bare hook flag is forwarded. In an install directory named `inst \xff dir` (non-UTF-8 argv[0], so `Run()` is skipped), the four hooks plus a mixed-case hook and a hook with a non-UTF-8 version all exit 0 without launching the game. A bare hook flag and an ordinary launch are still forwarded. Netguard positive control. |
| `real_godot` | Copies the receipt engine as `Tortuga.godot.x86_64` into `…/Tört ugä ⚓ real/` next to the built launcher, and runs from an unrelated CWD with isolated XDG. |

`real_godot` in detail:

- `<launcher> --headless --version` → `4.7.2.stable.official.ed1daf0bf`, exit 0.
- `<launcher> --headless --path <repo>/game --script <repo>/native/tests/capture_args.gd --quit-after 5 -- "a b" "" '"q"' --x` → exit 0. The capture shows:
  - Godot `OS.get_process_id()` == launcher PID (exec replacement);
  - `OS.get_executable_path()` == the installed sibling;
  - `/proc/self/cmdline` after argv[0] == the forwarded list exactly, with exactly one `--`;
  - `OS.get_cmdline_user_args()` == `["a b", "", "\"q\"", "--x"]`.

### Linkage, size and runtime requirements (Linux launcher)

- **Velopack static library:** `velopack_libc_linux_x64_gnu.a` links with only `Threads::Threads` + `${CMAKE_DL_LIBS}` (`-ldl`). GCC added libstdc++/libm/libgcc_s. No other system libraries were needed; there were no link errors.
- **Size:** installed `bin/Tortuga` is **5,907,040 bytes**, unstripped with debug info (sha256 `c586a7b6b4f8bd8a65b1ec532668b1f5144b039bf6084a845211a1b581c89b80`, post-review build; the earlier build was 5,903,032). `strip` brings it to **2,537,712 bytes**. Stripping during packaging is a Plan 02 decision.
- **`ldd`:** `linux-vdso.so.1`, `libstdc++.so.6`, `libm.so.6`, `libgcc_s.so.1`, `libc.so.6`, `/lib64/ld-linux-x86-64.so.2`. `NEEDED`: libstdc++, libm, libgcc_s, libc, ld-linux.
- **Required symbol versions:** `GLIBC_2.39` (non-weak version requirement, from Rust std `pidfd_spawnp`/`pidfd_getpid` resolved against host glibc 2.43), `GLIBCXX_3.4.26`, `CXXABI_1.3.9`. The stock Godot 4.7.2 binary needs only `GLIBC_2.28`.
  - **Consequence:** a launcher built on this Fedora 44 host cannot start on glibc < 2.39 (e.g. Ubuntu 22.04's 2.35).
  - Plan 02 / Task 6 must build Linux release launchers in an older-glibc environment (or prove otherwise) before declaring a Linux minimum OS. This host's build is **not** release-portable evidence.

### Not proved / blocked

| Item | Status | Owner | Next action |
|---|---|---|---|
| Windows launcher (`CreateProcessW`, `wmain`, `/SUBSYSTEM:WINDOWS` + `wmainCRTStartup`, static CRT because the `.lib` declares `/DEFAULTLIB:LIBCMT`) | **blocked: compile-unproved.** The POSIX CTest harness is not built on Windows. Required Win32 system libraries for the static `.lib` are unknown (only `OLDNAMES`/`LIBCMT` defaultlibs are embedded). Failures show a `MessageBoxW`, because GUI-subsystem stderr is invisible. `wmain` arguments are converted with `WideCharToMultiByte`; lone UTF-16 surrogates become U+FFFD, so they are not round-tripped. `windows_quoting` is model-based only. | repository owner | Build on a Windows 11 x64 host. Add any missing system libraries from link errors. Port the cases to `CreateProcessW`, including "launcher exit 0 = creation only". |
| macOS launcher (`_NSGetExecutablePath`+`realpath`, `execv`, both thin `osx_*_gnu.a` linked) | **blocked: compile-unproved.** Universal-slice handling and framework requirements are unknown. | repository owner | Build universal on the Apple Silicon Mac. Run `ctest -R launcher` natively; record `lipo`/`otool -L`. |
| Installed-package behavior (locator success, package cleanup, env removal, hooks under a real AppImage) | not executed. A dev launcher only reaches `NotInstalled`. | Task 6 | Run against `vpk`-packed fixtures |
| Linux portability (glibc 2.39 floor of this build) | open | Plan 02 / Task 6 | Build in an older-glibc environment, then re-run `ldd`/`readelf -V` |

## Task 3 — Asynchronous bridge and installation locator (2026-10-01)

Same Linux host and receipt as Tasks 1–2. Sources:

- `native/updater/updater_bridge.{h,cpp}` — the plain C++ core: state machine, event queue, target freeze, integrity check, SHA-256, and the real Velopack adapter.
- `native/updater/register_types.cpp` — the Godot `TortugaUpdaterBridge` wrapper.
- `native/tests/test_bridge.cpp` — fake-SDK CTests.
- `native/tests/probe.gd` — the external probe.
- `game/native/tortuga_updater.gdextension` and `game/native/.gdignore`.
- `native/CMakeLists.txt` — adds the core library, godot-cpp, the extension, and the tests.

The contract is in [`release-contracts.md`](release-contracts.md#updater-bridge-task-3).

### Design (as built)

- **Narrow SDK seam.** `tortuga_updater::Sdk` has four calls: `locate`, `check`, `download`, `apply`. Errors are thrown.
  - The real implementation, `VelopackSdk`, builds one `Velopack::UpdateManager` per call and keeps it alive for that call: `HttpSource(<exact base>, HttpOptions{TimeoutMilliseconds})`, `UpdateOptions{AllowVersionDowngrade=false, ExplicitChannel=<target channel>, MaximumDeltasBeforeFallback=-1}`. No explicit locator is passed.
  - The tests use `FakeSdk`. No Velopack type leaves `updater_bridge.cpp`.
- **Deadlines.** `kCheckTimeoutMs = 30000` and `kDownloadTimeoutMs = 600000` are passed per call. The fake asserts them. Task 4 tests the real deadlines.
- **One worker.** There is one `std::thread`, and the job holds a `shared_ptr` to the shared state.
  - Progress callbacks run on the worker thread. Velopack's cpp `vpkc_download_updates` drains progress on the calling thread (`src/lib-cpp/src/lib.rs` around L429-446). The callbacks only append to the mutex-protected queue, and only when the percent value changes.
  - `poll_events` moves the queue out under the mutex. The Godot wrapper turns it into fresh `Dictionary` values on the main thread.
- **Shutdown.**
  - `request_shutdown` only sets a flag. It never blocks, and it stops later admission and apply.
  - `worker_stopped` is queued by the next `poll_events` that sees the worker idle. That call joins the finished thread, which returns immediately.
  - The destructor sets the flag and **joins**. Code is never unloaded under a running thread, and the thread is never detached.
  - Task 4 must still harden this: destroying a busy bridge blocks the caller until the SDK call returns (bounded only by its deadline).
- **Check.**
  - A target that is not newer than the installed version, or that is OS-incompatible, gets `checked{update_available:false}` with **no feed request**.
  - Otherwise `CheckForUpdates` runs:
    - `null` → error `feed missing expected release <v>`.
    - A returned `TargetFullRelease` whose id, version, filename, SHA-256, size or Full type differs from the frozen target → error.
- **Download.**
  - Download requires the same request ID and a target identical to the one frozen by a successful check.
  - The frozen target is passed as the `UpdateInfo` (full only), so there is no second feed request. Velopack then verifies its SHA-256 (`manager.rs:452-456`, `537-560`).
  - **Cached package:** pinned `download_updates` returns early when `PackagesDir/<FileName>` already exists (`manager.rs:414-417`). The bridge therefore checks the size and its own SHA-256 of any existing file before reuse.
  - On mismatch, the bridge deletes **only that file** and emits an error. A retry then downloads fresh bytes.
  - After a download, size and SHA-256 are checked again.
- **Apply.**
  - Apply requires the same request ID and a completed, verified download.
  - The bridge re-verifies size and SHA-256 on the calling (main) thread. It then calls `WaitExitThenApplyUpdates(asset, silent=false, restart=true, restart_args)` in the calling process; `--waitPid` is `std::process::id()` (`manager.rs:637-640`).
  - `apply_prepared` is emitted only if that call returns without error. Failure leaves the bridge usable and requires a new download.
  - `silent=false` because `--silent` makes `ask_user_to_elevate` fail (`src/l18n/src/dialogs.rs:103-105`), and the AppImage replacement falls back to `pkexec` when `mv` fails (`src/bins/src/commands/apply_linux_impl.rs`). The value is recorded in the `apply_prepared` payload.
- **Identity.** `get_identity` combines:
  - the compiled `release_identity.h` macros, plus `TORTUGA_BUILD_PLATFORM` (a CMake compile definition);
  - the observed OS: `uname` plus `gnu_get_libc_version()`;
  - the SDK locator.

  The result is unavailable when any of these hold:
  - the build is a development build;
  - the running platform ≠ the build platform;
  - the locator fails;
  - the installed app id, version or channel ≠ the compiled values;
  - the package directory is unknown.

  The installed channel is read from the located `sq.version` `<channel>`, and its `<id>/<version>` must equal the SDK's `GetAppId`/`GetCurrentVersion`.
- **Target validation.**
  - Fixed app/channel/platform must equal the compiled identity.
  - The version must be `N.N.N`.
  - `base_url` must equal `https://github.com/dnldxn/tortuga/releases/download/v<M>.<m>/`, derived from the version.
  - The filename must be a safe basename ending in `.nupkg`.
  - SHA-256 must be 64 lowercase hex characters, and the size must be > 0.
  - `minimum_os` must be `""` or `glibc X.Y` with 1–4 digit parts. Anything else is rejected as an invalid target until Plan 02 fixes the grammar. The digit bound is what keeps `std::stoi` from throwing (see the review round below).
  - The version must be `0.N.0` with N ≥ 1, the only release-line form.
  - Task 4 must add the validated loopback test base. Today only the public base is accepted (`ponytail:` note).

### Locator findings (pinned source, `92d6a1c9…`)

Velopack's default discovery is `UpdateManager::new_boxed` → `auto_locate_app_manifest(LocationContext::FromCurrentExe)` when no locator config is given (`src/lib-rust/src/manager.rs:213-218`). It runs inside **the Godot process**, because the extension is loaded there.

| OS | How default discovery works (locator.rs) | Renamed Godot sibling | Status |
|---|---|---|---|
| Linux | `current_exe()` must contain `/usr/bin/`. `UpdateNix` and `sq.version` must exist in `<mount>/usr/bin/`, and **`$APPIMAGE` must be set and exist** (L463-559). `PackagesDir` = `/var/tmp/velopack/<app id>/packages` unless overridden. | The launcher `execv`s Godot inside the same mount (`<mount>/usr/bin/Tortuga.godot.x86_64`), so `current_exe` still contains `/usr/bin/`. The AppImage runtime's `$APPIMAGE` survives `execv`. Pinned `VelopackApp::Run` removes only `VELOPACK_FIRSTRUN`/`VELOPACK_RESTART` (`app.rs:171-175`). | **Source-derived: default discovery should work, so no explicit locator was added.** Installed AppImage proof is **pending Task 6**. |
| macOS | `current_exe()` must contain `.app/`, `Contents/MacOS/UpdateMac` must exist, and the manifest is `Contents/MacOS/sq.version` or `Contents/Resources/sq.version` (L562-622). `PackagesDir` = `~/Library/Caches/velopack/<id>/packages`. | `Contents/MacOS/Tortuga.godot` contains `.app/` | **blocked:** source only, compile-unproved |
| Windows | `parent(current_exe)/Update.exe`, else a search for `\current\` in the path; root = prefix (L397-460). `PackagesDir` = `<root>\packages`, or a `%LocalAppData%\<id>` fallback when the root is not writable (L133-186). | `<root>\current\Tortuga.godot.exe` → `\current\` match | **blocked:** source only. The bridge's packages-dir derivation ignores the LocalAppData fallback (marked in code). |

- **Executed on Linux (non-installed):** with the real pinned SDK, `test_bridge identity_and_locator` and the external probe (whose locator call runs inside the stock Godot process) get `NotInstalled("Could not locate '/usr/bin/' in executable path …")`. The result is `available=false`.
  - Constructing the manager makes no network request and writes no `velopack.log`: the probe's `$TMPDIR` stayed empty, because file logging is only initialized by `vpkc_app_run`.
- **Package directory:** the bridge needs `PackagesDir` to verify cached bytes, but the pinned C++ API does not expose the locator's paths.
  - `derive_layout` therefore recomputes the default paths with the same rules as the table above, and only after the SDK has located the app.
  - It cross-checks `sq.version` `<id>/<version>` against the SDK. If they disagree, the result is unavailable.
  - Task 6 must confirm that this equals the directory Velopack actually writes to under an installed AppImage.
- **User path unchanged:** `OS.get_user_data_dir()` in the probe = `<XDG_DATA_HOME>/godot/app_userdata/Tortuga`.
- **SDK side effect (source, `manager.rs:426-431`, `475-480`):** a successful `download_updates` deletes every other `*.nupkg` and `*.partial` in `PackagesDir`. Bridge cache removal happens only while this bridge owns its single operation. It does **not** hold Velopack's `.velopack_lock`, so a second running Tortuga instance could race. That is a Task 6 "busy multi-launch lock" case.

### `.gdextension` and the absent-library decision

`game/native/tortuga_updater.gdextension`:

- `entry_symbol = "tortuga_updater_init"`, `compatibility_minimum = "4.7"`.
- `linux.x86_64 = res://native/bin/libtortuga_updater.linux.template_release.x86_64.so` (godot-cpp's own suffix).
- There is only the `linux.x86_64` entry. macOS and Windows entries are added once those libraries are built (review round 1 dropped the unproved placeholders).

Experiment: a scratch copy of `game/` with the file and no library.

- `--import` and `--quit-after 30` both exited 0, but **every run printed 3 `ERROR` lines**: `Can't open dynamic library, file not found`, `GDExtension dynamic library not found`, `Error loading extension`. These come from `core/extension/gdextension.cpp:810` and `gdextension_manager.cpp:333`, through `.godot/extension_list.cfg`.
- **Mitigation:** an empty `game/native/.gdignore`. The editor filesystem scan (`_scan_extensions`) then never registers the extension, so no load is attempted.
  - With it, the same import and run printed 0 errors and no `extension_list.cfg` was created.
  - The library stays untracked; it is built into `build/` only.
  - Package staging (Plan 02) and the probe work on a disposable staging copy of `game/`. They place the library at the `.gdextension` path and delete `.gdignore` in that copy only.
  - `.gitignore` was not edited, and neither file is ignored (`git check-ignore` exit 1).

### Commands and results (Linux x86_64)

`TR=$PWD/build/phase-2/feasibility/linux-x86_64/toolchain`, `B=build/phase-2/feasibility/linux-x86_64/native`, `ARGS` = the receipt's `cmake_args`.

| Command | Result |
|---|---|
| `cmake -S native -B $B -G Ninja -DCMAKE_BUILD_TYPE=Release -DTORTUGA_TOOLCHAIN_ROOT=$TR $ARGS` | exit 0 (1.3 s). godot-cpp `add_subdirectory` with `GODOTCPP_TARGET=template_release` and `GODOTCPP_CUSTOM_API_FILE=<receipt extension_api.json>` (`GODOTCPP_GDEXTENSION_API_FILE` echoed). |
| RED: `updater_bridge.cpp` replaced by an inert stub with the same interface, `cmake --build $B --target test_bridge`, then `ctest --test-dir $B -C Release --output-on-failure -R bridge` | build exit 0. ctest **exit 8, 0/4 passed**: `identity_and_locator` and `sha256` Failed, `serialized_events` and `target_mismatch` **Timeout** (60 s; their `drain_until` waits for events the stub never emits). 50 `FAIL` / 21 `ok` lines before the timeouts (log `task3-ctest-bridge-red.log`). |
| GREEN: real `updater_bridge.cpp` restored, rebuild `test_bridge`, same ctest | exit 0, **4/4 passed** |
| `cmake --build $B` (first extension link) | exit 1: `ld: cannot find -lstdc++`. godot-cpp defaults `GODOTCPP_USE_STATIC_CPP=ON` (`cmake/linux.cmake:18`), and this host has no `libstdc++.a`. Fix: `GODOTCPP_USE_STATIC_CPP=OFF` on Linux (dynamic libstdc++, like the launcher). |
| reconfigure + `cmake --build $B` | exit 0, 0 `warning:` lines. godot-cpp was compiled across an interrupted run and this one, so no single clean timing exists. Task 1's standalone build took 153 s. |
| Review fix: `--exclude-libs,ALL`, rebuild | The dynamic symbol table went from all Rust `vpkc_*` exports to `tortuga_updater_init` (+3 libstdc++ `bad_variant_access` typeinfo symbols) |
| `ctest --test-dir $B -C Release -V` (full, before review round 1) | exit 0. **15/15 tests** (10 launcher, 1 identity, 4 bridge). Bridge cases: **129 `ok`, 0 `FAIL`** (21 identity_and_locator, 27 serialized_events, 75 target_mismatch, 6 sha256). Superseded by review round 1 below. |
| `cmake --install $B --config Release --prefix build/phase-2/feasibility/linux-x86_64/staging/native-runtime` | exit 0. Installs `bin/Tortuga` and `native/bin/libtortuga_updater.linux.template_release.x86_64.so` |
| Probe: copy `game/` to `build/phase-2/feasibility/linux-x86_64/probe-project/game`, delete `.godot` and `native/.gdignore`, copy the installed `.so` to `native/bin/`. Isolated `XDG_*` and `TMPDIR` under probe-project. `<receipt engine> --headless --path <copy> --import` | exit 0, 0 `ERROR` lines. `extension_list.cfg` = `res://native/tortuga_updater.gdextension` |
| `<receipt engine> --headless --path <copy> --script <repo>/native/tests/probe.gd` | exit 0, **19 ok / 0 FAIL**, 0 `ERROR` lines. See details below. After review round 1: **20 ok / 0 FAIL**. |
| `GODOT=$P/bin/… bash game/tests/run_settings_checks.sh` (with `game/native/` present, library absent) | exit 0. Guard rejection OK. **Tests: 3037 checks, 0 failures.** Probes write 7, read 13, corrupt 2, fallback 8, restore 1, read-defaults 14, all 0 failures. 7 `ERROR` lines, all the deliberate invalid-ID/corrupt-settings ones (none GDExtension). |
| `bash game/tests/run_settings_checks.sh --self-test-failure` | exit 1 (expected) |
| `"$GODOT" --headless --path game --quit-after 30` | exit 0, 0 error/GDExtension lines |

Probe details:

- `TortugaUpdaterBridge` is registered, extends `RefCounted`, and instantiates.
- `get_identity` keys are `available, reason, identity, platform_key, os`, with `available=false` and `reason="development build: never update eligible"`.
- Nested identity: `{schema 1, org.tortuga.game, 0.0.0-dev, dev, linux-x86_64, is_release false}`. `os`: `{system Linux, machine x86_64, release 7.2.4-200.fc44.x86_64, glibc 2.43}`.
- `begin_check` returns `ERR_UNAVAILABLE` (2) for a valid target. Since review round 1, a malformed `{}` target or a float `size` returns `ERR_INVALID_PARAMETER` without locating. `begin_download` and `prepare_apply` return `ERR_UNAVAILABLE`.
- `poll_events` returns `[]`. After `request_shutdown` it returns one `{request_id, kind:"worker_stopped", payload}` Dictionary, then `[]`.
- Reported: PID 771003, `OS.get_executable_path()` = receipt engine, `user_data_dir` = `<probe xdg>/data/godot/app_userdata/Tortuga`.

Fake-SDK CTest cases (label `bridge`):

| Case | What it proves |
|---|---|
| `bridge_identity_and_locator` | A development identity, missing install, wrong app id/version/channel, unknown package directory, running platform ≠ build platform, or locator exception is each unavailable, and `begin_check` then returns unavailable. A matching install is available. `os` carries glibc. The real pinned SDK in the non-installed test process returns `NotInstalled`, so unavailable. |
| `bridge_serialized_events` | Work runs on the worker thread. With the worker held inside the SDK, a second `begin_check`/`begin_download`/`prepare_apply` returns busy and no event appears early. Changing the caller's `Target` after `begin` does not change what the SDK sees or the `checked.payload.target`. Every event carries its request ID. Progress `0,0,10,10,55,100` → 4 events. Deadlines are 30000/600000. `request_shutdown` returns in < 100 ms while busy and stops admission; `worker_stopped` appears only after the worker finishes, exactly once and last. The destructor returns only after the SDK call finishes. |
| `bridge_target_mismatch` | These are rejected before any SDK call: 16 invalid targets (app/channel/platform, unnormalized, patch or major version, foreign host, wrong tag base, `../` and non-nupkg filenames, upper-case/short SHA, zero size, huge, 5-digit or unknown-grammar `minimum_os`). A non-std exception thrown inside the worker becomes an `error` event. These produce `error`, and download is refused afterwards: a null feed for a newer target, or a feed whose version/filename/SHA/size/type/package id differs. A not-newer or glibc-incompatible target gives `checked` without a feed request. Apply/download preconditions: wrong request, changed target, or apply before download → invalid. A corrupt download is removed and causes an error. A tampered same-size cached file causes an error, only that file is removed (a sibling package survives), and the SDK is not called. The retry succeeds and a valid cache is reused. Bytes swapped before apply → refused and removed. A helper failure → error, and the bridge stays usable. Success → SDK apply with the frozen target, `silent=false` and the exact restart args, then nothing more is admitted. |
| `bridge_cache_safety` | Covers the cache owner/mode/symlink rules and the refuse-without-deleting behavior (see review round 1). |
| `bridge_sha256` | FIPS 180-4 vectors: empty, `abc`, the 448-bit message and 1,000,000×`a`. The file and in-memory hashes agree across 64 KiB chunks. |

### Review round 1 fixes (2026-10-01)

| Finding | Fix | Test |
|---|---|---|
| **Critical:** `os_compatible` used `std::stol` on unbounded digits. `glibc 99999999999999999999.1` threw `out_of_range` from `begin_check` after admission had set busy, which would `std::terminate` Godot. | (1) `minimum_os` is validated in `validate_target` as `""` or `^glibc ([0-9]{1,4})\.([0-9]{1,4})$`, otherwise invalid. (2) The observed glibc is parsed with the same bound, using `stoi`. (3) The compatibility check runs before busy is reserved. (4) `start()` wraps every job in `catch (std::exception)` / `catch (...)` → `error` event. | `bridge_target_mismatch`: huge, 5-digit and unknown-grammar `minimum_os` → invalid, with no SDK call. A fake SDK that does `throw 42` inside `check` → one `error "internal error"`, and the bridge is idle afterwards. **Mutation check:** removing the validation gives 3 FAILs; removing the worker catch makes `test_bridge` abort (exit 134, `terminate called after throwing an instance of 'int'`). |
| The contract claimed every failure emits an `error` event | Contract corrected: a synchronous non-OK return has no event and no state change. Only worker failures and `prepare_apply` `FAILED` emit `error`. | — |
| `admit()` called `locate()` (a new `UpdateManager`) before the busy/shutdown check, and the wrapper called `identity()` just to pick an error code | `admit()` reserves busy under the lock first (shutdown/applied → unavailable, busy → busy), then locates, releasing busy if unavailable. `prepare_apply` uses the same path. Target validation happens before `admit`. The wrapper returns `ERR_INVALID_PARAMETER` for a malformed Dictionary without calling `identity()`. | `bridge_serialized_events`: three busy rejections leave the fake's `locate` count unchanged. `bridge_identity_and_locator`: a dev bridge given an other-channel target → invalid before locating. Probe: `{}` and float size → `ERR_INVALID_PARAMETER`. |
| The cache directory `/var/tmp/velopack/<id>/packages` sits under a world-writable parent | `cache_dir_problem(dir)` walks every component with `lstat`. Each must be a real directory owned by this user or root; group/world-writable is allowed only for root-owned sticky parents; the packages dir itself must be ours and not group/world-writable. `verify_package` also requires the package to be a regular file (`symlink_status`). The download job refuses an existing unsafe directory before reading or deleting anything. Deletion happens only for a regular file in a safe directory. The real adapter's `locate` marks an existing unsafe directory unavailable. | New `bridge_cache_safety` (19 ok): own 0755 directory safe; relative, missing, foreign-owned (`/`), group-writable, world-writable, world-writable non-root parent and symlinked directory refused. A world-writable directory with valid bytes gives an error, with nothing deleted and no download. A symlinked cached package gives an error, with link and target untouched. A symlink swapped in after a verified download makes `prepare_apply` `FAILED`, with no apply and nothing deleted. |
| Minor | `public_base` accepts only `0.N.0` (N ≥ 1). `Installed.root` deleted (Task 6 compares roots through the smoke receipt). `last_request` is set only after validation succeeds. The Plan 03 JSON float → exact int `size` rule is documented. Staging wording now says "disposable staging copy of `game/`". The macOS/Windows `.gdextension` lines were dropped. | `bridge_target_mismatch`: `0.2.1` and `1.2.0` → invalid |

**Residual risk (recorded, not fixed):** the bridge verifies the package on the main thread and then launches Velopack's helper, which reads `PackagesDir/<file>` only **after Godot exits** (`--waitPid`). Within that window, anyone who can write the packages directory could swap the bytes.

- The ownership and mode checks mean only this user (or root) can, but the helper itself is not re-verified by Tortuga.
- The pinned helper's `apply_linux_impl.rs` loads the bundle without a SHA check.
- **Task 6 (owner: Task 6 / repository owner):** record the real owner, mode and parent chain of `/var/tmp/velopack/org.tortuga.game/packages` after an installed download, including when it was first created by another user. Decide whether Plan 03 needs a private `PackagesDir` through explicit locator plumbing.

| Command (review round 1) | Result |
|---|---|
| `cmake -S native -B $B` + `cmake --build $B` | exit 0 / exit 0, 0 `warning:` lines |
| `ctest --test-dir $B -C Release -V` (log `build/phase-2/feasibility/linux-x86_64/task3-ctest-verbose.log`) | exit 0, **16/16 tests** (10 launcher, 1 identity, 5 bridge). Bridge: **163 `ok`, 0 `FAIL`** (22 identity_and_locator, 28 serialized_events, 88 target_mismatch, 19 cache_safety, 6 sha256). |
| Mutation: `minimum_os` validation removed and unbounded regex restored → `test_bridge target_mismatch` | exit 1, 3 FAIL |
| Mutation: worker `try/catch` removed → `test_bridge target_mismatch` | exit 134 (`terminate called after throwing an instance of 'int'`). The real source was restored and rebuilt: `PASSED target_mismatch (0 failures)` |
| `cmake --install …/staging/native-runtime`, fresh `probe-project` copy, `--import`, `--script probe.gd` | install exit 0. import exit 0, 0 `ERROR`. probe exit 0, **20 ok / 0 FAIL**, 0 `ERROR`, PID 777886. Probe `TMPDIR` empty. |
| `bash game/tests/run_settings_checks.sh` | exit 0. Guard rejection OK. **Tests: 3037 checks, 0 failures.** Probes 7/13/2/8/1/14, all 0 failures. 7 deliberate `ERROR` lines, 0 GDExtension lines. |
| `bash game/tests/run_settings_checks.sh --self-test-failure` | exit 1 (expected) |
| `"$GODOT" --headless --path game --quit-after 30` | exit 0, 0 `ERROR` lines |

### Library facts (Linux x86_64)

| Item | Value |
|---|---|
| File | `libtortuga_updater.linux.template_release.x86_64.so`: ELF64 x86-64 shared object, already stripped (godot-cpp release flags) |
| Size / sha256 | **3,258,808 bytes**, `3f4b769b1663b2db9e1ca01f9b04f8a6ac817be4cf26dbc1142d4c5e72824587` (after review round 1; previously 3,250,560 bytes) |
| `ldd` / NEEDED | `libstdc++.so.6`, `libm.so.6`, `libgcc_s.so.1`, `libc.so.6`, `ld-linux-x86-64.so.2`. **No sidecars**: Velopack is linked statically from `velopack_libc_linux_x64_gnu.a`. |
| Highest symbol versions | `GLIBC_2.39` (Rust std `pidfd_spawnp`/`pidfd_getpid`, as with the launcher), `GLIBCXX_3.4.26`, `CXXABI_1.3.9`. The same portability limit as Task 2 applies: it cannot load on glibc < 2.39. Plan 02 must build in an older-glibc environment. |
| Exported dynamic symbols | `tortuga_updater_init` (+ libstdc++ `bad_variant_access` typeinfo) |

### Not proved / blocked

| Item | Status | Owner | Next action |
|---|---|---|---|
| Default locator inside an installed AppImage after the launcher → renamed Godot handoff (`$APPIMAGE`, `/usr/bin/` mount path, derived `PackagesDir`) | **pending (Task 6)**. The Linux reasoning is source-derived only. | Task 6 | Install the `vpk` AppImage fixture and run the probe through the launcher; `get_identity` must be available with the same root/packages dir as Velopack's log |
| Real HTTP check/download/apply, `WaitExitThenApplyUpdates` from the Godot PID | not executed (fake SDK only) | Tasks 4–6 | Loopback source plus fixture feeds |
| Destroying a busy bridge blocks the main thread until the SDK returns (≤ 10 min) | open by design. Task 4 adds the hardening and the `native_deadline` tests. | Task 4 / Plan 03 | Keep the reference until `worker_stopped` before `SceneTree.quit` |
| Cache removal is not under Velopack's `.velopack_lock` | open | Task 6 | Busy multi-launch case |
| Package bytes can be swapped between the bridge's verification and the helper's read after Godot exits (writers limited to this user/root by the owner/mode checks) | open risk | Task 6 / repository owner | Record the real `PackagesDir` owner, mode and parent chain on an installed AppImage; decide on a private `PackagesDir` for Plan 03 |
| macOS/Windows bridge (compile, locator, packages dir, `.gdextension` entries) | **blocked: compile-unproved** | repository owner | Build on native hosts and run the probe |
| Linux portability (glibc 2.39 floor, dynamic libstdc++) | open | Plan 02 / Task 6 | Older-glibc build environment |
