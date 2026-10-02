// LD_PRELOAD test shim (Linux): any socket/connect/getaddrinfo call appends its
// name to $TORTUGA_NETGUARD_OUT and fails, so tests can assert "no network".
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <netdb.h>
#include <sys/socket.h>

static void mark(const char* what) {
    if (const char* out = std::getenv("TORTUGA_NETGUARD_OUT")) {
        if (FILE* f = std::fopen(out, "a")) { std::fprintf(f, "%s\n", what); std::fclose(f); }
    }
}

extern "C" int socket(int, int, int) { mark("socket"); errno = EACCES; return -1; }
extern "C" int connect(int, const sockaddr*, socklen_t) { mark("connect"); errno = EACCES; return -1; }
extern "C" int getaddrinfo(const char*, const char*, const addrinfo*, addrinfo**) { mark("getaddrinfo"); return EAI_FAIL; }
