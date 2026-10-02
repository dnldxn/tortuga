// bridge_* CTest cases: the plain C++ bridge core with an injected fake SDK.
//   test_bridge <case>
#include "../updater/updater_bridge.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <sys/stat.h>
#include <unistd.h>

using namespace tortuga_updater;
namespace fs = std::filesystem;

static int failures = 0;
#define CHECK(cond, what)                                                       \
    do {                                                                        \
        if (cond) std::cout << "ok   " << what << "\n";                         \
        else { std::cout << "FAIL " << what << "  (" #cond ")\n"; ++failures; } \
    } while (0)

// ---------------------------------------------------------------- fixtures
static const std::string kBytes = "tortuga full package bytes v0.2.0";

static Identity release_id() { return {1, "org.tortuga.game", "0.1.0", "linux-test", "linux-x86_64", true}; }
static std::vector<std::pair<std::string, std::string>> linux_os() {
    return {{"system", "Linux"}, {"machine", "x86_64"}, {"release", "test"}, {"glibc", "2.43"}};
}
static Target good_target() {
    return {"org.tortuga.game", "linux-test", "linux-x86_64", "0.2.0",
            "https://github.com/dnldxn/tortuga/releases/download/v0.2/", "org.tortuga.game-0.2.0-linux-test-full.nupkg",
            sha256_hex(kBytes), "", static_cast<int64_t>(kBytes.size())};
}
static Asset asset_of(const Target& t) { return {t.app_id, t.version, "Full", t.full_filename, t.sha256, uint64_t(t.size)}; }

struct Gate {  // lets a test hold the worker inside an SDK call
    std::mutex m;
    std::condition_variable cv;
    bool open = true, entered = false;
    void enter() {
        std::unique_lock<std::mutex> l(m);
        entered = true;
        cv.notify_all();
        cv.wait(l, [&] { return open; });
    }
    void release() { std::lock_guard<std::mutex> g(m); open = true; cv.notify_all(); }
    void wait_entered() { std::unique_lock<std::mutex> l(m); cv.wait(l, [&] { return entered; }); }
};

struct FakeSdk : Sdk {
    Installed installed;
    std::optional<Asset> feed;
    std::string download_bytes = kBytes;
    std::vector<int> progress_steps = {0, 0, 10, 10, 55, 100};
    bool apply_throws = false;
    Gate gate;
    std::mutex m;
    std::vector<Target> checked, downloaded, applied;
    std::vector<bool> applied_silent;
    std::vector<std::vector<std::string>> applied_args;
    std::vector<uint64_t> timeouts;
    std::thread::id worker_thread;
    std::atomic<int> locates{0};

    Installed locate() override { ++locates; return installed; }
    std::optional<Asset> check(const Target& t, uint64_t timeout) override {
        gate.enter();
        std::lock_guard<std::mutex> g(m);
        checked.push_back(t);
        timeouts.push_back(timeout);
        worker_thread = std::this_thread::get_id();
        return feed;
    }
    void download(const Target& t, uint64_t timeout, const std::function<void(int)>& progress) override {
        gate.enter();
        {
            std::lock_guard<std::mutex> g(m);
            downloaded.push_back(t);
            timeouts.push_back(timeout);
        }
        for (int p : progress_steps) progress(p);
        fs::create_directories(installed.packages_dir);
        std::ofstream(fs::path(installed.packages_dir) / t.full_filename, std::ios::binary) << download_bytes;
    }
    void apply(const Target& t, bool silent, const std::vector<std::string>& args) override {
        if (apply_throws) throw std::runtime_error("helper launch failed");
        applied.push_back(t);
        applied_silent.push_back(silent);
        applied_args.push_back(args);
    }
};

static fs::path scratch() {
    fs::path p = fs::temp_directory_path() / ("tortuga-bridge-" + std::to_string(getpid()));
    fs::remove_all(p);
    fs::create_directories(p);
    return p;
}

static std::shared_ptr<FakeSdk> installed_sdk(const fs::path& root) {
    auto sdk = std::make_shared<FakeSdk>();
    sdk->installed = {true, "", "org.tortuga.game", "0.1.0", "linux-test", (root / "packages").string()};
    sdk->feed = asset_of(good_target());
    return sdk;
}

// Polls until an event of `kind` arrives (or 5 s); collects everything seen.
static std::vector<Event> drain_until(Bridge& b, const std::string& kind) {
    std::vector<Event> all;
    for (int i = 0; i < 500; ++i) {
        for (auto& e : b.poll_events()) all.push_back(e);
        for (auto& e : all) if (e.kind == kind) return all;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    return all;
}

static const Field* field(const Event& e, const std::string& k) {
    for (auto& [name, v] : e.payload) if (name == k) return &v;
    return nullptr;
}
template <class T> static T get(const Event& e, const std::string& k) {
    const Field* f = field(e, k);
    return f && std::holds_alternative<T>(*f) ? std::get<T>(*f) : T{};
}
static bool same(const Target& a, const Target& b) {
    return a.app_id == b.app_id && a.channel == b.channel && a.platform == b.platform && a.version == b.version &&
           a.base_url == b.base_url && a.full_filename == b.full_filename && a.sha256 == b.sha256 && a.size == b.size;
}
static int count(const std::vector<Event>& ev, const std::string& kind) {
    int n = 0;
    for (auto& e : ev) n += e.kind == kind;
    return n;
}

// ---------------------------------------------------------------- cases
static void identity_and_locator() {
    fs::path root = scratch();
    auto sdk = installed_sdk(root);

    {
        Identity dev{1, "org.tortuga.game", "0.0.0-dev", "dev", "linux-x86_64", false};
        Bridge b(dev, sdk, linux_os());
        IdentityReport r = b.identity();
        CHECK(!r.available && r.reason.find("development build") != std::string::npos, "development identity unavailable: " << r.reason);
        Target dt = good_target();
        dt.channel = "dev";
        CHECK(b.begin_check(dt, 1) == Err::unavailable, "development begin_check -> unavailable");
        CHECK(b.begin_check(good_target(), 1) == Err::invalid, "target for another channel -> invalid before locating");
        CHECK(b.prepare_apply(1, {}) == Err::unavailable, "development prepare_apply -> unavailable");
    }
    {
        Bridge b(release_id(), sdk, linux_os());
        IdentityReport r = b.identity();
        CHECK(r.available && r.reason.empty(), "matching installed release available");
        CHECK(r.platform_key == "linux-x86_64", "platform_key from observed OS: " << r.platform_key);
        bool glibc = false;
        for (auto& [k, v] : r.os) glibc = glibc || (k == "glibc" && v == "2.43");
        CHECK(glibc, "os carries observed glibc");
        CHECK(r.identity.app_id == "org.tortuga.game" && r.identity.package_version == "0.1.0", "nested compiled identity");
    }
    struct Case { const char* label; std::function<void(Installed&)> mutate; const char* why; };
    std::vector<Case> cases = {
        {"missing install", [](Installed& i) { i = Installed{false, "UpdateNix does not exist"}; }, "not an installed package"},
        {"wrong app id", [](Installed& i) { i.app_id = "org.other.game"; }, "installed app id"},
        {"wrong version", [](Installed& i) { i.version = "0.2.0"; }, "installed version"},
        {"wrong channel", [](Installed& i) { i.channel = "osx-test"; }, "installed channel"},
        {"no packages dir", [](Installed& i) { i.packages_dir.clear(); }, "package cache"},
    };
    for (auto& c : cases) {
        auto s2 = installed_sdk(root);
        c.mutate(s2->installed);
        Bridge b(release_id(), s2, linux_os());
        IdentityReport r = b.identity();
        CHECK(!r.available && r.reason.find(c.why) != std::string::npos, c.label << " -> unavailable: " << r.reason);
        CHECK(b.begin_check(good_target(), 7) == Err::unavailable, c.label << " begin_check -> unavailable");
    }
    {
        Bridge b(release_id(), sdk, {{"system", "Darwin"}, {"machine", "arm64"}});
        CHECK(!b.identity().available, "running platform mismatch -> unavailable");
    }
    {
        struct Throwing : FakeSdk { Installed locate() override { throw std::runtime_error("boom"); } };
        Bridge b(release_id(), std::make_shared<Throwing>(), linux_os());
        IdentityReport r = b.identity();
        CHECK(!r.available && r.reason.find("locator failed: boom") != std::string::npos, "locator exception -> unavailable");
    }
    {
        // Real pinned Velopack default locator in this (non-installed) test process.
        Bridge b(release_id(), make_velopack_sdk());
        IdentityReport r = b.identity();
        CHECK(!r.available && r.reason.find("locator failed") != std::string::npos, "real SDK, not installed -> unavailable: " << r.reason);
        bool glibc = false;
        for (auto& [k, v] : r.os) glibc = glibc || (k == "glibc" && !v.empty());
        CHECK(glibc && r.platform_key == "linux-x86_64", "real observe_os: glibc + linux-x86_64");
    }
    fs::remove_all(root);
}

static void serialized_events() {
    fs::path root = scratch();
    auto sdk = installed_sdk(root);
    Bridge b(release_id(), sdk, linux_os());

    Target t = good_target();
    sdk->gate.open = false;
    CHECK(b.begin_check(t, 41) == Err::ok, "begin_check accepted");
    sdk->gate.wait_entered();
    t.version = "9.9.9";  // caller mutation after begin
    t.sha256 = std::string(64, 'f');
    CHECK(b.is_busy(), "busy while worker runs");
    int locates = sdk->locates;
    CHECK(b.begin_check(good_target(), 42) == Err::busy, "duplicate begin_check -> busy");
    CHECK(b.begin_download(good_target(), 41) == Err::busy, "begin_download while busy -> busy");
    CHECK(b.prepare_apply(41, {}) == Err::busy, "prepare_apply while busy -> busy");
    CHECK(sdk->locates == locates, "busy admission never calls the SDK locator");
    CHECK(b.poll_events().empty(), "no event before the SDK call returns");
    sdk->gate.release();
    auto ev = drain_until(b, "checked");
    CHECK(count(ev, "checked") == 1 && ev.back().request_id == 41, "checked carries request 41");
    CHECK(sdk->worker_thread != std::this_thread::get_id(), "SDK check ran on the worker thread");
    CHECK(sdk->checked.size() == 1 && same(sdk->checked[0], good_target()), "SDK saw the frozen target, not the mutation");
    CHECK(sdk->timeouts.size() == 1 && sdk->timeouts[0] == 30000, "check deadline 30000 ms");
    const Event& c = ev.back();
    CHECK(get<bool>(c, "compatible") && get<bool>(c, "update_available"), "checked compatible + update_available");
    CHECK(field(c, "requirement") && get<std::string>(c, "requirement").empty(), "checked requirement present");
    CHECK(same(get<Target>(c, "target"), good_target()), "checked payload target is the frozen copy");

    for (int i = 0; i < 100 && b.is_busy(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(5));
    CHECK(b.begin_download(good_target(), 41) == Err::ok, "begin_download accepted for checked request");
    ev = drain_until(b, "downloaded");
    int progress = 0;
    bool ids = true;
    std::vector<int64_t> pcts;
    for (auto& e : ev) {
        ids = ids && e.request_id == 41;
        if (e.kind == "progress") { ++progress; pcts.push_back(get<int64_t>(e, "percent")); }
    }
    CHECK(ids, "every download event carries request 41");
    CHECK((pcts == std::vector<int64_t>{0, 10, 55, 100}), "progress throttled on percent change (4 events, got " << progress << ")");
    CHECK(count(ev, "downloaded") == 1 && !get<bool>(ev.back(), "cached"), "downloaded (fresh) after progress");
    CHECK(sdk->timeouts.size() == 2 && sdk->timeouts[1] == 600000, "download deadline 600000 ms");
    CHECK(b.poll_events().empty(), "queue drained exactly once");

    // Shutdown: non-blocking while a worker is busy; worker_stopped only after the join.
    Bridge b2(release_id(), sdk, linux_os());
    sdk->feed = asset_of(good_target());
    sdk->gate.open = false;
    sdk->gate.entered = false;
    CHECK(b2.begin_check(good_target(), 77) == Err::ok, "second bridge begin_check");
    sdk->gate.wait_entered();
    auto t0 = std::chrono::steady_clock::now();
    b2.request_shutdown();
    CHECK(std::chrono::steady_clock::now() - t0 < std::chrono::milliseconds(100), "request_shutdown returns without waiting");
    CHECK(count(b2.poll_events(), "worker_stopped") == 0, "no worker_stopped while the worker is inside the SDK");
    CHECK(b2.begin_check(good_target(), 78) == Err::unavailable, "admission stopped after request_shutdown");
    sdk->gate.release();
    ev = drain_until(b2, "worker_stopped");
    CHECK(count(ev, "worker_stopped") == 1 && ev.back().kind == "worker_stopped" && ev.back().request_id == 77,
          "worker_stopped once, last, for request 77");
    CHECK(!b2.is_busy() && b2.poll_events().empty(), "idle and no repeat after worker_stopped");

    {   // Destruction while busy joins the worker before returning.
        auto s3 = installed_sdk(root);
        s3->gate.open = false;
        auto b3 = std::make_unique<Bridge>(release_id(), s3, linux_os());
        CHECK(b3->begin_check(good_target(), 90) == Err::ok, "third bridge begin_check");
        s3->gate.wait_entered();
        std::thread opener([s3] { std::this_thread::sleep_for(std::chrono::milliseconds(50)); s3->gate.release(); });
        b3.reset();
        CHECK(s3->checked.size() == 1, "destructor returned only after the SDK call finished");
        opener.join();
    }
    fs::remove_all(root);
}

static void target_mismatch() {
    fs::path root = scratch();
    // Invalid targets are rejected before any SDK call.
    struct Bad { const char* label; std::function<void(Target&)> mutate; };
    std::vector<Bad> bad = {
        {"app id", [](Target& t) { t.app_id = "org.other"; }},
        {"channel", [](Target& t) { t.channel = "osx-test"; }},
        {"platform", [](Target& t) { t.platform = "macos-universal"; }},
        {"unnormalized version", [](Target& t) { t.version = "0.2"; }},
        {"base url host", [](Target& t) { t.base_url = "https://evil.example/v0.2/"; }},
        {"base url tag", [](Target& t) { t.base_url = "https://github.com/dnldxn/tortuga/releases/download/v0.3/"; }},
        {"path filename", [](Target& t) { t.full_filename = "../x-full.nupkg"; }},
        {"non-nupkg filename", [](Target& t) { t.full_filename = "x.AppImage"; }},
        {"uppercase sha", [](Target& t) { t.sha256 = std::string(64, 'A'); }},
        {"short sha", [](Target& t) { t.sha256 = "abc"; }},
        {"zero size", [](Target& t) { t.size = 0; }},
        {"patch version", [](Target& t) {
             t.version = "0.2.1";
             t.base_url = "https://github.com/dnldxn/tortuga/releases/download/v0.2/";
         }},
        {"major version", [](Target& t) {
             t.version = "1.2.0";
             t.base_url = "https://github.com/dnldxn/tortuga/releases/download/v1.2/";
         }},
        {"huge glibc minimum_os", [](Target& t) { t.minimum_os = "glibc 99999999999999999999.1"; }},
        {"5-digit glibc minimum_os", [](Target& t) { t.minimum_os = "glibc 2.10000"; }},
        {"unknown minimum_os grammar", [](Target& t) { t.minimum_os = "macOS 12"; }},
    };
    for (auto& c : bad) {
        auto sdk = installed_sdk(root);
        Bridge b(release_id(), sdk, linux_os());
        Target t = good_target();
        c.mutate(t);
        CHECK(validate_target(t, release_id()) != "" && b.begin_check(t, 5) == Err::invalid && !b.is_busy(),
              "invalid target (" << c.label << ") -> invalid");
        CHECK(sdk->checked.empty(), "no SDK call for invalid " << c.label);
    }

    auto expect_error = [&](std::shared_ptr<FakeSdk> sdk, Target t, const std::string& needle, const char* label) {
        Bridge b(release_id(), sdk, linux_os());
        CHECK(b.begin_check(t, 11) == Err::ok, label << ": begin_check");
        auto ev = drain_until(b, "error");
        CHECK(count(ev, "error") == 1 && ev.back().request_id == 11 &&
                  get<std::string>(ev.back(), "message").find(needle) != std::string::npos,
              label << ": " << (ev.empty() ? "" : get<std::string>(ev.back(), "message")));
        for (int i = 0; i < 100 && b.is_busy(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(5));
        CHECK(b.begin_download(t, 11) == Err::invalid, label << ": download refused after failed check");
    };
    {
        auto sdk = installed_sdk(root);
        sdk->feed.reset();
        expect_error(sdk, good_target(), "feed missing expected release 0.2.0", "null feed for newer target");
    }
    std::vector<std::pair<const char*, std::function<void(Asset&)>>> feed_mismatch = {
        {"feed newer version", [](Asset& a) { a.version = "0.3.0"; }},
        {"feed other filename", [](Asset& a) { a.filename = "other-full.nupkg"; }},
        {"feed other sha", [](Asset& a) { a.sha256 = std::string(64, '0'); }},
        {"feed other size", [](Asset& a) { a.size += 1; }},
        {"feed delta asset", [](Asset& a) { a.type = "Delta"; }},
        {"feed other package id", [](Asset& a) { a.package_id = "org.other"; }},
    };
    for (auto& [label, mutate] : feed_mismatch) {
        auto sdk = installed_sdk(root);
        mutate(*sdk->feed);
        expect_error(sdk, good_target(), "does not match the manifest target", label);
    }
    {   // A non-std exception inside the worker becomes an error event, never std::terminate.
        struct Throwing : FakeSdk {
            std::optional<Asset> check(const Target&, uint64_t) override { throw 42; }
        };
        auto sdk = std::make_shared<Throwing>();
        sdk->installed = installed_sdk(root)->installed;
        Bridge b(release_id(), sdk, linux_os());
        CHECK(b.begin_check(good_target(), 12) == Err::ok, "begin_check with a throwing SDK");
        auto ev = drain_until(b, "error");
        CHECK(count(ev, "error") == 1 && ev.back().request_id == 12 &&
                  get<std::string>(ev.back(), "message") == "internal error",
              "non-std exception -> error 'internal error'");
        for (int i = 0; i < 100 && b.is_busy(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(5));
        CHECK(!b.is_busy(), "bridge idle after worker exception");
    }
    {   // Target not newer than installed: checked without a feed request, never eligible.
        auto sdk = installed_sdk(root);
        Bridge b(release_id(), sdk, linux_os());
        Target t = good_target();
        t.version = "0.1.0";
        t.base_url = "https://github.com/dnldxn/tortuga/releases/download/v0.1/";
        CHECK(b.begin_check(t, 3) == Err::ok, "current-version target accepted");
        auto ev = drain_until(b, "checked");
        CHECK(count(ev, "checked") == 1 && !get<bool>(ev.back(), "update_available") && sdk->checked.empty(),
              "current version -> update_available false, no feed request");
    }
    {   // Unproved minimum-OS grammar or too-new glibc -> incompatible, no feed request.
        auto sdk = installed_sdk(root);
        Bridge b(release_id(), sdk, linux_os());
        Target t = good_target();
        t.minimum_os = "glibc 2.99";
        CHECK(b.begin_check(t, 4) == Err::ok, "incompatible target accepted for reporting");
        auto ev = drain_until(b, "checked");
        CHECK(count(ev, "checked") == 1 && !get<bool>(ev.back(), "compatible") &&
                  get<std::string>(ev.back(), "requirement") == "glibc 2.99" && sdk->checked.empty(),
              "glibc 2.99 > 2.43 -> incompatible, no feed request");
    }

    // Download / apply preconditions.
    auto sdk = installed_sdk(root);
    Bridge b(release_id(), sdk, linux_os());
    CHECK(b.begin_download(good_target(), 20) == Err::invalid, "download without a check -> invalid");
    CHECK(b.prepare_apply(20, {}) == Err::invalid, "apply without a download -> invalid");
    CHECK(b.begin_check(good_target(), 20) == Err::ok, "check 20");
    drain_until(b, "checked");
    for (int i = 0; i < 100 && b.is_busy(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(5));
    CHECK(b.begin_download(good_target(), 21) == Err::invalid, "download with another request id -> invalid");
    Target changed = good_target();
    changed.size += 1;
    CHECK(b.begin_download(changed, 20) == Err::invalid, "download with a changed target -> invalid");
    CHECK(b.prepare_apply(20, {}) == Err::invalid, "apply before download completes -> invalid");

    // Corrupt download: error, selected file removed, apply refused.
    sdk->download_bytes = "tampered";
    CHECK(b.begin_download(good_target(), 20) == Err::ok, "download 20 (corrupt bytes)");
    auto ev = drain_until(b, "error");
    fs::path pkg = fs::path(sdk->installed.packages_dir) / good_target().full_filename;
    CHECK(count(ev, "downloaded") == 0 && count(ev, "error") == 1 && !fs::exists(pkg), "corrupt download -> error, file removed");
    for (int i = 0; i < 100 && b.is_busy(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(5));
    CHECK(b.prepare_apply(20, {}) == Err::invalid, "apply after corrupt download -> invalid");

    // Tampered pre-existing cache (right size, wrong bytes): only that file removed, SDK not called.
    sdk->download_bytes = kBytes;
    std::string same_size(kBytes.size(), 'x');
    std::ofstream(pkg, std::ios::binary) << same_size;
    fs::path sibling = fs::path(sdk->installed.packages_dir) / "org.tortuga.game-0.1.0-linux-test-full.nupkg";
    std::ofstream(sibling, std::ios::binary) << "current";
    size_t downloads = sdk->downloaded.size();
    CHECK(b.begin_download(good_target(), 20) == Err::ok, "download 20 (tampered cache)");
    ev = drain_until(b, "error");
    CHECK(count(ev, "error") == 1 && get<std::string>(ev.back(), "message").find("cached package SHA-256") != std::string::npos,
          "tampered cache -> error: " << get<std::string>(ev.back(), "message"));
    CHECK(!fs::exists(pkg) && fs::exists(sibling) && sdk->downloaded.size() == downloads,
          "only the selected cached file removed; no SDK download");
    for (int i = 0; i < 100 && b.is_busy(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(5));

    // Fresh retry downloads and verifies; then a valid cache is reused without the SDK.
    CHECK(b.begin_download(good_target(), 20) == Err::ok, "retry download 20");
    ev = drain_until(b, "downloaded");
    CHECK(count(ev, "downloaded") == 1 && fs::exists(pkg), "retry downloaded verified bytes");
    for (int i = 0; i < 100 && b.is_busy(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(5));
    downloads = sdk->downloaded.size();
    CHECK(b.begin_download(good_target(), 20) == Err::ok, "download again (valid cache)");
    ev = drain_until(b, "downloaded");
    CHECK(get<bool>(ev.back(), "cached") && sdk->downloaded.size() == downloads, "valid cache reused without SDK download");
    for (int i = 0; i < 100 && b.is_busy(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(5));

    CHECK(b.prepare_apply(21, {}) == Err::invalid, "apply with the wrong request -> invalid");
    // Bytes swapped after download: apply re-verifies and refuses.
    std::ofstream(pkg, std::ios::binary) << same_size;
    CHECK(b.prepare_apply(20, {}) == Err::failed && sdk->applied.empty() && !fs::exists(pkg), "swapped bytes -> apply refused, file removed");
    ev = b.poll_events();
    CHECK(count(ev, "error") == 1 && count(ev, "apply_prepared") == 0, "refusal is an error event, no apply_prepared");
    CHECK(b.prepare_apply(20, {}) == Err::invalid, "refused apply requires a new download");

    CHECK(b.begin_download(good_target(), 20) == Err::ok, "download 20 again");
    drain_until(b, "downloaded");
    for (int i = 0; i < 100 && b.is_busy(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(5));
    sdk->apply_throws = true;
    CHECK(b.prepare_apply(20, {"--x"}) == Err::failed && !b.is_busy(), "helper failure -> failed, bridge usable");
    ev = b.poll_events();
    CHECK(count(ev, "error") == 1 && count(ev, "apply_prepared") == 0, "helper failure emits error only");

    CHECK(b.begin_download(good_target(), 20) == Err::ok, "download 20 after helper failure");
    drain_until(b, "downloaded");
    for (int i = 0; i < 100 && b.is_busy(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(5));
    sdk->apply_throws = false;
    CHECK(b.prepare_apply(20, {"a b", "", "--updater-x"}) == Err::ok, "prepare_apply success");
    ev = b.poll_events();
    CHECK(count(ev, "apply_prepared") == 1 && ev.back().request_id == 20, "apply_prepared for request 20");
    CHECK(sdk->applied.size() == 1 && same(sdk->applied[0], good_target()) && sdk->applied_silent[0] == false &&
              (sdk->applied_args[0] == std::vector<std::string>{"a b", "", "--updater-x"}),
          "SDK apply got frozen target, silent=false, exact restart args");
    CHECK(b.begin_check(good_target(), 30) == Err::unavailable && b.prepare_apply(20, {}) == Err::unavailable,
          "nothing admitted after apply_prepared");
    fs::remove_all(root);
}

static bool wait_idle(Bridge& b) {
    for (int i = 0; i < 200 && b.is_busy(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(5));
    return !b.is_busy();
}

static void cache_safety() {
    fs::path root = scratch();
    fs::path pkgs = root / "packages";
    fs::create_directories(pkgs);
    fs::permissions(root, fs::perms(0755));
    fs::permissions(pkgs, fs::perms(0755));
    CHECK(cache_dir_problem(pkgs.string()).empty(), "own 0755 dir under sticky /tmp is safe: " << cache_dir_problem(pkgs.string()));
    CHECK(!cache_dir_problem("relative/packages").empty(), "relative cache dir refused");
    CHECK(!cache_dir_problem((root / "nope").string()).empty(), "missing cache dir refused");
    CHECK(cache_dir_problem("/").find("not owned") != std::string::npos, "dir not owned by this user refused");
    fs::permissions(pkgs, fs::perms(0775));
    CHECK(cache_dir_problem(pkgs.string()).find("writable") != std::string::npos, "group-writable cache dir refused");
    fs::permissions(pkgs, fs::perms(0757));
    CHECK(cache_dir_problem(pkgs.string()).find("writable") != std::string::npos, "world-writable cache dir refused");
    fs::permissions(pkgs, fs::perms(0755));
    fs::permissions(root, fs::perms(0777));
    CHECK(cache_dir_problem(pkgs.string()).find("writable") != std::string::npos, "world-writable non-root parent refused");
    fs::permissions(root, fs::perms(0755));
    fs::create_directory_symlink(pkgs, root / "link");
    CHECK(cache_dir_problem((root / "link").string()).find("not a directory") != std::string::npos, "symlinked cache dir refused");

    auto sdk = installed_sdk(root);
    Target t = good_target();
    fs::path pkg = pkgs / t.full_filename;
    auto checked_bridge = [&](Bridge& b, int64_t id) {
        CHECK(b.begin_check(t, id) == Err::ok, "check " << id);
        drain_until(b, "checked");
        wait_idle(b);
    };

    {   // World-writable existing cache dir: error, the valid file is neither read as cache nor deleted.
        Bridge b(release_id(), sdk, linux_os());
        checked_bridge(b, 50);
        std::ofstream(pkg, std::ios::binary) << kBytes;
        fs::permissions(pkgs, fs::perms(0777));
        CHECK(b.begin_download(t, 50) == Err::ok, "download with world-writable cache dir");
        auto ev = drain_until(b, "error");
        CHECK(count(ev, "error") == 1 && count(ev, "downloaded") == 0 &&
                  get<std::string>(ev.back(), "message").find("writable") != std::string::npos,
              "world-writable dir -> error: " << get<std::string>(ev.back(), "message"));
        CHECK(fs::exists(pkg) && sdk->downloaded.empty(), "nothing deleted or downloaded in an unsafe dir");
        fs::permissions(pkgs, fs::perms(0755));
        fs::remove(pkg);
        wait_idle(b);
    }
    {   // Cached package that is a symlink to valid bytes: refused, both link and target kept.
        Bridge b(release_id(), sdk, linux_os());
        checked_bridge(b, 51);
        fs::path elsewhere = root / "elsewhere.nupkg";
        std::ofstream(elsewhere, std::ios::binary) << kBytes;
        fs::create_symlink(elsewhere, pkg);
        CHECK(b.begin_download(t, 51) == Err::ok, "download with symlinked cache file");
        auto ev = drain_until(b, "error");
        CHECK(count(ev, "error") == 1 && count(ev, "downloaded") == 0 &&
                  get<std::string>(ev.back(), "message").find("not a regular file") != std::string::npos,
              "symlinked cached package -> error");
        CHECK(fs::is_symlink(pkg) && fs::exists(elsewhere) && sdk->downloaded.empty(), "symlink and target untouched, no download");
        fs::remove(pkg);
        wait_idle(b);

        // Verified download, then swapped for a symlink before apply: refused, nothing applied or deleted.
        CHECK(b.begin_download(t, 51) == Err::ok, "fresh download 51");
        drain_until(b, "downloaded");
        wait_idle(b);
        fs::remove(pkg);
        fs::create_symlink(elsewhere, pkg);
        CHECK(b.prepare_apply(51, {}) == Err::failed && sdk->applied.empty(), "symlink swapped in before apply -> failed");
        ev = b.poll_events();
        CHECK(count(ev, "error") == 1 && fs::is_symlink(pkg) && fs::exists(elsewhere), "apply refusal keeps link + target");
    }
    fs::remove_all(root);
}

static void sha256_vectors() {
    // FIPS 180-4 / NIST CAVP examples.
    CHECK(sha256_hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256('')");
    CHECK(sha256_hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256('abc')");
    CHECK(sha256_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
              "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "sha256(448-bit message)");
    CHECK(sha256_hex(std::string(1000000, 'a')) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
          "sha256(1,000,000 x 'a')");
    fs::path root = scratch();
    std::string big(200000, '\0');
    for (size_t i = 0; i < big.size(); ++i) big[i] = static_cast<char>(i * 7);
    std::ofstream(root / "f", std::ios::binary) << big;
    CHECK(sha256_file_hex((root / "f").string()) == sha256_hex(big), "file hash == memory hash across chunks");
    CHECK(sha256_file_hex((root / "missing").string()).empty(), "unreadable file -> empty");
    fs::remove_all(root);
}

int main(int argc, char** argv) {
    std::map<std::string, void (*)()> cases = {{"identity_and_locator", identity_and_locator},
                                               {"serialized_events", serialized_events},
                                               {"target_mismatch", target_mismatch},
                                               {"cache_safety", cache_safety},
                                               {"sha256", sha256_vectors}};
    if (argc != 2 || !cases.count(argv[1])) { std::cerr << "usage: test_bridge <case>\n"; return 2; }
    cases[argv[1]]();
    std::cout << (failures ? "FAILED " : "PASSED ") << argv[1] << " (" << failures << " failures)\n";
    return failures ? 1 : 0;
}
