// TortugaUpdaterBridge: thin Godot wrapper (Dictionary <-> struct) over the
// plain C++ Bridge. Only plain Variants cross this boundary; no SDK objects.
#include <gdextension_interface.h>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <memory>

#include "release_identity.h"
#include "updater_bridge.h"

using namespace godot;
namespace tu = tortuga_updater;

namespace {

String s(const std::string& v) { return String::utf8(v.c_str(), static_cast<int>(v.size())); }
std::string s(const String& v) {
    CharString c = v.utf8();
    return std::string(c.get_data(), static_cast<size_t>(c.length()));
}

Dictionary to_dict(const tu::Target& t) {
    Dictionary d;
    d["app_id"] = s(t.app_id);
    d["channel"] = s(t.channel);
    d["platform"] = s(t.platform);
    d["version"] = s(t.version);
    d["base_url"] = s(t.base_url);
    d["full_filename"] = s(t.full_filename);
    d["sha256"] = s(t.sha256);
    d["size"] = t.size;
    d["minimum_os"] = s(t.minimum_os);
    return d;
}

// Every key required with the exact Variant type; anything else is invalid.
// size must be an int: Plan 03 converts the JSON number (a float after
// JSON.parse) to an exact int and rejects fractional/out-of-range values first.
bool from_dict(const Dictionary& d, tu::Target& t) {
    const char* strings[] = {"app_id", "channel", "platform", "version", "base_url", "full_filename", "sha256",
                             "minimum_os"};
    std::string* fields[] = {&t.app_id, &t.channel, &t.platform, &t.version, &t.base_url, &t.full_filename,
                             &t.sha256, &t.minimum_os};
    for (int i = 0; i < 8; ++i) {
        Variant v = d.get(strings[i], Variant());
        if (v.get_type() != Variant::STRING) return false;
        *fields[i] = s(String(v));
    }
    Variant size = d.get("size", Variant());
    if (size.get_type() != Variant::INT) return false;
    t.size = int64_t(size);
    return true;
}

struct ToVariant {
    Variant operator()(bool v) const { return v; }
    Variant operator()(int64_t v) const { return v; }
    Variant operator()(const std::string& v) const { return s(v); }
    Variant operator()(const std::vector<std::string>& v) const {
        PackedStringArray a;
        for (auto& x : v) a.push_back(s(x));
        return a;
    }
    Variant operator()(const tu::Target& v) const { return to_dict(v); }
};

Error to_error(tu::Err e) {
    switch (e) {
        case tu::Err::ok: return OK;
        case tu::Err::busy: return ERR_BUSY;
        case tu::Err::unavailable: return ERR_UNAVAILABLE;
        case tu::Err::invalid: return ERR_INVALID_PARAMETER;
        default: return FAILED;
    }
}

tu::Identity compiled_identity() {
    return tu::Identity{TORTUGA_IDENTITY_SCHEMA, TORTUGA_APP_ID, TORTUGA_PACKAGE_VERSION, TORTUGA_CHANNEL,
                        TORTUGA_BUILD_PLATFORM, TORTUGA_IS_RELEASE != 0};
}

}  // namespace

class TortugaUpdaterBridge : public RefCounted {
    GDCLASS(TortugaUpdaterBridge, RefCounted)

    std::unique_ptr<tu::Bridge> bridge = std::make_unique<tu::Bridge>(compiled_identity(), tu::make_velopack_sdk());

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("get_identity"), &TortugaUpdaterBridge::get_identity);
        ClassDB::bind_method(D_METHOD("begin_check", "target", "request_id"), &TortugaUpdaterBridge::begin_check);
        ClassDB::bind_method(D_METHOD("begin_download", "target", "request_id"), &TortugaUpdaterBridge::begin_download);
        ClassDB::bind_method(D_METHOD("prepare_apply", "request_id", "restart_args"), &TortugaUpdaterBridge::prepare_apply);
        ClassDB::bind_method(D_METHOD("poll_events"), &TortugaUpdaterBridge::poll_events);
        ClassDB::bind_method(D_METHOD("is_busy"), &TortugaUpdaterBridge::is_busy);
        ClassDB::bind_method(D_METHOD("request_shutdown"), &TortugaUpdaterBridge::request_shutdown);
    }

public:
    Dictionary get_identity() {
        tu::IdentityReport r = bridge->identity();
        Dictionary id, os, d;
        id["schema"] = r.identity.schema;
        id["app_id"] = s(r.identity.app_id);
        id["package_version"] = s(r.identity.package_version);
        id["channel"] = s(r.identity.channel);
        id["platform"] = s(r.identity.platform);
        id["is_release"] = r.identity.is_release;
        for (auto& [k, v] : r.os) os[s(k)] = s(v);
        d["available"] = r.available;
        d["reason"] = s(r.reason);
        d["identity"] = id;
        d["platform_key"] = s(r.platform_key);
        d["os"] = os;
        return d;
    }

    Error begin_check(const Dictionary& target, int64_t request_id) {
        tu::Target t;
        if (!from_dict(target, t)) return ERR_INVALID_PARAMETER;  // no locate for a malformed target
        return to_error(bridge->begin_check(t, request_id));
    }

    Error begin_download(const Dictionary& target, int64_t request_id) {
        tu::Target t;
        if (!from_dict(target, t)) return ERR_INVALID_PARAMETER;  // no locate for a malformed target
        return to_error(bridge->begin_download(t, request_id));
    }

    Error prepare_apply(int64_t request_id, const PackedStringArray& restart_args) {
        std::vector<std::string> args;
        for (int64_t i = 0; i < restart_args.size(); ++i) args.push_back(s(restart_args[i]));
        return to_error(bridge->prepare_apply(request_id, args));
    }

    // Main-thread drain: fresh Dictionaries built from copied events.
    TypedArray<Dictionary> poll_events() {
        TypedArray<Dictionary> out;
        for (auto& e : bridge->poll_events()) {
            Dictionary payload, d;
            for (auto& [k, v] : e.payload) payload[s(k)] = std::visit(ToVariant{}, v);
            d["request_id"] = e.request_id;
            d["kind"] = s(e.kind);
            d["payload"] = payload;
            out.push_back(d);
        }
        return out;
    }

    bool is_busy() { return bridge->is_busy(); }
    void request_shutdown() { bridge->request_shutdown(); }
};

namespace {
void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) GDREGISTER_CLASS(TortugaUpdaterBridge);
}
void uninitialize(ModuleInitializationLevel) {}
}  // namespace

extern "C" GDExtensionBool GDE_EXPORT tortuga_updater_init(GDExtensionInterfaceGetProcAddress get_proc_address,
                                                           GDExtensionClassLibraryPtr library,
                                                           GDExtensionInitialization* init) {
    GDExtensionBinding::InitObject obj(get_proc_address, library, init);
    obj.register_initializer(initialize);
    obj.register_terminator(uninitialize);
    obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return obj.init();
}
