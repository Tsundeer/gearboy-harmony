/*
 * Gearboy for HarmonyOS — NAPI thin shell (slot E1)
 *
 * Bridges the vendored Gearboy core to ArkTS:
 *   loadRom(bytes, name?) / runFrame() / setKey(key, pressed)
 *   saveState(slot) / loadState(slot) / reset()
 *   setSaveDir(dir) / isRomLoaded()
 *
 * Rendering: every runFrame() runs one emulated frame and blits the
 * 160x144 RGB565 frame buffer (nearest-neighbour scaled) into the
 * XComponent NativeWindow as RGBA8888 (pure software rendering).
 * Audio: muted in phase 1 (OHAudio planned for phase 2).
 *
 * Core copyright (C) 2012 Ignacio Sanchez, Gearboy, GPLv3+ (see vendor LICENSE).
 */
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <napi/native_api.h>
#include <native_buffer/buffer_common.h>
#include <native_window/external_window.h>
#include <hilog/log.h>

#include <unistd.h>

#include <mutex>
#include <string>
#include <vector>
#include <fstream>

#include "gearboy.h"

// Frontend flag expected by the core's log.h (silences stdio logging when the
// core is driven by an MCP server; we always run as a GUI frontend -> false).
bool g_mcp_stdio_mode = false;

#define GB_LOG_DOMAIN 0x0000
#define GB_LOG_TAG "GearboyNapi"

// ---------------------------------------------------------------------------
// Emulator state
// ---------------------------------------------------------------------------

namespace {

struct EmuState
{
    GearboyCore* core;
    bool rom_loaded;
    std::string rom_name;
    std::string save_dir;
    u16 frame_buffer[GAMEBOY_WIDTH * GAMEBOY_HEIGHT];
    s16 audio_buffer[AUDIO_BUFFER_SIZE];
    int audio_samples;
    OHNativeWindow* window;
    uint32_t surface_width;
    uint32_t surface_height;
    std::vector<uint16_t> column_lut;

    EmuState() : core(NULL), rom_loaded(false), window(NULL),
                 surface_width(0), surface_height(0)
    {
        memset(frame_buffer, 0, sizeof(frame_buffer));
        memset(audio_buffer, 0, sizeof(audio_buffer));
        audio_samples = 0;
    }
};

EmuState g_state;
std::mutex g_mutex; // NAPI calls and surface callbacks may arrive on different threads

// Virtual key order expected from ArkTS setKey()
enum EmuKey
{
    KEY_UP = 0,
    KEY_DOWN = 1,
    KEY_LEFT = 2,
    KEY_RIGHT = 3,
    KEY_A = 4,
    KEY_B = 5,
    KEY_SELECT = 6,
    KEY_START = 7,
    KEY_COUNT = 8
};

const Gameboy_Keys kKeyMap[KEY_COUNT] =
{
    Up_Key, Down_Key, Left_Key, Right_Key, A_Key, B_Key, Select_Key, Start_Key
};

inline uint32_t Rgb565ToRgba8888(u16 pixel)
{
    const uint32_t r5 = (pixel >> 11) & 0x1F;
    const uint32_t g6 = (pixel >> 5) & 0x3F;
    const uint32_t b5 = pixel & 0x1F;
    const uint32_t r8 = (r5 << 3) | (r5 >> 2);
    const uint32_t g8 = (g6 << 2) | (g6 >> 4);
    const uint32_t b8 = (b5 << 3) | (b5 >> 2);
    return 0xFF000000u | (r8 << 16) | (g8 << 8) | b8;
}

void InitCore()
{
    if (g_state.core != NULL)
        return;

    g_state.core = new GearboyCore();
    g_state.core->Init(GB_PIXEL_RGB565);
    g_state.core->SetSoundSampleRate(GB_AUDIO_SAMPLE_RATE);
    g_state.core->SetSoundMute(true); // phase 1: audio muted, OHAudio in phase 2
    g_state.core->SetSGBEnabled(false); // keep the frame buffer at 160x144
    g_state.core->SetSGBBorder(false);
    g_state.rom_loaded = false;
    g_state.rom_name = "rom";
}

std::string SanitizeName(const std::string& name)
{
    std::string clean;
    const size_t max_len = 64;
    for (size_t i = 0; i < name.size() && clean.size() < max_len; ++i)
    {
        const char c = name[i];
        const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.';
        if (ok)
            clean += c;
    }
    if (clean.empty())
        clean = "rom";
    return clean;
}

std::string SaveStateFilePath(const std::string& base_name, int slot)
{
    std::string dir = g_state.save_dir;
    if (dir.empty())
        dir = ".";
    std::string path = dir;
    if (!path.empty() && path[path.size() - 1] != '/')
        path += "/";
    path += base_name;
    path += ".slot";
    path += std::to_string(slot);
    path += ".state";
    return path;
}

static int blit_dbg = 0;
static int blit_cnt = 0;
// ---------------------------------------------------------------------------
// Rendering: blit 160x144 RGB565 -> surface RGBA8888 (nearest neighbour)
// ---------------------------------------------------------------------------

void BlitFrame()
{
    if (!blit_dbg++ ) OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "GearboyDbg", "BlitFrame first call, window=%{public}p", g_state.window);
    OHNativeWindowBuffer* buffer = NULL;
    int fence_fd = -1;

    if (OH_NativeWindow_NativeWindowRequestBuffer(g_state.window, &buffer, &fence_fd) != 0)
        return;

    if (fence_fd >= 0)
        close(fence_fd);

    BufferHandle* handle = OH_NativeWindow_GetBufferHandleFromNative(buffer);
    if (handle == NULL || handle->virAddr == NULL || handle->width <= 0 || handle->height <= 0)
    {
        OH_NativeWindow_NativeWindowAbortBuffer(g_state.window, buffer);
        return;
    }

    const int w = handle->width;
    const int h = handle->height;
    const int stride_pixels = handle->stride / 4;

    if (g_state.surface_width != (uint32_t)w || g_state.surface_height != (uint32_t)h ||
        g_state.column_lut.empty())
    {
        g_state.surface_width = (uint32_t)w;
        g_state.surface_height = (uint32_t)h;
        g_state.column_lut.resize(w);
        for (int x = 0; x < w; ++x)
            g_state.column_lut[x] = (uint16_t)((x * GAMEBOY_WIDTH) / w);
    }

    uint32_t* dst = (uint32_t*)handle->virAddr;
    for (int y = 0; y < h; ++y)
    {
        const u16* src_row = g_state.frame_buffer + ((y * GAMEBOY_HEIGHT) / h) * GAMEBOY_WIDTH;
        uint32_t* dst_row = dst + (size_t)y * (size_t)stride_pixels;
        for (int x = 0; x < w; ++x)
            dst_row[x] = Rgb565ToRgba8888(src_row[g_state.column_lut[x]]);
    }

    Region region;
    region.rects = NULL;    // NULL/0 = whole buffer dirty
    region.rectNumber = 0;
    OH_NativeWindow_NativeWindowFlushBuffer(g_state.window, buffer, -1, region);
}

// ---------------------------------------------------------------------------
// XComponent surface lifecycle
// ---------------------------------------------------------------------------

void ConfigureWindowGeometry()
{
    OH_NativeWindow_NativeWindowHandleOpt(g_state.window, SET_FORMAT,
                                          NATIVEBUFFER_PIXEL_FMT_RGBA_8888);
    OH_NativeWindow_NativeWindowHandleOpt(g_state.window, SET_BUFFER_GEOMETRY,
                                          (uint32_t)g_state.surface_width,
                                          (uint32_t)g_state.surface_height);
}

void OnSurfaceCreatedCB(OH_NativeXComponent* component, void* window)
{
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "GearboyDbg", "OnSurfaceCreated fired! window=%{public}p", window);
    (void)component;
    std::lock_guard<std::mutex> lock(g_mutex);
    g_state.window = (OHNativeWindow*)window;

    uint64_t width = 0;
    uint64_t height = 0;
    if (OH_NativeXComponent_GetXComponentSize(component, window, &width, &height)
        == OH_NATIVEXCOMPONENT_RESULT_SUCCESS && width > 0 && height > 0)
    {
        g_state.surface_width = (uint32_t)width;
        g_state.surface_height = (uint32_t)height;
    }
    else
    {
        // Fallback: a sane 4x window around the GB resolution
        g_state.surface_width = GAMEBOY_WIDTH * 4;
        g_state.surface_height = GAMEBOY_HEIGHT * 4;
    }

    ConfigureWindowGeometry();
    g_state.column_lut.clear();
    OH_LOG_Print(LOG_APP, LOG_INFO, GB_LOG_DOMAIN, GB_LOG_TAG,
                 "Surface created: %{public}ux%{public}u", g_state.surface_width,
                 g_state.surface_height);
}

void OnSurfaceChangedCB(OH_NativeXComponent* component, void* window)
{
    (void)window;
    std::lock_guard<std::mutex> lock(g_mutex);

    uint64_t width = 0;
    uint64_t height = 0;
    if (OH_NativeXComponent_GetXComponentSize(component, window, &width, &height)
        == OH_NATIVEXCOMPONENT_RESULT_SUCCESS && width > 0 && height > 0)
    {
        if (g_state.surface_width != (uint32_t)width ||
            g_state.surface_height != (uint32_t)height)
        {
            g_state.surface_width = (uint32_t)width;
            g_state.surface_height = (uint32_t)height;
            g_state.column_lut.clear();
            if (g_state.window != NULL)
                ConfigureWindowGeometry();
        }
    }
}

void OnSurfaceDestroyedCB(OH_NativeXComponent* component, void* window)
{
    (void)component;
    (void)window;
    std::lock_guard<std::mutex> lock(g_mutex);
    g_state.window = NULL;
    g_state.column_lut.clear();
    OH_LOG_Print(LOG_APP, LOG_INFO, GB_LOG_DOMAIN, GB_LOG_TAG, "Surface destroyed");
}

void DispatchTouchEventCB(OH_NativeXComponent* component, void* window)
{
    // Touch input is delivered from ArkTS via setKey(); nothing to do here.
    (void)component;
    (void)window;
}

OH_NativeXComponent_Callback g_xcomponent_callback = {
    OnSurfaceCreatedCB,
    OnSurfaceChangedCB,
    OnSurfaceDestroyedCB,
    DispatchTouchEventCB
};

// ---------------------------------------------------------------------------
// NAPI helpers
// ---------------------------------------------------------------------------

napi_value BoolValue(napi_env env, bool value)
{
    napi_value result = NULL;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value UndefinedValue(napi_env env)
{
    napi_value result = NULL;
    napi_get_undefined(env, &result);
    return result;
}

std::string NapiStringArg(napi_env env, napi_value value, const std::string& fallback)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, NULL, 0, &length) != napi_ok)
        return fallback;
    std::vector<char> buffer(length + 1, 0);
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &copied) != napi_ok)
        return fallback;
    return std::string(buffer.data(), copied);
}

// ---------------------------------------------------------------------------
// Exported NAPI functions
// ---------------------------------------------------------------------------

// loadRom(romBytes: ArrayBuffer, romName?: string): boolean
napi_value LoadRom(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {NULL, NULL};
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);

    if (argc < 1)
        return BoolValue(env, false);

    void* data = NULL;
    size_t length = 0;
    if (napi_get_arraybuffer_info(env, args[0], &data, &length) != napi_ok ||
        data == NULL || length <= 0)
    {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GB_LOG_DOMAIN, GB_LOG_TAG, "loadRom: bad ArrayBuffer");
        return BoolValue(env, false);
    }

    std::string rom_name = "rom";
    if (argc >= 2)
    {
        napi_valuetype type = napi_undefined;
        napi_typeof(env, args[1], &type);
        if (type == napi_string)
            rom_name = SanitizeName(NapiStringArg(env, args[1], "rom"));
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    InitCore();

    g_state.rom_name = rom_name;
    g_state.core->SetSGBEnabled(false);
    g_state.core->SetSGBBorder(false);
    const bool ok = g_state.core->LoadROMFromBuffer((const u8*)data, (int)length, false,
                                                    Cartridge::CartridgeNotSupported, false);
    if (ok)
    {
        g_state.core->Pause(false);
        g_state.rom_loaded = true;
        OH_LOG_Print(LOG_APP, LOG_INFO, GB_LOG_DOMAIN, GB_LOG_TAG,
                     "ROM loaded: %{public}s (%{public}zu bytes)", g_state.rom_name.c_str(),
                     length);
    }
    else
    {
        g_state.rom_loaded = false;
        OH_LOG_Print(LOG_APP, LOG_ERROR, GB_LOG_DOMAIN, GB_LOG_TAG, "ROM load failed");
    }
    return BoolValue(env, ok);
}

// runFrame(): void — runs one frame and blits it to the NativeWindow
napi_value RunFrame(napi_env env, napi_callback_info info)
{
    (void)info;
    std::lock_guard<std::mutex> lock(g_mutex);

    if (!g_state.rom_loaded || g_state.core == NULL)
        return UndefinedValue(env);

    int sample_count = 0;
    g_state.core->RunToVBlank(g_state.frame_buffer, g_state.audio_buffer, &sample_count);
    g_state.audio_samples = sample_count;

    if (g_state.window != NULL)
        BlitFrame();

    return UndefinedValue(env);
}


// getFramePixels(): ArrayBuffer (RGBA8888, 160*144*4 bytes)
napi_value GetFramePixels(napi_env env, napi_callback_info info)
{
    (void)info;
    std::lock_guard<std::mutex> lock(g_mutex);

    const int PIXEL_COUNT = GAMEBOY_WIDTH * GAMEBOY_HEIGHT;
    const int BYTE_COUNT = PIXEL_COUNT * 4;

    // Reuse one persistent ArrayBuffer across frames to avoid per-frame
    // allocation churn (GC hiccups at 60 fps) in the ArkTS render loop.
    static napi_ref frame_ref = NULL;
    napi_value ab;
    void* data = NULL;
    if (frame_ref == NULL)
    {
        if (napi_create_arraybuffer(env, BYTE_COUNT, &data, &ab) != napi_ok)
            return UndefinedValue(env);
        napi_create_reference(env, ab, 1, &frame_ref);
    }
    else
    {
        if (napi_get_reference_value(env, frame_ref, &ab) != napi_ok)
            return UndefinedValue(env);
        size_t len = 0;
        napi_get_arraybuffer_info(env, ab, &data, &len);
    }

    if (g_state.core != NULL && g_state.rom_loaded)
    {
        // RGB565 → RGBA8888
        const u16* src = g_state.frame_buffer;
        uint8_t* dst = (uint8_t*)data;
        for (int i = 0; i < PIXEL_COUNT; ++i)
        {
            u16 p = src[i];
            dst[i*4+0] = (uint8_t)(((p >> 11) & 0x1F) << 3);
            dst[i*4+1] = (uint8_t)(((p >> 5)  & 0x3F) << 2);
            dst[i*4+2] = (uint8_t)((p & 0x1F) << 3);
            dst[i*4+3] = 0xFF;
        }
    }
    return ab;
}

// getAudioSamples(): ArrayBuffer (s16 mono @ GB_AUDIO_SAMPLE_RATE, one frame)
napi_value GetAudioSamples(napi_env env, napi_callback_info info)
{
    (void)info;
    std::lock_guard<std::mutex> lock(g_mutex);

    int count = 0;
    if (g_state.core != NULL && g_state.rom_loaded)
        count = g_state.audio_samples;
    if (count < 0)
        count = 0;
    if (count > AUDIO_BUFFER_SIZE)
        count = AUDIO_BUFFER_SIZE;

    napi_value ab;
    void* data = NULL;
    if (napi_create_arraybuffer(env, (size_t)count * sizeof(s16), &data, &ab) != napi_ok)
        return UndefinedValue(env);
    if (count > 0)
        memcpy(data, g_state.audio_buffer, (size_t)count * sizeof(s16));
    return ab;
}

// saveRam(): boolean — cartridge battery RAM (in-game saves), keyed by rom name
napi_value SaveRamNapi(napi_env env, napi_callback_info info)
{
    (void)info;
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_state.rom_loaded || g_state.core == NULL || g_state.save_dir.empty())
        return BoolValue(env, false);
    const std::string path = g_state.save_dir + "/" + g_state.rom_name + ".sav";
    g_state.core->SaveRam(path.c_str(), true);
    OH_LOG_Print(LOG_APP, LOG_INFO, GB_LOG_DOMAIN, GB_LOG_TAG, "saveRam -> %{public}s", path.c_str());
    return BoolValue(env, true);
}

// loadRam(): boolean — restore cartridge battery RAM if a save exists
napi_value LoadRamNapi(napi_env env, napi_callback_info info)
{
    (void)info;
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_state.rom_loaded || g_state.core == NULL || g_state.save_dir.empty())
        return BoolValue(env, false);
    const std::string path = g_state.save_dir + "/" + g_state.rom_name + ".sav";
    std::ifstream f(path.c_str());
    bool exists = f.good();
    f.close();
    if (!exists)
        return BoolValue(env, false);
    g_state.core->LoadRam(path.c_str(), true);
    OH_LOG_Print(LOG_APP, LOG_INFO, GB_LOG_DOMAIN, GB_LOG_TAG, "loadRam <- %{public}s", path.c_str());
    return BoolValue(env, true);
}

// setKey(key: number, pressed: boolean): void
napi_value SetKey(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {NULL, NULL};
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);

    if (argc < 2)
        return UndefinedValue(env);

    int32_t key = -1;
    bool pressed = false;
    napi_valuetype type = napi_undefined;
    napi_typeof(env, args[1], &type);
    if (type == napi_boolean)
        napi_get_value_bool(env, args[1], &pressed);

    if (napi_get_value_int32(env, args[0], &key) != napi_ok)
        return UndefinedValue(env);

    if (key < 0 || key >= KEY_COUNT)
        return UndefinedValue(env);

    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_state.core != NULL && g_state.rom_loaded)
    {
        if (pressed)
            g_state.core->KeyPressed(kKeyMap[key]);
        else
            g_state.core->KeyReleased(kKeyMap[key]);
    }
    return UndefinedValue(env);
}

// saveState(slot: number): boolean — writes a savestate file into the app sandbox
napi_value SaveState(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {NULL};
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);

    int32_t slot = 1;
    if (argc >= 1 && napi_get_value_int32(env, args[0], &slot) != napi_ok)
        slot = 1;
    if (slot < 0)
        slot = 0;

    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_state.rom_loaded || g_state.core == NULL)
        return BoolValue(env, false);

    const std::string path = SaveStateFilePath(g_state.rom_name, slot);
    const bool ok = g_state.core->SaveState(path.c_str(), -1, false);
    OH_LOG_Print(LOG_APP, LOG_INFO, GB_LOG_DOMAIN, GB_LOG_TAG, "saveState(%{public}d) -> %{public}s: %{public}s",
                 slot, path.c_str(), ok ? "ok" : "failed");
    return BoolValue(env, ok);
}

// loadState(slot: number): boolean
napi_value LoadState(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {NULL};
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);

    int32_t slot = 1;
    if (argc >= 1 && napi_get_value_int32(env, args[0], &slot) != napi_ok)
        slot = 1;
    if (slot < 0)
        slot = 0;

    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_state.rom_loaded || g_state.core == NULL)
        return BoolValue(env, false);

    const std::string path = SaveStateFilePath(g_state.rom_name, slot);
    const bool ok = g_state.core->LoadState(path.c_str(), -1, false);
    OH_LOG_Print(LOG_APP, LOG_INFO, GB_LOG_DOMAIN, GB_LOG_TAG, "loadState(%{public}d): %{public}s",
                 slot, ok ? "ok" : "missing/failed");
    return BoolValue(env, ok);
}

// reset(): boolean
napi_value Reset(napi_env env, napi_callback_info info)
{
    (void)info;
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_state.rom_loaded || g_state.core == NULL)
        return BoolValue(env, false);
    g_state.core->ResetROM(false, Cartridge::CartridgeNotSupported, false);
    return BoolValue(env, true);
}

// setSaveDir(dir: string): void — sandbox directory for savestates
napi_value SetSaveDir(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {NULL};
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);

    if (argc < 1)
        return UndefinedValue(env);

    std::lock_guard<std::mutex> lock(g_mutex);
    g_state.save_dir = NapiStringArg(env, args[0], "");
    return UndefinedValue(env);
}

// isRomLoaded(): boolean
napi_value IsRomLoaded(napi_env env, napi_callback_info info)
{
    (void)info;
    std::lock_guard<std::mutex> lock(g_mutex);
    return BoolValue(env, g_state.rom_loaded);
}

// ---------------------------------------------------------------------------
// Module registration (also hooks the XComponent)
// ---------------------------------------------------------------------------

napi_value Init(napi_env env, napi_value exports)
{
    const napi_property_descriptor desc[] =
    {
        {"loadRom", NULL, LoadRom, NULL, NULL, NULL, napi_default, NULL},
        {"runFrame", NULL, RunFrame, NULL, NULL, NULL, napi_default, NULL},
        {"setKey", NULL, SetKey, NULL, NULL, NULL, napi_default, NULL},
        {"saveState", NULL, SaveState, NULL, NULL, NULL, napi_default, NULL},
        {"loadState", NULL, LoadState, NULL, NULL, NULL, napi_default, NULL},
        {"reset", NULL, Reset, NULL, NULL, NULL, napi_default, NULL},
        {"setSaveDir", NULL, SetSaveDir, NULL, NULL, NULL, napi_default, NULL},
        {"isRomLoaded", NULL, IsRomLoaded, NULL, NULL, NULL, napi_default, NULL},
        {"getFramePixels", NULL, GetFramePixels, NULL, NULL, NULL, napi_default, NULL},
        {"getAudioSamples", NULL, GetAudioSamples, NULL, NULL, NULL, napi_default, NULL},
        {"saveRam", NULL, SaveRamNapi, NULL, NULL, NULL, napi_default, NULL},
        {"loadRam", NULL, LoadRamNapi, NULL, NULL, NULL, napi_default, NULL},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

    InitCore();

    // Hook the XComponent that declares libraryname: 'gearboy'
    napi_value export_instance = NULL;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &export_instance) != napi_ok ||
        export_instance == NULL)
    {
        OH_LOG_Print(LOG_APP, LOG_WARN, GB_LOG_DOMAIN, GB_LOG_TAG, "No native XComponent object yet");
        return exports;
    }

    OH_NativeXComponent* native_xcomponent = NULL;
    if (napi_unwrap(env, export_instance, reinterpret_cast<void**>(&native_xcomponent)) != napi_ok ||
        native_xcomponent == NULL)
    {
        return exports;
    }

    char id[OH_XCOMPONENT_ID_LEN_MAX + 1] = {0};
    uint64_t id_size = OH_XCOMPONENT_ID_LEN_MAX + 1;
    if (OH_NativeXComponent_GetXComponentId(native_xcomponent, id, &id_size)
        == OH_NATIVEXCOMPONENT_RESULT_SUCCESS)
    {
        OH_LOG_Print(LOG_APP, LOG_INFO, GB_LOG_DOMAIN, GB_LOG_TAG, "XComponent id: %{public}s", id);
    }

    OH_NativeXComponent_RegisterCallback(native_xcomponent, &g_xcomponent_callback);
    return exports;
}

napi_module g_gearboy_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = NULL,
    .nm_register_func = Init,
    .nm_modname = "gearboy",
    .nm_priv = NULL,
    .reserved = {0},
};

} // namespace

extern "C" __attribute__((constructor)) void RegisterGearboyModule(void)
{
    napi_module_register(&g_gearboy_module);
}
