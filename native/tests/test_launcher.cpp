// launcher_paths_and_arguments CTest cases (POSIX). Usage:
//   test_launcher <case> <launcher> <fake_game> <netguard|-> <engine> <repo_root>
//   test_launcher identity
// Processes are started with fork+execve (argv arrays, never a shell).
#define TORTUGA_LAUNCHER_TEST
#include "../launcher/main.cpp"

#include "release_identity.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <map>
#include <regex>
#include <sstream>
#include <sys/wait.h>
#include <unistd.h>

using namespace tortuga_launcher;
using Args = std::vector<std::string>;

static int failures = 0;
#define CHECK(cond, what)                                                       \
    do {                                                                        \
        if (cond) std::cout << "ok   " << what << "\n";                         \
        else { std::cout << "FAIL " << what << "  (" #cond ")\n"; ++failures; } \
    } while (0)

static std::string show(const Args& v) {
    std::string s = "[";
    for (auto& a : v) s += "<" + a + ">";
    return s + "]";
}

static std::string slurp(const fs::path& p) {
    std::ifstream f(p, std::ios::binary);
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

static Args split_nul(const std::string& s) {
    Args out;
    size_t start = 0;
    for (size_t i = 0; i < s.size(); ++i)
        if (s[i] == '\0') { out.push_back(s.substr(start, i - start)); start = i + 1; }
    return out;
}

struct Run { int status; pid_t pid; std::string out, err; };

// fork + execve; child closes inherited fds > 2 so leak checks see only the launcher's.
static Run run(const Args& argv, const fs::path& cwd, const std::map<std::string, std::string>& extra_env,
               const fs::path& scratch) {
    fs::path out = scratch / "stdout.txt", err = scratch / "stderr.txt";
    std::vector<std::string> env;
    for (char** e = environ; *e; ++e) {
        std::string kv = *e;
        if (!extra_env.count(kv.substr(0, kv.find('=')))) env.push_back(kv);
    }
    for (auto& [k, v] : extra_env) env.push_back(k + "=" + v);
    std::vector<char*> cargv, cenv;
    for (auto& a : argv) cargv.push_back(const_cast<char*>(a.c_str()));
    cargv.push_back(nullptr);
    for (auto& e : env) cenv.push_back(const_cast<char*>(e.c_str()));
    cenv.push_back(nullptr);
    pid_t pid = fork();
    if (pid == 0) {
        int o = open(out.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
        int e = open(err.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (o < 0 || e < 0 || dup2(o, 1) < 0 || dup2(e, 2) < 0 || chdir(cwd.c_str()) != 0) _exit(120);
        for (int fd = 3; fd < 1024; ++fd) close(fd);
        execve(cargv[0], cargv.data(), cenv.data());
        _exit(121);
    }
    int st = 0;
    waitpid(pid, &st, 0);
    return {WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st), pid, slurp(out), slurp(err)};
}

struct Game { bool ran; pid_t pid; std::string exe, cwd, fds; Args args; };

static Game read_game(const fs::path& marker) {
    if (!fs::exists(marker)) return {false, 0, "", "", "", {}};
    std::string s = slurp(marker);
    std::istringstream in(s);
    Game g{true, 0, "", "", "", {}};
    std::string pid;
    std::getline(in, pid);
    std::getline(in, g.exe);
    std::getline(in, g.cwd);
    std::getline(in, g.fds);
    g.pid = std::stoi(pid);
    g.args = split_nul(s.substr(static_cast<size_t>(in.tellg())));
    return g;
}

struct Ctx {
    fs::path launcher, fake_game, netguard, engine, repo, root;
    fs::path install(const std::string& name, bool with_game, fs::perms game_perms = fs::perms::owner_all) {
        fs::path dir = root / name;
        fs::create_directories(dir);
        fs::copy_file(launcher, dir / kLauncherName);
        if (with_game) {
            fs::copy_file(fake_game, dir / kGameName);
            fs::permissions(dir / kGameName, game_perms);
        }
        return dir;
    }
    fs::path dir(const std::string& name) { fs::create_directories(root / name); return root / name; }
    std::map<std::string, std::string> env(const fs::path& marker) {
        std::map<std::string, std::string> e{{"TORTUGA_FAKE_GAME_OUT", marker.string()},
                                             {"TORTUGA_NETGUARD_OUT", (root / "net.log").string()},
                                             {"TMPDIR", dir("tmp").string()}};
        if (!netguard.empty()) e["LD_PRELOAD"] = netguard.string();
        return e;
    }
    bool no_network() { return !fs::exists(root / "net.log"); }
};

// Launch the installed launcher from an unrelated CWD and expect exact forwarding.
static void expect_handoff(Ctx& c, const fs::path& inst, const Args& args, const std::string& label,
                           const fs::path& invoke_as = {}) {
    fs::path cwd = c.dir("unrelated cwd");
    static int seq = 0;
    fs::path marker = c.root / ("marker-" + std::to_string(++seq));
    Args argv{(invoke_as.empty() ? inst / kLauncherName : invoke_as).string()};
    argv.insert(argv.end(), args.begin(), args.end());
    Run r = run(argv, cwd, c.env(marker), c.root);
    Game g = read_game(marker);
    CHECK(r.status == 0, label + ": launcher exit 0 (got " + std::to_string(r.status) + ", stderr: " + r.err + ")");
    CHECK(g.ran, label + ": game process ran");
    CHECK(g.exe == fs::canonical(inst / kGameName).string(), label + ": installation-relative game " + g.exe);
    CHECK(g.cwd == fs::canonical(cwd).string(), label + ": game cwd preserved " + g.cwd);
    CHECK(g.args == args, label + ": args exact " + show(g.args) + " == " + show(args));
    CHECK(g.pid == r.pid, label + ": exec replacement (game pid " + std::to_string(g.pid) + " == launcher pid " +
                              std::to_string(r.pid) + ")");
    CHECK(g.fds.empty(), label + ": no leaked descriptors [" + g.fds + "]");
}

static void expect_no_launch(Ctx& c, const fs::path& inst, const Args& args, const std::string& label,
                             bool want_zero) {
    static int seq = 0;
    fs::path marker = c.root / ("marker-none-" + std::to_string(++seq));
    Args argv{(inst / kLauncherName).string()};
    argv.insert(argv.end(), args.begin(), args.end());
    Run r = run(argv, c.dir("unrelated cwd"), c.env(marker), c.root);
    CHECK(!fs::exists(marker), label + ": game NOT launched");
    if (want_zero) CHECK(r.status == 0, label + ": exit 0 (got " + std::to_string(r.status) + ")");
    else {
        CHECK(r.status != 0, label + ": nonzero exit (got " + std::to_string(r.status) + ")");
        CHECK(r.err.find((inst / kGameName).string()) != std::string::npos && r.err.find("Reinstall") != std::string::npos,
              label + ": actionable diagnostic names the game path: " + r.err);
    }
}

// Inverse of CommandLineToArgvW for arguments after the program name.
static Args parse_windows_tail(const std::string& s) {
    Args out;
    std::string cur;
    bool in_quotes = false, started = false;
    for (size_t i = 0; i < s.size();) {
        char ch = s[i];
        if (ch == '\\') {
            size_t n = 0;
            while (i < s.size() && s[i] == '\\') { ++n; ++i; }
            if (i < s.size() && s[i] == '"') {
                cur.append(n / 2, '\\');
                if (n % 2) { cur += '"'; ++i; }
            } else cur.append(n, '\\');
            started = true;
        } else if (ch == '"') { in_quotes = !in_quotes; started = true; ++i; }
        else if ((ch == ' ' || ch == '\t') && !in_quotes) {
            if (started) { out.push_back(cur); cur.clear(); started = false; }
            ++i;
        } else { cur += ch; started = true; ++i; }
    }
    if (started) out.push_back(cur);
    return out;
}

static int run_case(const std::string& name, Ctx& c) {
    if (name == "helpers") {
        fs::path l = "/opt/Tört ⚓/" + std::string(kLauncherName);
        CHECK(resolve_game_executable(l) == fs::path("/opt/Tört ⚓") / kGameName, "resolve: sibling of launcher");
        Args in{"/x/Tortuga", "--headless", "--", "a b", "", "--"};
        CHECK(forward_arguments(in) == Args(in.begin() + 1, in.end()), "forward: drops argv[0] only, no boundary added");
        CHECK(forward_arguments({"/x/Tortuga"}).empty(), "forward: no args -> none");
    } else if (name == "windows_quoting") {
        std::string prog = "C:\\Users\\Ünï Cødé\\Tortuga.godot.exe";
        Args cases{"a b", "", "\"q\"", "--x", "a\\b", "a\\\\b c", "x y\\", "a\\\"b", "\\\\\"", "tab\there", "--", "⚓"};
        std::string cmd = windows_command_line(prog, cases);
        CHECK(cmd.rfind("\"" + prog + "\" ", 0) == 0, "windows: program path quoted first: " + cmd);
        Args back = parse_windows_tail(cmd.size() > prog.size() + 3 ? cmd.substr(prog.size() + 3) : "");
        CHECK(back == cases, "windows: CommandLineToArgvW round trip " + show(back));
        CHECK(windows_command_line(prog, {}) == "\"" + prog + "\"", "windows: no args");
    } else if (name == "unrelated_cwd") {
        fs::path inst = c.install("install", true);
        // A decoy game in the CWD must never be chosen.
        fs::path cwd = c.dir("unrelated cwd");
        fs::copy_file(c.fake_game, cwd / kGameName);
        expect_handoff(c, inst, {"--headless"}, "absolute path");
        fs::create_symlink(inst / kLauncherName, c.dir("links") / "tortuga-link");
        expect_handoff(c, inst, {"--headless"}, "via symlink", c.root / "links" / "tortuga-link");
        CHECK(c.no_network(), "no socket/connect/getaddrinfo during normal handoff");
    } else if (name == "unicode_path") {
        fs::path inst = c.install("Tört ugä ⚓ 船 dir", true);
        expect_handoff(c, inst, {"--path", "Ünï cødé ⚓"}, "unicode+spaces install");
    } else if (name == "quotes_and_empty_args") {
        fs::path inst = c.install("install", true);
        expect_handoff(c, inst, {"a b", "", "\"q\"", "--x", "'s'", "$HOME", "*", "`id`", "; echo pwned", "\\"},
                       "literal quotes/empty/shell metachars");
        CHECK(!fs::exists(c.root / "unrelated cwd" / "pwned"), "no shell evaluation");
        // Pinned Velopack app.rs:40 calls env::args(), which panics (abort) on non-UTF-8 argv.
        expect_handoff(c, inst, {"\xff\xfe", "ok"}, "non-UTF-8 argument forwarded byte-exact");
        // Ill-formed per Rust's strict UTF-8: overlong, surrogate, above U+10FFFF (x2).
        for (const char* bad : {"\xc0\x80", "\xed\xa0\x80", "\xf4\x90\x80\x80", "\xf5\x80\x80\x80"})
            expect_handoff(c, inst, {bad, "ok"}, "strict-UTF-8 reject forwarded byte-exact");
        expect_handoff(c, inst, {"\xed\x9f\xbf\xf4\x8f\xbf\xbf"}, "valid U+D7FF U+10FFFF forwarded");
    } else if (name == "user_boundary") {
        fs::path inst = c.install("install", true);
        expect_handoff(c, inst, {"--headless", "--", "u1", "--", "u2"}, "preexisting user boundary kept once");
        expect_handoff(c, inst, {"--headless", "x"}, "no boundary added when absent");
    } else if (name == "missing_game") {
        expect_no_launch(c, c.install("install", false), {"--headless"}, "missing game", false);
    } else if (name == "nonexecutable_game") {
        expect_no_launch(c, c.install("install", true, fs::perms::owner_read | fs::perms::owner_write),
                         {"--headless"}, "non-executable game", false);
    } else if (name == "lifecycle_only") {
        fs::path inst = c.install("install", true);
        for (const char* hook : {"--veloapp-install", "--veloapp-updated", "--veloapp-obsolete",
                                 "--veloapp-uninstall", "--VELOAPP-INSTALL"})
            expect_no_launch(c, inst, {hook, "0.1.0"}, hook, true);
        CHECK(c.no_network(), "lifecycle handling made no socket/connect/getaddrinfo call");
        // Pinned app.rs requires a second argument; a bare hook flag is an ordinary launch.
        expect_handoff(c, inst, {"--veloapp-install"}, "bare hook flag forwarded");
        // Non-UTF-8 install dir makes argv[0] non-UTF-8, so Velopack Run() is skipped;
        // the launcher must still treat hook invocations as lifecycle-only.
        fs::path bad = c.install("inst \xff dir", true);
        for (const char* hook : {"--veloapp-install", "--veloapp-updated", "--veloapp-obsolete",
                                 "--veloapp-uninstall", "--VeloApp-Install"})
            expect_no_launch(c, bad, {hook, "0.1.0"}, std::string("non-UTF-8 dir ") + hook, true);
        expect_no_launch(c, bad, {"--veloapp-install", "\xff"}, "non-UTF-8 dir hook with non-UTF-8 version", true);
        expect_handoff(c, bad, {"--veloapp-install"}, "non-UTF-8 dir bare hook flag forwarded");
        expect_handoff(c, bad, {"--headless", "x"}, "non-UTF-8 dir ordinary launch");
        if (!c.netguard.empty()) {  // positive control: the shim does observe network calls
            fs::path m = c.root / "control-marker";
            auto e = c.env(m);
            e["TORTUGA_FAKE_GAME_NET"] = "1";
            run({c.fake_game.string()}, c.root, e, c.root);
            CHECK(!c.no_network(), "netguard control: shim records a real getaddrinfo");
        }
    } else if (name == "real_godot") {
        fs::path inst = c.dir("Tört ugä ⚓ real");
        fs::copy_file(c.launcher, inst / kLauncherName);
        fs::copy_file(c.engine, inst / kGameName);
        fs::path cwd = c.dir("unrelated cwd"), xdg = c.dir("xdg");
        std::map<std::string, std::string> env{{"XDG_DATA_HOME", xdg.string()}, {"XDG_CONFIG_HOME", xdg.string()},
                                               {"XDG_CACHE_HOME", xdg.string()}, {"TMPDIR", c.dir("tmp").string()},
                                               {"TORTUGA_CAPTURE_OUT", (c.root / "capture").string()}};
        Run v = run({(inst / kLauncherName).string(), "--headless", "--version"}, cwd, env, c.root);
        CHECK(v.status == 0 && v.out.rfind("4.7.2.stable.", 0) == 0, "real godot --version via launcher: " + v.out);
        fs::path script = c.repo / "native" / "tests" / "capture_args.gd";
        Args fwd{"--headless", "--path", (c.repo / "game").string(), "--script", script.string(), "--quit-after", "5",
                 "--", "a b", "", "\"q\"", "--x"};
        Args argv{(inst / kLauncherName).string()};
        argv.insert(argv.end(), fwd.begin(), fwd.end());
        Run r = run(argv, cwd, env, c.root);
        CHECK(r.status == 0, "real godot run exit 0 (got " + std::to_string(r.status) + ")");
        std::string cap = slurp(c.root / "capture");
        std::istringstream in(cap);
        std::string pid = "0", exe;
        std::getline(in, pid);
        std::getline(in, exe);
        Args cmdline = in ? split_nul(cap.substr(static_cast<size_t>(in.tellg()))) : Args{};
        Args user = split_nul(slurp(c.root / "capture.user"));
        CHECK(!pid.empty() && std::atoi(pid.c_str()) == r.pid, "Godot OS.get_process_id " + pid + " == launcher pid " +
                                                           std::to_string(r.pid) + " (exec replacement)");
        CHECK(exe == fs::canonical(inst / kGameName).string(), "Godot executable is installed sibling: " + exe);
        CHECK(cmdline.size() == fwd.size() + 1 && Args(cmdline.begin() + 1, cmdline.end()) == fwd,
              "Godot /proc/self/cmdline after argv[0] == forwarded " + show(cmdline));
        CHECK(std::count(cmdline.begin(), cmdline.end(), "--") == 1, "exactly one -- boundary");
        CHECK(user == Args({"a b", "", "\"q\"", "--x"}), "OS.get_cmdline_user_args " + show(user));
    } else {
        std::cout << "unknown case " << name << "\n";
        return 2;
    }
    return failures ? 1 : 0;
}

int main(int argc, char** argv) {
    if (argc == 2 && std::string(argv[1]) == "identity") {
        std::string v = TORTUGA_PACKAGE_VERSION;
        CHECK(std::string(TORTUGA_APP_ID) == "org.tortuga.game", "identity: app id");
        if (TORTUGA_IS_RELEASE)
            CHECK(std::regex_match(v, std::regex("0\\.[1-9][0-9]*\\.0")), "release identity version " + v);
        else
            CHECK(v == "0.0.0-dev" && std::string(TORTUGA_CHANNEL) == "dev", "development identity " + v);
        return failures ? 1 : 0;
    }
    if (argc != 7) {
        std::cerr << "usage: test_launcher <case> <launcher> <fake_game> <netguard|-> <engine> <repo_root>\n";
        return 2;
    }
    Ctx c{argv[2], argv[3], std::string(argv[4]) == "-" ? "" : argv[4], argv[5], argv[6], {}};
    c.root = fs::temp_directory_path() / ("tortuga launcher ✓ " + std::string(argv[1]) + " " + std::to_string(getpid()));
    fs::create_directories(c.root);
    int rc = run_case(argv[1], c);
    if (rc == 0) fs::remove_all(c.root);
    else std::cout << "kept for inspection: " << c.root << "\n";
    return rc;
}
