# Gearboy for HarmonyOS（鸿蒙 PC 移植槽位 E1）

把 [Gearboy](https://github.com/drhelius/Gearboy)（Nintendo Game Boy / Game Boy Color 模拟器，
(C) 2012 Ignacio Sanchez）的核心移植为鸿蒙原生（ArkTS stage + Native C++）应用，
面向 HarmonyOS PC（2in1 与手机同应用模型）。

- 渲染：XComponent（type=surface + libraryname）→ NativeWindow **纯软件渲染**，
  核心 160x144 RGB565 帧缓冲最近邻缩放为 RGBA8888 写入窗口缓冲，每帧回调刷一次。
- 声音：**一期静音**（核心 `SetSoundMute(true)`，音频样点直接丢弃）。
  OHAudio 原生播放属二期工作，如实标注。
- 平台无关核心零第三方依赖、C++11；仅附带单文件 miniz（zip ROM 容器支持，随核心一起编译）。

## 操作说明

1. 启动应用进入 Index 页，点击「导入 ROM (.gb / .gbc)」，在 documentViewPicker 中选择
   ROM 文件；文件会被拷贝到应用沙箱（`files/last_rom.gb`）并自动进入 Play 页。
2. Play 页：屏幕（XComponent）+ 底部虚拟按键：
   - 左侧十字键：UP / DOWN / LEFT / RIGHT
   - 右侧：A、B 圆钮；SELECT、START 胶囊钮
   - 顶部菜单：重置 / 写存档 / 读存档 / 退回；存档槽位 1–3 可选
3. PC 键盘同样可用（Play 页获得焦点后）：方向键 = 十字键，
   X = A，Z = B，Enter = START，左/右 Shift = SELECT。
4. 存档写入沙箱 `files/<rom名>.slot<N>.state`（核心原生 SaveState/LoadState 序列化）。

## 架构

```
ArkTS 壳 (entry/src/main/ets)
  pages/Index.ets   documentViewPicker 导入 .gb/.gbc → 沙箱 → 路由进 Play
  pages/Play.ets    XComponent 屏幕 + 16ms 定时回调 runFrame()
                    虚拟按键 onTouch → setKey(key,pressed)
                    键盘 onKeyEvent → setKey；菜单（重置/存读档/退回）
        │ import emu from 'libgearboy.so'
        ▼
NAPI 薄壳 (entry/src/main/cpp/napi/emu_napi.cpp)
  loadRom(bytes, name?)   ArrayBuffer → LoadROMFromBuffer
  runFrame()              RunToVBlank 一帧 → 帧缓冲 → NativeWindow 软渲染
  setKey(key, pressed)    KeyPressed/KeyReleased（UP/DOWN/LEFT/RIGHT/A/B/SELECT/START）
  saveState(slot)/loadState(slot)  核心序列化 ↔ 沙箱文件
  reset()                 ResetROM
  setSaveDir(dir) / isRomLoaded()
  XComponent 生命周期回调（OnSurfaceCreated/Changed/Destroyed）持有 NativeWindow
        │ 直接调用 C++ 类
        ▼
vendor 核心 (entry/src/main/cpp/vendor/gearboy/)
  GearboyCore 门面：Init(GB_PIXEL_RGB565)/LoadROMFromBuffer/RunToVBlank/
  KeyPressed/KeyReleased/SaveState/LoadState/ResetROM
  全部 src/*.cpp + src/audio/*.cpp + miniz.c（见 CMakeLists.txt）
  核心边界：核心不含任何平台代码；平台相关（窗口/输入/文件/声音）全部在 napi 壳与 ArkTS。
```

- 键位编码（setKey）：0=UP 1=DOWN 2=LEFT 3=RIGHT 4=A 5=B 6=SELECT 7=START。
- 接口声明见 `entry/src/main/cpp/types/libgearboy/index.d.ts`。

## 构建方法

依赖：DevEco Studio（内置 ohos clang 工具链 + hvigorw + ohpm），本地 SDK `C:/OHSDK`（26.0.0）。

```sh
cd /e/HarmonyApps/gearboy-harmony
ohpm install
hvigorw assembleHap --mode module -p product=default --no-daemon
# 产物: entry/build/default/outputs/default/entry-default-unsigned.hap
```

首次克隆如缺 `local.properties`，可执行
`sh /e/OhProject/tools/init_ohos_config.sh <本工程目录>` 补齐 sdk.dir 等配置
（工程已按 8 处配置对齐：compileSdkVersion/compatibleSdkVersion/targetSdkVersion
26.0.0、runtimeOS OpenHarmony、modelVersion 6.0.0、deviceTypes default、syscap.json）。

## 已知限制（如实标注）

- **声音静音**：一期未接入 OHAudio，游戏无声；核心侧 `SetSoundMute(true)`。
- 运行时玩 ROM 属真机/模拟器运行事项，本仓验证到「核心真实编入 + HAP 构建成功」级别。
- 手柄震动、联机线缆（link cable）、金手指、SGB 模式等核心能力未在壳中暴露。
- 电池档 RAM（.sav）持久化未实现（仅即时存档槽位）。
- 构建期警告主要来自 vendor 原始源码（miniz pragma 等），不影响产物。

## License

- 本工程 ArkTS 壳与 NAPI 薄壳：MIT。
- `entry/src/main/cpp/vendor/gearboy/` 内的 Gearboy 核心保留上游原始
  **GPL-3.0-or-later** LICENSE 文件（上游仓库当前以 GPLv3+ 发布；移植规格表中
  标注的 MIT 与上游实际 LICENSE 不符，此处以上游 LICENSE 文件为准）。
- `vendor/gearboy/miniz.{c,h}`：单文件 miniz（公共领域/MIT 类许可，保留文件头声明）。
