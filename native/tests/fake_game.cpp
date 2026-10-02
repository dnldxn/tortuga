// Stand-in for the exported Godot binary in launcher tests (POSIX). Writes
// "pid\nexe\ncwd\nfds\n" then each argv[1..] terminated by '\0' to
// $TORTUGA_FAKE_GAME_OUT. fds = targets of inherited descriptors > 2, ';'-joined.
// TORTUGA_FAKE_GAME_NET=1 performs one getaddrinfo (netguard positive control).
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <netdb.h>
#include <string>
#include <unistd.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

namespace fs = std::filesystem;

static std::string self_exe() {
#ifdef __APPLE__
    char buf[4096];
    uint32_t size = sizeof buf;
    return _NSGetExecutablePath(buf, &size) == 0 ? fs::canonical(buf).string() : "";
#else
    return fs::read_symlink("/proc/self/exe").string();
#endif
}

int main(int argc, char** argv) {
    const char* out = std::getenv("TORTUGA_FAKE_GAME_OUT");
    if (!out) return 3;
    if (std::getenv("TORTUGA_FAKE_GAME_NET")) {
        addrinfo* res = nullptr;
        if (getaddrinfo("localhost", nullptr, nullptr, &res) == 0) freeaddrinfo(res);
    }
    std::string fds;
    std::error_code ec;
    for (int fd = 3; fd < 256; ++fd) {
        fs::path target = fs::read_symlink("/dev/fd/" + std::to_string(fd), ec);
        if (!ec) fds += target.string() + ";";
    }
    FILE* f = std::fopen(out, "wb");
    if (!f) return 4;
    std::fprintf(f, "%d\n%s\n%s\n%s\n", static_cast<int>(getpid()), self_exe().c_str(),
                 fs::current_path().c_str(), fds.c_str());
    for (int i = 1; i < argc; ++i) std::fwrite(argv[i], 1, std::strlen(argv[i]) + 1, f);
    std::fclose(f);
    return 0;
}
