// Tortuga updater bridge core. See updater_bridge.h.
#include "updater_bridge.h"

#include <array>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <regex>
#include <stdexcept>

#include "Velopack.hpp"

#if defined(__linux__)
#include <gnu/libc-version.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>
#elif defined(_WIN32)
#include <windows.h>
#endif

namespace fs = std::filesystem;

namespace tortuga_updater {

// ---------------------------------------------------------------- SHA-256 (FIPS 180-4)
namespace {
constexpr uint32_t K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

inline uint32_t rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }

struct Sha256 {
    uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    unsigned char buf[64];
    size_t used = 0;
    uint64_t total = 0;

    void block(const unsigned char* p) {
        uint32_t w[64];
        for (int i = 0; i < 16; ++i)
            w[i] = uint32_t(p[4 * i]) << 24 | uint32_t(p[4 * i + 1]) << 16 | uint32_t(p[4 * i + 2]) << 8 | p[4 * i + 3];
        for (int i = 16; i < 64; ++i) {
            uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
        for (int i = 0; i < 64; ++i) {
            uint32_t t1 = hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
            uint32_t t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
            hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
        }
        h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
    }
    void update(const unsigned char* p, size_t n) {
        total += n;
        while (n > 0) {
            size_t take = std::min(n, size_t(64) - used);
            std::memcpy(buf + used, p, take);
            used += take; p += take; n -= take;
            if (used == 64) { block(buf); used = 0; }
        }
    }
    std::string hex() {
        uint64_t bits = total * 8;
        unsigned char pad = 0x80, zero = 0;
        update(&pad, 1);
        while (used != 56) update(&zero, 1);
        unsigned char len[8];
        for (int i = 0; i < 8; ++i) len[i] = static_cast<unsigned char>(bits >> (56 - 8 * i));
        update(len, 8);
        char out[65];
        for (int i = 0; i < 8; ++i) std::snprintf(out + 8 * i, 9, "%08x", h[i]);
        return std::string(out, 64);
    }
};
}  // namespace

std::string sha256_hex(const std::string& bytes) {
    Sha256 s;
    s.update(reinterpret_cast<const unsigned char*>(bytes.data()), bytes.size());
    return s.hex();
}

std::string sha256_file_hex(const std::string& path) {
    std::ifstream f(fs::u8path(path), std::ios::binary);
    if (!f) return "";
    Sha256 s;
    std::array<char, 1 << 16> chunk;
    while (f) {
        f.read(chunk.data(), chunk.size());
        s.update(reinterpret_cast<const unsigned char*>(chunk.data()), static_cast<size_t>(f.gcount()));
    }
    return f.bad() ? "" : s.hex();
}

// ---------------------------------------------------------------- validation helpers
namespace {

bool parse_version(const std::string& v, std::array<long, 3>& out) {
    std::smatch m;
    static const std::regex re("^(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})$");
    if (!std::regex_match(v, m, re)) return false;
    for (int i = 0; i < 3; ++i) out[i] = std::stol(m[i + 1]);
    return true;
}

bool version_gt(const std::string& a, const std::string& b) {
    std::array<long, 3> x{}, y{};
    return parse_version(a, x) && parse_version(b, y) && x > y;
}

std::string lower(std::string s) {
    for (char& c : s) if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    return s;
}

// Release line mapping (spec §5): machine 0.N.0 (N >= 1) -> tag v0.N -> immutable base.
// ponytail: public base only; Task 4 adds the validated loopback test source.
std::string public_base(const std::string& version) {
    std::array<long, 3> v{};
    if (!parse_version(version, v) || v[0] != 0 || v[1] < 1 || v[2] != 0) return "";
    return "https://github.com/dnldxn/tortuga/releases/download/v0." + std::to_string(v[1]) + "/";
}

bool same_target(const Target& a, const Target& b) {
    return a.app_id == b.app_id && a.channel == b.channel && a.platform == b.platform && a.version == b.version &&
           a.base_url == b.base_url && a.full_filename == b.full_filename && a.sha256 == b.sha256 &&
           a.size == b.size && a.minimum_os == b.minimum_os;
}

bool asset_matches(const Asset& a, const Target& t) {
    return a.package_id == t.app_id && lower(a.type) == "full" && a.version == t.version &&
           a.filename == t.full_filename && lower(a.sha256) == t.sha256 && a.size == static_cast<uint64_t>(t.size);
}

// Minimum-OS comparison against locally observed inputs. Empty = no requirement.
// ponytail: only "glibc X.Y" (Linux) is understood; other forms fail closed
// until Plan 02 fixes the manifest's minimum-OS grammar.
// Digits are bounded so std::stoi can never overflow.
const std::regex kMinimumOs("^glibc ([0-9]{1,4})\\.([0-9]{1,4})$");

bool os_compatible(const std::string& req, const std::vector<std::pair<std::string, std::string>>& os) {
    std::smatch m;
    if (req.empty()) return true;
    if (!std::regex_match(req, m, kMinimumOs)) return false;
    for (auto& [k, v] : os) {
        std::smatch h;
        static const std::regex have("^([0-9]{1,4})\\.([0-9]{1,4})(?![0-9])");
        if (k == "glibc" && std::regex_search(v, h, have))
            return std::make_pair(std::stoi(h[1]), std::stoi(h[2])) >= std::make_pair(std::stoi(m[1]), std::stoi(m[2]));
    }
    return false;
}

Event make(int64_t id, const char* kind, Fields payload = {}) { return Event{id, kind, std::move(payload)}; }
Event error(int64_t id, const std::string& msg) { return make(id, "error", {{"message", msg}}); }

}  // namespace

std::string cache_dir_problem(const std::string& dir) {
#if defined(_WIN32)
    (void)dir;
    return "";  // compile-unproved: Windows ACL checks come with the Windows gate
#else
    // The Linux default is /var/tmp/velopack/<id>/packages, under a world-writable
    // root. Every component must be a real directory owned by us or root; the
    // packages dir itself must be ours. Group/other-writable is allowed only
    // for root-owned sticky dirs (/var/tmp, /tmp).
    fs::path p = fs::u8path(dir);
    if (!p.is_absolute()) return "package cache path is not absolute: " + dir;
    bool leaf = true;
    for (; ; p = p.parent_path()) {
        struct stat st {};
        if (lstat(p.c_str(), &st) != 0) return "package cache path missing: " + p.u8string();
        if (!S_ISDIR(st.st_mode)) return "package cache path component is not a directory: " + p.u8string();
        bool ours = st.st_uid == geteuid(), root = st.st_uid == 0;
        bool shared = (st.st_mode & (S_IWGRP | S_IWOTH)) != 0;
        if (leaf ? !ours : !(ours || root)) return "package cache path not owned by this user: " + p.u8string();
        if (shared && (leaf || !root || !(st.st_mode & S_ISVTX)))
            return "package cache path is group/world-writable: " + p.u8string();
        leaf = false;
        if (p == p.parent_path()) return "";
    }
#endif
}

std::string validate_target(const Target& t, const Identity& id) {
    static const std::regex safe_name("^[A-Za-z0-9][A-Za-z0-9._-]{0,200}\\.nupkg$");
    static const std::regex hex64("^[0-9a-f]{64}$");
    std::array<long, 3> v{};
    if (t.app_id != id.app_id) return "target app_id '" + t.app_id + "' != installed build '" + id.app_id + "'";
    if (t.channel != id.channel) return "target channel '" + t.channel + "' != build channel '" + id.channel + "'";
    if (t.platform != id.platform) return "target platform '" + t.platform + "' != build platform '" + id.platform + "'";
    if (!parse_version(t.version, v)) return "target version is not normalized N.N.N: '" + t.version + "'";
    if (t.base_url != public_base(t.version)) return "target base_url is not the exact release base for " + t.version;
    if (!std::regex_match(t.full_filename, safe_name)) return "unsafe full package filename: '" + t.full_filename + "'";
    if (!std::regex_match(t.sha256, hex64)) return "target sha256 must be 64 lowercase hex characters";
    if (t.size <= 0) return "target size must be positive";
    if (!t.minimum_os.empty() && !std::regex_match(t.minimum_os, kMinimumOs))
        return "target minimum_os must be empty or 'glibc X.Y': '" + t.minimum_os + "'";
    return "";
}

std::vector<std::pair<std::string, std::string>> observe_os() {
    std::vector<std::pair<std::string, std::string>> os;
#if defined(__linux__) || defined(__APPLE__)
    struct utsname u {};
    if (uname(&u) == 0) os = {{"system", u.sysname}, {"machine", u.machine}, {"release", u.release}};
#endif
#if defined(__linux__)
    os.emplace_back("glibc", gnu_get_libc_version());
#elif defined(_WIN32)
    os = {{"system", "Windows"}};  // compile-unproved; version inputs come with the Windows gate
#endif
    return os;
}

static std::string platform_key_of(const std::vector<std::pair<std::string, std::string>>& os) {
    std::string sys, mach;
    for (auto& [k, v] : os) {
        if (k == "system") sys = v;
        if (k == "machine") mach = v;
    }
    if (sys == "Linux" && mach == "x86_64") return "linux-x86_64";
    if (sys == "Darwin" && (mach == "arm64" || mach == "x86_64")) return "macos-universal";
    if (sys == "Windows") return "windows-x86_64";
    return sys + "-" + mach;
}

// ---------------------------------------------------------------- bridge
struct Bridge::State {
    std::mutex m;
    std::deque<Event> events;
    bool busy = false, shutdown = false, stop_emitted = false, applied = false;
    int64_t last_request = 0;
    int64_t checked_request = -1, downloaded_request = -1;  // completed, verified steps
    Target frozen;
    std::string package_path;
    int last_progress = -1;

    void push(Event e) {
        std::lock_guard<std::mutex> g(m);
        events.push_back(std::move(e));
    }
};

Bridge::Bridge(Identity compiled, std::shared_ptr<Sdk> sdk, std::vector<std::pair<std::string, std::string>> os)
    : compiled_(std::move(compiled)), sdk_(std::move(sdk)), os_(std::move(os)), state_(std::make_shared<State>()) {}

Bridge::~Bridge() {
    {
        std::lock_guard<std::mutex> g(state_->m);
        state_->shutdown = true;
    }
    // ponytail: blocks until the SDK call returns (bounded by its whole-request
    // deadline); Task 4 tests this barrier. Never detach: code must stay loaded.
    if (worker_.joinable()) worker_.join();
}

IdentityReport Bridge::identity() {
    IdentityReport r;
    r.identity = compiled_;
    r.os = os_;
    r.platform_key = platform_key_of(os_);
    try {
        r.installed = sdk_->locate();
    } catch (const std::exception& e) {
        r.installed = Installed{false, std::string("locator failed: ") + e.what()};
    }
    const Installed& in = r.installed;
    if (!compiled_.is_release) r.reason = "development build: never update eligible";
    else if (r.platform_key != compiled_.platform)
        r.reason = "running platform '" + r.platform_key + "' != build platform '" + compiled_.platform + "'";
    else if (!in.ok) r.reason = "not an installed package: " + in.reason;
    else if (in.app_id != compiled_.app_id)
        r.reason = "installed app id '" + in.app_id + "' != build '" + compiled_.app_id + "'";
    else if (in.version != compiled_.package_version)
        r.reason = "installed version '" + in.version + "' != build '" + compiled_.package_version + "'";
    else if (in.channel != compiled_.channel)
        r.reason = "installed channel '" + in.channel + "' != build '" + compiled_.channel + "'";
    else if (in.packages_dir.empty()) r.reason = "package cache directory unknown";
    r.available = r.reason.empty();
    return r;
}

// Reserves the single operation (busy) before locating, so no second
// UpdateManager is built while a worker is inside the SDK. On success the
// caller owns busy and must release() or start() a job.
Err Bridge::admit(IdentityReport& report) {
    {
        std::lock_guard<std::mutex> g(state_->m);
        if (state_->shutdown || state_->applied) return Err::unavailable;
        if (state_->busy) return Err::busy;
        state_->busy = true;
    }
    report = identity();
    return report.available ? Err::ok : release(Err::unavailable);
}

void Bridge::start(int64_t request_id, std::function<void()> job) {
    if (worker_.joinable()) worker_.join();  // previous job finished (busy was false)
    auto st = state_;
    worker_ = std::thread([st, request_id, job = std::move(job)] {
        try {
            job();
        } catch (const std::exception& e) {
            st->push(error(request_id, std::string("internal error: ") + e.what()));
        } catch (...) {
            st->push(error(request_id, "internal error"));
        }
        std::lock_guard<std::mutex> g(st->m);
        st->busy = false;
    });
}

Err Bridge::release(Err e) {
    std::lock_guard<std::mutex> g(state_->m);
    state_->busy = false;
    return e;
}

Err Bridge::begin_check(const Target& target, int64_t request_id) {
    if (!validate_target(target, compiled_).empty()) return Err::invalid;
    const bool compatible = os_compatible(target.minimum_os, os_);  // before reserving busy
    IdentityReport rep;
    if (Err e = admit(rep); e != Err::ok) return e;
    {
        std::lock_guard<std::mutex> g(state_->m);
        state_->last_request = request_id;
        state_->last_progress = -1;
        state_->checked_request = state_->downloaded_request = -1;
        state_->frozen = target;  // copy: caller mutation cannot reach the worker
    }
    auto st = state_;
    auto sdk = sdk_;
    const Target t = target;
    const std::string current = rep.installed.version;
    start(request_id, [st, sdk, t, request_id, current, compatible] {
        auto checked = [&](bool update_available) {
            return make(request_id, "checked", {{"compatible", compatible}, {"requirement", t.minimum_os},
                                                {"update_available", update_available}, {"target", t}});
        };
        // No feed request for an incompatible or not-newer target.
        if (!compatible || !version_gt(t.version, current)) return st->push(checked(false));
        try {
            std::optional<Asset> a = sdk->check(t, kCheckTimeoutMs);
            if (!a) return st->push(error(request_id, "feed missing expected release " + t.version));
            if (!asset_matches(*a, t))
                return st->push(error(request_id, "feed release " + a->version + " (" + a->filename +
                                                      ") does not match the manifest target"));
            std::lock_guard<std::mutex> g(st->m);
            st->checked_request = request_id;
            st->events.push_back(checked(true));
        } catch (const std::exception& e) {
            st->push(error(request_id, std::string("check failed: ") + e.what()));
        }
    });
    return Err::ok;
}

namespace {
// "" when the file at path has exactly the target's size and SHA-256.
std::string verify_package(const std::string& path, const Target& t) {
    if (std::string bad = cache_dir_problem(fs::u8path(path).parent_path().u8string()); !bad.empty()) return bad;
    std::error_code ec;
    auto status = fs::symlink_status(fs::u8path(path), ec);
    if (ec || status.type() == fs::file_type::not_found) return "package missing: " + path;
    if (status.type() != fs::file_type::regular) return "package is not a regular file (symlink?): " + path;
    auto size = fs::file_size(fs::u8path(path), ec);
    if (ec) return "package missing: " + path;
    if (static_cast<int64_t>(size) != t.size)
        return "package size " + std::to_string(size) + " != expected " + std::to_string(t.size);
    std::string got = sha256_file_hex(path);
    if (got != t.sha256) return "package SHA-256 " + (got.empty() ? std::string("unreadable") : got) + " != expected";
    return "";
}
}  // namespace

Err Bridge::begin_download(const Target& target, int64_t request_id) {
    IdentityReport rep;
    if (Err e = admit(rep); e != Err::ok) return e;
    Target t;
    std::string path;
    {
        std::lock_guard<std::mutex> g(state_->m);
        if (state_->checked_request != request_id || !same_target(state_->frozen, target)) {
            state_->busy = false;
            return Err::invalid;
        }
        state_->last_request = request_id;
        state_->last_progress = -1;
        t = state_->frozen;
        state_->downloaded_request = -1;
        path = state_->package_path = (fs::u8path(rep.installed.packages_dir) / t.full_filename).u8string();
    }
    auto st = state_;
    auto sdk = sdk_;
    start(request_id, [st, sdk, t, request_id, path] {
        auto done = [&](bool cached) {
            std::lock_guard<std::mutex> g(st->m);
            st->downloaded_request = request_id;
            st->events.push_back(make(request_id, "downloaded", {{"cached", cached}, {"path", path}, {"target", t}}));
        };
        // Refuse an unsafe existing cache dir before reading or deleting anything in it.
        std::error_code ec;
        std::string dir = fs::u8path(path).parent_path().u8string();
        if (fs::exists(fs::u8path(dir), ec)) {
            if (std::string bad = cache_dir_problem(dir); !bad.empty()) return st->push(error(request_id, bad));
        }
        // Pinned Velopack skips its own checksum when the final file already exists
        // (manager.rs:414), so a cached package is verified here before reuse.
        auto cached = fs::symlink_status(fs::u8path(path), ec).type();
        if (cached == fs::file_type::symlink || (cached != fs::file_type::not_found && cached != fs::file_type::regular))
            return st->push(error(request_id, "cached package is not a regular file (symlink?): " + path));
        if (cached == fs::file_type::regular) {
            std::string bad = verify_package(path, t);
            if (bad.empty()) return done(true);
            fs::remove(fs::u8path(path), ec);  // only the selected file, while this op owns the bridge
            return st->push(error(request_id, "cached " + bad + "; removed it, retry downloads fresh bytes"));
        }
        try {
            sdk->download(t, kDownloadTimeoutMs, [st, request_id](int pct) {
                std::lock_guard<std::mutex> g(st->m);  // enqueue only
                if (pct == st->last_progress) return;
                st->last_progress = pct;
                st->events.push_back(make(request_id, "progress", {{"percent", int64_t(pct)}}));
            });
        } catch (const std::exception& e) {
            return st->push(error(request_id, std::string("download failed: ") + e.what()));
        }
        std::string bad = verify_package(path, t);
        if (bad.empty()) return done(false);
        if (fs::symlink_status(fs::u8path(path), ec).type() == fs::file_type::regular && cache_dir_problem(dir).empty())
            fs::remove(fs::u8path(path), ec);
        st->push(error(request_id, "downloaded " + bad));
    });
    return Err::ok;
}

Err Bridge::prepare_apply(int64_t request_id, const std::vector<std::string>& restart_args) {
    IdentityReport rep;
    if (Err e = admit(rep); e != Err::ok) return e;  // owns busy while verifying/launching the helper
    Target t;
    std::string path;
    {
        std::lock_guard<std::mutex> g(state_->m);
        if (state_->downloaded_request != request_id) {
            state_->busy = false;
            return Err::invalid;
        }
        t = state_->frozen;
        path = state_->package_path;
    }
    // ponytail: re-hash on the calling (main) thread just before the helper starts;
    // ~0.1-0.3 s for a 50 MB package, once, right before quit.
    std::string bad = verify_package(path, t);
    Err result = Err::ok;
    if (!bad.empty()) {
        std::error_code ec;
        std::string dir = fs::u8path(path).parent_path().u8string();
        if (fs::symlink_status(fs::u8path(path), ec).type() == fs::file_type::regular && cache_dir_problem(dir).empty())
            fs::remove(fs::u8path(path), ec);
        state_->push(error(request_id, "apply refused: " + bad));
        result = Err::failed;
    } else {
        try {
            sdk_->apply(t, kApplySilent, restart_args);
        } catch (const std::exception& e) {
            state_->push(error(request_id, std::string("apply preparation failed: ") + e.what()));
            result = Err::failed;
        }
    }
    std::lock_guard<std::mutex> g(state_->m);
    state_->busy = false;
    if (result == Err::ok) {
        state_->applied = true;
        state_->events.push_back(make(request_id, "apply_prepared",
                                      {{"silent", kApplySilent}, {"restart_args", restart_args}, {"target", t}}));
    } else {
        state_->downloaded_request = -1;  // the next attempt must download/verify again
    }
    return result;
}

std::vector<Event> Bridge::poll_events() {
    bool stop_now = false;
    int64_t last = 0;
    {
        std::lock_guard<std::mutex> g(state_->m);
        stop_now = state_->shutdown && !state_->busy && !state_->stop_emitted;
        last = state_->last_request;
    }
    if (stop_now) {
        if (worker_.joinable()) worker_.join();  // job already finished; join is immediate
        std::lock_guard<std::mutex> g(state_->m);
        state_->stop_emitted = true;
        state_->events.push_back(make(last, "worker_stopped"));
    }
    std::lock_guard<std::mutex> g(state_->m);
    std::vector<Event> out(std::make_move_iterator(state_->events.begin()),
                           std::make_move_iterator(state_->events.end()));
    state_->events.clear();
    return out;
}

bool Bridge::is_busy() {
    std::lock_guard<std::mutex> g(state_->m);
    return state_->busy;
}

void Bridge::request_shutdown() {
    std::lock_guard<std::mutex> g(state_->m);
    state_->shutdown = true;  // stops admission and apply; worker_stopped is emitted by poll_events
}

// ---------------------------------------------------------------- real Velopack adapter
namespace {

std::string self_exe() {
#if defined(__linux__)
    std::error_code ec;
    return fs::read_symlink("/proc/self/exe", ec).u8string();
#elif defined(__APPLE__)
    char buf[4096];
    uint32_t n = sizeof buf;
    return _NSGetExecutablePath(buf, &n) == 0 ? std::string(buf) : std::string();
#else
    std::wstring w(32768, L'\0');
    DWORD n = GetModuleFileNameW(nullptr, w.data(), static_cast<DWORD>(w.size()));
    return fs::path(w.substr(0, n)).u8string();
#endif
}

std::string xml_text(const std::string& xml, const std::string& tag) {
    std::smatch m;
    std::regex re("<" + tag + ">([^<]*)</" + tag + ">");
    return std::regex_search(xml, m, re) ? m[1].str() : "";
}

// Same paths the pinned default locator derives (locator.rs:463-559 Linux,
// 562-622 macOS, 367-460 Windows); only read here, after the SDK located the app.
struct Layout { std::string manifest, packages; };

Layout derive_layout(const std::string& exe, const std::string& app_id) {
#if defined(__linux__)
    auto i = exe.find("/usr/bin/");
    if (i == std::string::npos) return {};
    return {exe.substr(0, i) + "/usr/bin/sq.version", "/var/tmp/velopack/" + app_id + "/packages"};
#elif defined(__APPLE__)
    // compile-unproved
    auto i = exe.find(".app/");
    const char* home = std::getenv("HOME");
    if (i == std::string::npos || !home) return {};
    std::string app = exe.substr(0, i + 4);
    std::string m = app + "/Contents/MacOS/sq.version";
    if (!fs::exists(fs::u8path(m))) m = app + "/Contents/Resources/sq.version";
    return {m, std::string(home) + "/Library/Caches/velopack/" + app_id + "/packages"};
#else
    // compile-unproved; ignores the read-only-root LocalAppData fallback (locator.rs:153-180).
    auto i = exe.rfind("\\current\\");
    if (i == std::string::npos) return {};
    std::string root = exe.substr(0, i);
    return {root + "\\current\\sq.version", root + "\\packages"};
#endif
}

class VelopackSdk final : public Sdk {
public:
    Installed locate() override {
        // Default discovery from the real process (no explicit locator, no network).
        Velopack::UpdateManager um(std::make_unique<Velopack::FileSource>("."));
        Installed in;
        in.app_id = um.GetAppId();
        in.version = um.GetCurrentVersion();
        Layout l = derive_layout(self_exe(), in.app_id);
        std::ifstream f(fs::u8path(l.manifest), std::ios::binary);
        std::string xml((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
        if (xml_text(xml, "id") != in.app_id || xml_text(xml, "version") != in.version) {
            in.reason = "installed manifest " + l.manifest + " disagrees with the SDK locator";
            return in;
        }
        in.channel = xml_text(xml, "channel");
        std::error_code ec;  // Velopack creates the dir on first download; an existing one must be safe
        if (fs::exists(fs::u8path(l.packages), ec)) {
            if (std::string bad = cache_dir_problem(l.packages); !bad.empty()) {
                in.reason = bad;
                return in;
            }
        }
        in.packages_dir = l.packages;
        in.ok = true;
        return in;
    }

    std::optional<Asset> check(const Target& t, uint64_t timeout_ms) override {
        auto um = manager(t, timeout_ms);
        auto info = um->CheckForUpdates();
        if (!info) return std::nullopt;
        return to_asset(info->TargetFullRelease);
    }

    // The frozen target (already matched against the feed by check) is the
    // UpdateInfo: no second feed request, and the SDK verifies its SHA-256.
    void download(const Target& t, uint64_t timeout_ms, const std::function<void(int)>& progress) override {
        auto um = manager(t, timeout_ms);
        Velopack::UpdateInfo info{asset(t), std::nullopt, {}, false};
        um->DownloadUpdates(info, [](void* p, size_t pct) {
            (*static_cast<const std::function<void(int)>*>(p))(static_cast<int>(pct));
        }, const_cast<std::function<void(int)>*>(&progress));
    }

    void apply(const Target& t, bool silent, const std::vector<std::string>& restart_args) override {
        auto um = manager(t, 0);
        um->WaitExitThenApplyUpdates(asset(t), silent, true, restart_args);
    }

private:
    static Velopack::VelopackAsset asset(const Target& t) {
        return {t.app_id, t.version, "Full", t.full_filename, "", t.sha256, static_cast<uint64_t>(t.size), "", ""};
    }
    static Asset to_asset(const Velopack::VelopackAsset& a) {
        return Asset{a.PackageId, a.Version, a.Type, a.FileName, a.SHA256, a.Size};
    }
    static std::unique_ptr<Velopack::UpdateManager> manager(const Target& t, uint64_t timeout_ms) {
        Velopack::HttpOptions http{{}, timeout_ms};
        Velopack::UpdateOptions opts{false, t.channel, -1};  // full packages only
        return std::make_unique<Velopack::UpdateManager>(std::make_unique<Velopack::HttpSource>(t.base_url, http),
                                                         &opts);
    }
};

}  // namespace

std::shared_ptr<Sdk> make_velopack_sdk() { return std::make_shared<VelopackSdk>(); }

}  // namespace tortuga_updater
