// Development-only build identity, compiled when CMake gets no
// TORTUGA_IDENTITY_HEADER. Plan 02 generates the release header with the same
// macros. "0.0.0-dev" can never match a release version (0.N.0, N >= 1).
#pragma once

#define TORTUGA_IDENTITY_SCHEMA 1
#define TORTUGA_APP_ID "org.tortuga.game"
#define TORTUGA_PACKAGE_VERSION "0.0.0-dev"
#define TORTUGA_CHANNEL "dev"
#define TORTUGA_IS_RELEASE 0
