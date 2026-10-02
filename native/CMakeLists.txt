cmake_minimum_required(VERSION 3.24)
project(tortuga_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(TORTUGA_TOOLCHAIN_ROOT "" CACHE PATH "Verified toolchain root containing toolchain.json (bootstrap_toolchain.py fetch)")
set(TORTUGA_IDENTITY_HEADER "" CACHE FILEPATH "Generated release_identity.h (Plan 02); empty = development identity")

# --- Build target platform key (must equal the receipt's platform) ---
if(WIN32)
  set(TORTUGA_PLATFORM windows-x86_64)
elseif(APPLE)
  set(TORTUGA_PLATFORM macos-universal)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64)$")
  set(TORTUGA_PLATFORM linux-x86_64)
else()
  message(FATAL_ERROR "Unsupported build target ${CMAKE_SYSTEM_NAME}/${CMAKE_SYSTEM_PROCESSOR}")
endif()

# --- Toolchain receipt (contract: docs/phase-2/release-contracts.md) ---
set(_receipt "${TORTUGA_TOOLCHAIN_ROOT}/toolchain.json")
if(NOT TORTUGA_TOOLCHAIN_ROOT OR NOT EXISTS "${_receipt}")
  message(FATAL_ERROR "TORTUGA_TOOLCHAIN_ROOT must name a verified toolchain root; missing ${_receipt}")
endif()
file(READ "${_receipt}" _r)
string(JSON _schema GET "${_r}" schema_version)
string(JSON _platform GET "${_r}" platform)
if(NOT _schema EQUAL 1)
  message(FATAL_ERROR "toolchain.json schema_version ${_schema} != 1")
endif()
if(NOT _platform STREQUAL TORTUGA_PLATFORM)
  message(FATAL_ERROR "toolchain.json platform '${_platform}' != build target '${TORTUGA_PLATFORM}'")
endif()

# The receipt's cmake_args define TORTUGA_* paths; explicit -D values win.
string(JSON _n LENGTH "${_r}" cmake_args)
if(_n GREATER 0)
  math(EXPR _last "${_n} - 1")
  foreach(_i RANGE ${_last})
    string(JSON _arg GET "${_r}" cmake_args ${_i})
    if(NOT _arg MATCHES "^-D([A-Z0-9_]+)=(.*)$")
      message(FATAL_ERROR "unexpected receipt cmake_args entry: ${_arg}")
    endif()
    if(NOT DEFINED ${CMAKE_MATCH_1})
      set(${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
    endif()
    if(NOT EXISTS "${${CMAKE_MATCH_1}}")
      message(FATAL_ERROR "${CMAKE_MATCH_1} does not exist: ${${CMAKE_MATCH_1}}")
    endif()
  endforeach()
endif()
if(NOT TORTUGA_VELOPACK_ROOT OR NOT EXISTS "${TORTUGA_VELOPACK_ROOT}/include/Velopack.hpp")
  message(FATAL_ERROR "TORTUGA_VELOPACK_ROOT (receipt cmake_args or -D) must contain include/Velopack.hpp")
endif()
string(JSON TORTUGA_ENGINE GET "${_r}" tools engine)

# --- Build identity: Plan 02 header, else development-only defaults ---
if(TORTUGA_IDENTITY_HEADER)
  if(NOT EXISTS "${TORTUGA_IDENTITY_HEADER}")
    message(FATAL_ERROR "TORTUGA_IDENTITY_HEADER does not exist: ${TORTUGA_IDENTITY_HEADER}")
  endif()
  set(_identity "${TORTUGA_IDENTITY_HEADER}")
else()
  set(_identity "${CMAKE_CURRENT_SOURCE_DIR}/common/development_identity.h")
endif()
configure_file("${_identity}" "${CMAKE_CURRENT_BINARY_DIR}/generated/release_identity.h" COPYONLY)
add_library(tortuga_identity INTERFACE)
target_include_directories(tortuga_identity INTERFACE "${CMAKE_CURRENT_BINARY_DIR}/generated")

# --- Velopack native SDK (static) ---
set(_vp_static "${TORTUGA_VELOPACK_ROOT}/lib-static")
if(TORTUGA_PLATFORM STREQUAL "linux-x86_64")
  set(_vp_libs "${_vp_static}/velopack_libc_linux_x64_gnu.a")
elseif(TORTUGA_PLATFORM STREQUAL "macos-universal")
  # ponytail: compile-unproved; ld picks the matching thin archive per slice.
  set(_vp_libs "${_vp_static}/velopack_libc_osx_arm64_gnu.a" "${_vp_static}/velopack_libc_osx_x64_gnu.a")
else()
  # compile-unproved; the .lib declares /DEFAULTLIB:LIBCMT, so use the static CRT.
  set(_vp_libs "${_vp_static}/velopack_libc_win_x64_msvc.lib")
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()
find_package(Threads REQUIRED)

# --- Launcher ---
add_executable(tortuga_launcher launcher/main.cpp)
set_target_properties(tortuga_launcher PROPERTIES OUTPUT_NAME Tortuga)
target_include_directories(tortuga_launcher PRIVATE "${TORTUGA_VELOPACK_ROOT}/include")
target_link_libraries(tortuga_launcher PRIVATE ${_vp_libs} Threads::Threads ${CMAKE_DL_LIBS})
if(MSVC)  # compile-unproved: GUI subsystem (no console flash) keeping the wmain entry.
  set_target_properties(tortuga_launcher PROPERTIES WIN32_EXECUTABLE ON)
  target_link_options(tortuga_launcher PRIVATE /ENTRY:wmainCRTStartup)
endif()
install(TARGETS tortuga_launcher RUNTIME DESTINATION bin)

# --- Updater bridge core (plain C++, no godot-cpp; unit-tested with a fake SDK) ---
add_library(tortuga_bridge_core STATIC updater/updater_bridge.cpp)
set_target_properties(tortuga_bridge_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(tortuga_bridge_core PUBLIC updater PRIVATE "${TORTUGA_VELOPACK_ROOT}/include")
target_link_libraries(tortuga_bridge_core PUBLIC ${_vp_libs} Threads::Threads ${CMAKE_DL_LIBS})

# --- GDExtension: godot-cpp pinned in the receipt, built against the dumped 4.7.2 API ---
if(NOT TORTUGA_GODOT_CPP_ROOT OR NOT EXISTS "${TORTUGA_GODOT_CPP_ROOT}/CMakeLists.txt")
  message(FATAL_ERROR "TORTUGA_GODOT_CPP_ROOT (receipt cmake_args or -D) must be a godot-cpp source tree")
endif()
set(GODOTCPP_TARGET template_release CACHE STRING "" FORCE)
set(GODOTCPP_CUSTOM_API_FILE "${TORTUGA_GODOT_EXTENSION_API}" CACHE FILEPATH "" FORCE)
# godot-cpp defaults to -static-libstdc++ on Linux; this Fedora host has no
# libstdc++.a (libstdc++-static not installed), so link it dynamically like the
# launcher. Revisit with the Plan 02 older-glibc build environment.
if(TORTUGA_PLATFORM STREQUAL "linux-x86_64")
  set(GODOTCPP_USE_STATIC_CPP OFF CACHE BOOL "" FORCE)
endif()
add_subdirectory("${TORTUGA_GODOT_CPP_ROOT}" godot-cpp EXCLUDE_FROM_ALL)
get_target_property(_gdcpp_suffix godot-cpp GODOTCPP_SUFFIX)

add_library(tortuga_updater SHARED updater/register_types.cpp)
target_compile_definitions(tortuga_updater PRIVATE TORTUGA_BUILD_PLATFORM="${TORTUGA_PLATFORM}")
target_link_libraries(tortuga_updater PRIVATE tortuga_bridge_core tortuga_identity godot-cpp)
set_target_properties(tortuga_updater PROPERTIES
  PREFIX "lib" OUTPUT_NAME "tortuga_updater${_gdcpp_suffix}"
  CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
if(TORTUGA_PLATFORM STREQUAL "linux-x86_64")
  # Keep the static Velopack/Rust archive's vpkc_* symbols out of the dynamic table.
  target_link_options(tortuga_updater PRIVATE "LINKER:--exclude-libs,ALL")
endif()
# Mirrors res://native/bin/ (game/native/tortuga_updater.gdextension); Plan 02 copies <prefix>/native/ over it.
install(TARGETS tortuga_updater LIBRARY DESTINATION native/bin RUNTIME DESTINATION native/bin)

# --- Tests (POSIX harness; Windows launcher tests are blocked until a native host exists) ---
enable_testing()
if(NOT WIN32)
  add_executable(tortuga_fake_game tests/fake_game.cpp)
  add_executable(test_launcher tests/test_launcher.cpp)
  target_include_directories(test_launcher PRIVATE "${TORTUGA_VELOPACK_ROOT}/include")
  target_link_libraries(test_launcher PRIVATE tortuga_identity ${_vp_libs} Threads::Threads ${CMAKE_DL_LIBS})

  set(_launcher_cases helpers windows_quoting unrelated_cwd unicode_path quotes_and_empty_args
      user_boundary missing_game nonexecutable_game lifecycle_only)
  set(_netguard -)
  if(TORTUGA_PLATFORM STREQUAL "linux-x86_64")
    list(APPEND _launcher_cases real_godot)
    add_library(tortuga_netguard SHARED tests/netguard.cpp)
    set(_netguard $<TARGET_FILE:tortuga_netguard>)
  endif()
  foreach(_case IN LISTS _launcher_cases)
    add_test(NAME launcher_paths_and_arguments.${_case}
      COMMAND test_launcher ${_case} $<TARGET_FILE:tortuga_launcher> $<TARGET_FILE:tortuga_fake_game>
              ${_netguard} "${TORTUGA_ENGINE}" "${CMAKE_CURRENT_SOURCE_DIR}/..")
    set_tests_properties(launcher_paths_and_arguments.${_case} PROPERTIES LABELS launcher TIMEOUT 120)
  endforeach()
  add_test(NAME identity_build_identity COMMAND test_launcher identity)
  set_tests_properties(identity_build_identity PROPERTIES LABELS identity)

  add_executable(test_bridge tests/test_bridge.cpp)
  target_link_libraries(test_bridge PRIVATE tortuga_bridge_core)
  foreach(_case identity_and_locator serialized_events target_mismatch cache_safety sha256)
    add_test(NAME bridge_${_case} COMMAND test_bridge ${_case})
    set_tests_properties(bridge_${_case} PROPERTIES LABELS bridge TIMEOUT 60)
  endforeach()
endif()
