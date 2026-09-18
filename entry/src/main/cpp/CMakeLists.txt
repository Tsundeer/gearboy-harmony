# Gearboy for HarmonyOS — native C++ module
# Builds the vendored Gearboy core (platform-independent, C++11, no third-party
# deps besides the single-file miniz needed for .zip ROM support) plus the
# NAPI bridge that drives an XComponent NativeWindow.

cmake_minimum_required(VERSION 3.5.0)
project(gearboy_harmony)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/vendor/gearboy
)

# ---- vendored Gearboy core: compile every .cpp of the upstream src/ tree ----
file(GLOB GEARBOY_VENDOR_SRC ${NATIVERENDER_ROOT_PATH}/vendor/gearboy/*.cpp)
file(GLOB GEARBOY_VENDOR_AUDIO_SRC ${NATIVERENDER_ROOT_PATH}/vendor/gearboy/audio/*.cpp)
# miniz.c is plain C (zip container support used by Cartridge.cpp)
list(APPEND GEARBOY_VENDOR_SRC ${NATIVERENDER_ROOT_PATH}/vendor/gearboy/miniz.c)

add_library(gearboy SHARED
    napi/emu_napi.cpp
    ${GEARBOY_VENDOR_SRC}
    ${GEARBOY_VENDOR_AUDIO_SRC}
)

target_compile_definitions(gearboy PUBLIC EMULATOR_BUILD="harmony-ohos")

target_link_libraries(gearboy PUBLIC
    libace_napi.z.so
    libace_ndk.z.so
    libnative_window.so
    libhilog_ndk.z.so
)
