// Tortuga native launcher: Velopack startup handling, then hand off to the
// stock exported Godot binary installed next to this executable.
// Linux is built and tested; macOS/Windows paths are compile-unproved
// (docs/phase-2/01-native-updater-feasibility.md, Task 2).
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

#include "Velopack.hpp"

#if defined(_WIN32)
#include <windows.h>
#else
#include <unistd.h>
#endif
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif

namespace fs = std::filesystem;

namespace tortuga_launcher {

// Prototype sibling names; validated against real packages in Task 6.
#if defined(_WIN32)
constexpr const char* kLauncherName = "Tortuga.exe";
constexpr const char* kGameName = "Tortuga.godot.exe";
#elif defined(__APPLE__)
constexpr const char* kLauncherName = "Tortuga";  // Contents/MacOS/Tortuga (CFBundleExecutable)
constexpr const char* kGameName = "Tortuga.godot";
#else
constexpr const char* kLauncherName = "Tortuga";
constexpr const char* kGameName = "Tortuga.godot.x86_64";
#endif

fs::path resolve_game_executable(const fs::path& launcher_path) {
    return launcher_path.parent_path() / kGameName;
}

// argv[0] is replaced by the game path; everything else, including any user
// "--" boundary, passes through unchanged. The launcher never adds a boundary.
std::vector<std::string> forward_arguments(const std::vector<std::string>& argv) {
    return argv.empty() ? argv : std::vector<std::string>(argv.begin() + 1, argv.end());
}

// One argument quoted per the CommandLineToArgvW / MSVC CRT rules.
static void append_windows_arg(std::string& out, const std::string& arg) {
    if (!arg.empty() && arg.find_first_of(" \t\n\v\"") == std::string::npos) {
        out += arg;
        return;
    }
    out += '"';
    size_t slashes = 0;
    for (char ch : arg) {
        if (ch == '\\') { ++slashes; continue; }
        out.append(ch == '"' ? slashes * 2 + 1 : slashes, '\\');
        slashes = 0;
        out += ch;
    }
    out.append(slashes * 2, '\\');
    out += '"';
}

// UTF-8 command line for CreateProcessW; the program path is always quoted.
std::string windows_command_line(const std::string& program, const std::vector<std::string>& args) {
    std::string cmd = "\"" + program + "\"";
    for (const auto& a : args) {
        cmd += ' ';
        append_windows_arg(cmd, a);
    }
    return cmd;
}

#if defined(_WIN32)
static std::wstring widen(const std::string& s) {
    if (s.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
    std::wstring w(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), w.data(), n);
    return w;
}

// ponytail: lone UTF-16 surrogates in Windows args become U+FFFD here (not
// round-trippable); revisit only if a real argument needs them.
static std::string narrow(const std::wstring& w) {
    if (w.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
    std::string s(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), s.data(), n, nullptr, nullptr);
    return s;
}
#endif

// GUI-subsystem Windows launchers have no visible stderr, so also show a dialog.
static int report(const std::string& msg) {
    std::fprintf(stderr, "%s\n", msg.c_str());
#if defined(_WIN32)
    MessageBoxW(nullptr, widen(msg).c_str(), L"Tortuga", MB_OK | MB_ICONERROR);
#endif
    return 1;
}

static int fail(const fs::path& game, const std::string& why) {
    return report("Tortuga: cannot start the game at \"" + game.u8string() + "\": " + why +
                  ". Reinstall Tortuga to repair the installation.");
}

#if defined(_WIN32)

// Success means the Godot process was created, not that it later exits 0.
int handoff(const fs::path& game, const std::vector<std::string>& args) {
    std::wstring cmd = widen(windows_command_line(game.u8string(), args));
    STARTUPINFOW si{};
    si.cb = sizeof si;
    PROCESS_INFORMATION pi{};
    if (!CreateProcessW(game.c_str(), cmd.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi))
        return fail(game, "Windows error " + std::to_string(GetLastError()));
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return 0;
}

static fs::path self_executable() {
    std::wstring buf(MAX_PATH, L'\0');
    for (;;) {
        DWORD n = GetModuleFileNameW(nullptr, buf.data(), static_cast<DWORD>(buf.size()));
        if (n == 0) return {};
        if (n < buf.size()) return fs::path(buf.substr(0, n));
        buf.resize(buf.size() * 2);
    }
}
#else
// Exec-style replacement: Godot keeps this PID; no shell is involved.
int handoff(const fs::path& game, const std::vector<std::string>& args) {
    std::vector<char*> argv;
    argv.push_back(const_cast<char*>(game.c_str()));
    for (const auto& a : args) argv.push_back(const_cast<char*>(a.c_str()));
    argv.push_back(nullptr);
    execv(game.c_str(), argv.data());
    return fail(game, std::strerror(errno));
}

static fs::path self_executable() {
    std::error_code ec;
#if defined(__APPLE__)
    char buf[4096];
    uint32_t size = sizeof buf;
    if (_NSGetExecutablePath(buf, &size) != 0) return {};
    return fs::canonical(buf, ec);
#else
    return fs::read_symlink("/proc/self/exe", ec);
#endif
}
#endif

// Strict UTF-8 (Unicode 3.9 / Rust str rules): no overlongs, surrogates or > U+10FFFF.
static bool valid_utf8(const std::string& s) {
    for (size_t i = 0; i < s.size();) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        size_t n = c < 0x80 ? 1 : (c >= 0xC2 && c <= 0xDF) ? 2 : (c >= 0xE0 && c <= 0xEF) ? 3
                 : (c >= 0xF0 && c <= 0xF4) ? 4 : 0;
        if (n == 0 || i + n > s.size()) return false;
        if (n > 1) {  // second-byte range per lead byte
            unsigned char b = static_cast<unsigned char>(s[i + 1]);
            unsigned char lo = c == 0xE0 ? 0xA0 : c == 0xF0 ? 0x90 : 0x80;
            unsigned char hi = c == 0xED ? 0x9F : c == 0xF4 ? 0x8F : 0xBF;
            if (b < lo || b > hi) return false;
        }
        for (size_t k = 2; k < n; ++k)
            if ((static_cast<unsigned char>(s[i + k]) & 0xC0) != 0x80) return false;
        i += n;
    }
    return true;
}

// Pinned app.rs:130-138 lifecycle match: >= 2 args and ASCII-lowercased args[0] is a hook.
static bool is_lifecycle(const std::vector<std::string>& args) {
    if (args.size() < 2) return false;
    std::string a = args[0];
    for (char& ch : a) if (ch >= 'A' && ch <= 'Z') ch = static_cast<char>(ch - 'A' + 'a');
    return a == "--veloapp-install" || a == "--veloapp-updated" || a == "--veloapp-obsolete" ||
           a == "--veloapp-uninstall";
}

int run(const std::vector<std::string>& argv) {
    std::vector<std::string> args = forward_arguments(argv);
    // Velopack first; lifecycle hooks (--veloapp-* <version>) exit inside Run().
    // ponytail: pinned app.rs:40 reads env::args() even with SetArgs and aborts on
    // non-UTF-8 argv (argv[0] included, e.g. a non-UTF-8 install dir). Then skip
    // Run() (and with it installed-mode package cleanup and env stripping), but keep
    // its lifecycle exit so hooks never boot Godot. VELOPACK_DEBUG is not honored here.
    bool utf8 = true;
    for (const auto& a : argv) utf8 = utf8 && valid_utf8(a);
    if (utf8) Velopack::VelopackApp::Build().SetAutoApplyOnStartup(false).Run();
    else if (is_lifecycle(args)) return 0;

    fs::path self = self_executable();
    if (self.empty()) return report("Tortuga: cannot determine the launcher's installed location.");
    return handoff(resolve_game_executable(self), args);
}

}  // namespace tortuga_launcher

#ifndef TORTUGA_LAUNCHER_TEST
#if defined(_WIN32)
int wmain(int argc, wchar_t** wargv) {
    std::vector<std::string> argv;
    for (int i = 0; i < argc; ++i) argv.push_back(narrow(wargv[i]));
    return tortuga_launcher::run(argv);
}
#else
int main(int argc, char** argv) {
    return tortuga_launcher::run(std::vector<std::string>(argv, argv + argc));
}
#endif
#endif
