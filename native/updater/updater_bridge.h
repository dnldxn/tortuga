// Tortuga updater bridge core: plain C++ (no godot-cpp). The Godot class in
// register_types.cpp is a thin Dictionary <-> struct wrapper around Bridge.
// Contract: docs/phase-2/release-contracts.md ("Updater bridge").
#pragma once

#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

namespace tortuga_updater {

// Whole-request HttpSource deadlines (spec §4). Task 4 tests the real deadlines.
constexpr uint64_t kCheckTimeoutMs = 30000;
constexpr uint64_t kDownloadTimeoutMs = 600000;
// Velopack's helper UI may ask for pkexec elevation; --silent forbids that
// (l18n dialogs.rs:103-105), so apply is never silent.
constexpr bool kApplySilent = false;

// Compiled schema-1 build identity (release_identity.h) plus the build platform.
struct Identity {
    int schema = 1;
    std::string app_id, package_version, channel, platform;
    bool is_release = false;
};

// Frozen copy of a schema-1 manifest platform entry plus the derived exact base.
struct Target {
    std::string app_id, channel, platform, version, base_url, full_filename, sha256, minimum_os;
    int64_t size = 0;
};

// Independently observed installation (never taken from the compiled identity).
struct Installed {
    bool ok = false;
    std::string reason, app_id, version, channel, packages_dir;
};

// A feed release as reported by the SDK (copied out of Velopack types).
struct Asset {
    std::string package_id, version, type, filename, sha256;
    uint64_t size = 0;
};

// Narrow SDK adapter: the only seam between the bridge and Velopack. Each call
// builds and owns its own manager for the duration of that call. Errors throw.
class Sdk {
public:
    virtual ~Sdk() = default;
    virtual Installed locate() = 0;
    virtual std::optional<Asset> check(const Target& t, uint64_t timeout_ms) = 0;
    virtual void download(const Target& t, uint64_t timeout_ms, const std::function<void(int)>& progress) = 0;
    virtual void apply(const Target& t, bool silent, const std::vector<std::string>& restart_args) = 0;
};

// Real adapter over the pinned Velopack C++ SDK (default locator discovery).
std::shared_ptr<Sdk> make_velopack_sdk();

using Field = std::variant<bool, int64_t, std::string, std::vector<std::string>, Target>;
using Fields = std::vector<std::pair<std::string, Field>>;

struct Event {
    int64_t request_id = 0;
    std::string kind;  // checked|progress|downloaded|apply_prepared|error|worker_stopped
    Fields payload;
};

struct IdentityReport {
    bool available = false;
    std::string reason;
    Identity identity;
    std::string platform_key;
    std::vector<std::pair<std::string, std::string>> os;
    Installed installed;
};

enum class Err { ok, busy, unavailable, invalid, failed };

std::string sha256_hex(const std::string& bytes);
std::string sha256_file_hex(const std::string& path);  // "" if unreadable
std::vector<std::pair<std::string, std::string>> observe_os();
std::string validate_target(const Target& t, const Identity& id);  // "" = valid
// "" when every component of the absolute cache dir is a real directory that
// another local user cannot write or replace (POSIX); otherwise the reason.
std::string cache_dir_problem(const std::string& dir);

class Bridge {
public:
    Bridge(Identity compiled, std::shared_ptr<Sdk> sdk,
           std::vector<std::pair<std::string, std::string>> os = observe_os());
    ~Bridge();  // stops admission, then joins the worker (never unloads under it)
    Bridge(const Bridge&) = delete;
    Bridge& operator=(const Bridge&) = delete;

    IdentityReport identity();
    Err begin_check(const Target& t, int64_t request_id);
    Err begin_download(const Target& t, int64_t request_id);
    Err prepare_apply(int64_t request_id, const std::vector<std::string>& restart_args);
    std::vector<Event> poll_events();
    bool is_busy();
    void request_shutdown();  // non-blocking; worker_stopped is polled after the join

    struct State;  // shared with the worker thread

private:
    Err admit(IdentityReport& report);
    Err release(Err e);
    void start(int64_t request_id, std::function<void()> job);

    Identity compiled_;
    std::shared_ptr<Sdk> sdk_;
    std::vector<std::pair<std::string, std::string>> os_;
    std::shared_ptr<State> state_;
    std::thread worker_;
};

}  // namespace tortuga_updater
