import emu from 'libgearboy.so';
import { fileIo as fs } from '@kit.CoreFileKit';
import { router } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { KeyCode } from '@kit.InputKit';
import { getBool, getNum, setNum, touchGame, SET_PAD, SET_SHARP, SET_FF } from '../common/Lib';

// Virtual key order understood by the native setKey()
const KEY_UP = 0;
const KEY_DOWN = 1;
const KEY_LEFT = 2;
const KEY_RIGHT = 3;
const KEY_A = 4;
const KEY_B = 5;
const KEY_SELECT = 6;
const KEY_START = 7;

const GB_W = 160;
const GB_H = 144;
const GB_FRAME_MS = 1000 / 59.7275;
const FRAME_TICK_MS = 8;
const ROM_PATH_SUFFIX = '/last_rom.gb';
const SLOTS: number[] = [1, 2, 3];

interface RouteParams {
  file?: string;
  name?: string;
  id?: string;
}

@Entry
@Component
struct Play {
  @State romLoaded: boolean = false;
  @State statusText: string = '';
  @State showMenu: boolean = true;
  @State slot: number = 1;
  @State ff: number = 1;
  @State padVisible: boolean = true;
  @State sharp: boolean = false;
  private timerId: number = -1;
  private lastTime: number = 0;
  private gameId: string = '';
  private romFile: string = '';
  private romName: string = 'rom';
  // RGBA8888 160x144 pixel map refreshed by the native core each frame
  private screenPm: image.PixelMap | null = null;
  private renderSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderSettings);

  aboutToAppear(): void {
    const ctx = getContext(this);
    const p = router.getParams() as RouteParams;
    if (p !== null && p !== undefined) {
      if (p.file !== undefined && p.file.length > 0) {
        this.romFile = p.file;
      }
      if (p.name !== undefined && p.name.length > 0) {
        this.romName = p.name;
      }
      if (p.id !== undefined) {
        this.gameId = p.id;
      }
    }
    if (this.romFile.length === 0) {
      this.romFile = ctx.filesDir + ROM_PATH_SUFFIX;
    }
    this.ff = getNum(ctx, SET_FF, 1);
    this.padVisible = getBool(ctx, SET_PAD, true);
    this.sharp = getBool(ctx, SET_SHARP, false);
    emu.setSaveDir(ctx.filesDir);
    this.createScreenPm();
    this.doLoadRom();
  }

  onPageShow(): void {
    // 从设置页返回时重新应用显示偏好
    const ctx = getContext(this);
    this.ff = getNum(ctx, SET_FF, 1);
    this.padVisible = getBool(ctx, SET_PAD, true);
    this.sharp = getBool(ctx, SET_SHARP, false);
    this.ctx.imageSmoothingEnabled = !this.sharp;
  }

  aboutToDisappear(): void {
    this.stopLoop();
    touchGame(getContext(this), this.gameId);
  }

  private createScreenPm(): void {
    const opts: image.InitializationOptions = {
      size: { width: GB_W, height: GB_H },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888
    };
    const blank = new ArrayBuffer(GB_W * GB_H * 4);
    image.createPixelMap(blank, opts).then((pm: image.PixelMap) => {
      this.screenPm = pm;
    }).catch((err: BusinessError) => {
      this.statusText = `PixelMap 创建失败: ${err.code}`;
    });
  }

  private doLoadRom(): void {
    try {
      if (!fs.accessSync(this.romFile)) {
        this.statusText = '未找到游戏文件，请返回首页重新导入';
        return;
      }
      const f = fs.openSync(this.romFile, fs.OpenMode.READ_ONLY);
      const st = fs.statSync(f.fd);
      const ab = new ArrayBuffer(st.size);
      fs.readSync(f.fd, ab);
      fs.closeSync(f);
      const ok: boolean = emu.loadRom(ab, this.romName);
      this.romLoaded = ok;
      this.statusText = ok ? `${this.romName} · 已就绪` : '游戏加载失败（核心拒绝）';
    } catch (err) {
      const e = err as BusinessError;
      this.statusText = `游戏文件读取失败: ${e.code}`;
    }
  }

  private startLoop(): void {
    if (this.timerId >= 0) {
      return;
    }
    this.lastTime = 0;
    this.timerId = setInterval(() => {
      this.tick();
    }, FRAME_TICK_MS);
  }

  private stopLoop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private tick(): void {
    // 时间戳追赶：定时器被系统节流时一次性补跑帧，保证游戏速度与真实时间一致
    const now = Date.now();
    if (this.lastTime === 0) {
      this.lastTime = now;
    }
    let frames = Math.floor((now - this.lastTime) / GB_FRAME_MS);
    if (frames < 1) {
      return;
    }
    const cap = 2 + this.ff * 2;
    if (frames > cap) {
      frames = cap;
    }
    this.lastTime += frames * GB_FRAME_MS;
    if (this.lastTime < now - 300) {
      this.lastTime = now;
    }
    for (let i = 0; i < frames; i++) {
      emu.runFrame();
    }
    const pm = this.screenPm;
    if (pm !== null) {
      const ab: ArrayBuffer = emu.getFramePixels();
      pm.writeBufferToPixelsSync(ab);
      this.ctx.drawImage(pm, 0, 0, this.ctx.width, this.ctx.height);
    }
  }

  private cycleFf(): void {
    this.ff = this.ff === 1 ? 2 : (this.ff === 2 ? 4 : 1);
    setNum(getContext(this), SET_FF, this.ff);
    this.statusText = this.ff === 1 ? '常速运行' : `快进 ${this.ff}×`;
  }

  private doReset(): void {
    if (emu.reset()) {
      this.statusText = '已重置';
    }
  }

  private doSaveState(): void {
    const ok: boolean = emu.saveState(this.slot);
    this.statusText = ok ? `已写入存档槽 ${this.slot}` : `存档槽 ${this.slot} 写入失败`;
  }

  private doLoadState(): void {
    const ok: boolean = emu.loadState(this.slot);
    this.statusText = ok ? `已读取存档槽 ${this.slot}` : `存档槽 ${this.slot} 为空`;
  }

  private goBack(): void {
    this.stopLoop();
    router.back();
  }

  private mapKeyCode(code: number): number {
    switch (code) {
      case KeyCode.KEYCODE_DPAD_UP:
        return KEY_UP;
      case KeyCode.KEYCODE_DPAD_DOWN:
        return KEY_DOWN;
      case KeyCode.KEYCODE_DPAD_LEFT:
        return KEY_LEFT;
      case KeyCode.KEYCODE_DPAD_RIGHT:
        return KEY_RIGHT;
      case KeyCode.KEYCODE_X:
        return KEY_A;
      case KeyCode.KEYCODE_Z:
        return KEY_B;
      case KeyCode.KEYCODE_ENTER:
        return KEY_START;
      case KeyCode.KEYCODE_SHIFT_RIGHT:
        return KEY_SELECT;
      default:
        return -1;
    }
  }

  private handleKeyEvent(event: KeyEvent): void {
    const key = this.mapKeyCode(event.keyCode);
    if (key < 0) {
      return;
    }
    if (event.type === KeyType.Down) {
      emu.setKey(key, true);
    } else if (event.type === KeyType.Up) {
      emu.setKey(key, false);
    }
  }

  @Builder
  menuButton(label: string, action: () => void) {
    Button(label)
      .height(36)
      .padding({ left: 12, right: 12 })
      .fontSize(14)
      .backgroundColor('#2B2F2B')
      .fontColor('#E8F0E0')
      .onClick(() => {
        action();
      })
  }

  @Builder
  padButton(label: string, key: number) {
    Text(label)
      .width(56)
      .height(56)
      .borderRadius(10)
      .backgroundColor('#2B2F2B')
      .fontColor('#E8F0E0')
      .fontSize(20)
      .textAlign(TextAlign.Center)
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          emu.setKey(key, true);
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          emu.setKey(key, false);
        }
      })
  }

  @Builder
  actionButton(label: string, key: number, color: Resource) {
    Text(label)
      .width(62)
      .height(62)
      .borderRadius(31)
      .backgroundColor(color)
      .fontColor('#FFFFFF')
      .fontSize(22)
      .fontWeight(FontWeight.Bold)
      .textAlign(TextAlign.Center)
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          emu.setKey(key, true);
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          emu.setKey(key, false);
        }
      })
  }

  @Builder
  pillButton(label: string, key: number) {
    Text(label)
      .width(84)
      .height(30)
      .borderRadius(15)
      .backgroundColor('#2B2F2B')
      .fontColor('#E8F0E0')
      .fontSize(12)
      .textAlign(TextAlign.Center)
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          emu.setKey(key, true);
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          emu.setKey(key, false);
        }
      })
  }

  build() {
    Column() {
      // ---------- 顶部菜单栏 ----------
      Row({ space: 8 }) {
        this.menuButton(this.showMenu ? '收起' : '菜单', (): void => {
          this.showMenu = !this.showMenu;
        })
        if (this.showMenu) {
          this.menuButton(this.ff === 1 ? '快进' : `${this.ff}×`, (): void => {
            this.cycleFf();
          })
          this.menuButton('重置', (): void => {
            this.doReset();
          })
          this.menuButton('写存档', (): void => {
            this.doSaveState();
          })
          this.menuButton('读存档', (): void => {
            this.doLoadState();
          })
          ForEach(SLOTS, (s: number) => {
            Button(`${s}`)
              .height(36)
              .width(36)
              .fontSize(14)
              .backgroundColor(this.slot === s ? '#8BC34A' : '#2B2F2B')
              .fontColor(this.slot === s ? '#1A1C1A' : '#E8F0E0')
              .onClick(() => {
                this.slot = s;
              })
          }, (s: number) => s.toString())
          Blank()
          this.menuButton('退出', (): void => {
            this.goBack();
          })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 4 })

      if (this.showMenu && this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(13)
          .fontColor('#8BC34A')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(2)
      }

      // ---------- 游戏画面（Canvas，非 XComponent） ----------
      Column() {
        Canvas(this.ctx)
          .height('100%')
          .aspectRatio(GB_W / GB_H)
          .backgroundColor(Color.Black)
          .borderRadius(8)
          .border({ width: 1, color: '#3A3F3A' })
          .onReady(() => {
            this.ctx.imageSmoothingEnabled = !this.sharp;
            this.startLoop();
          })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 4, bottom: 8 })

      // ---------- 虚拟手柄 ----------
      if (this.padVisible) {
        Row() {
          Column({ space: 6 }) {
            Row() {
              Blank()
              this.padButton('▲', KEY_UP)
              Blank()
            }
            .width(186)
            Row({ space: 6 }) {
              this.padButton('◀', KEY_LEFT)
              Text('')
                .width(56)
                .height(56)
                .borderRadius(10)
                .backgroundColor('#1A1C1A')
              this.padButton('▶', KEY_RIGHT)
            }
            Row() {
              Blank()
              this.padButton('▼', KEY_DOWN)
              Blank()
            }
            .width(186)
          }

          Blank()

          Column({ space: 10 }) {
            Row({ space: 14 }) {
              this.actionButton('B', KEY_B, $r('app.color.gb_btn_b'))
              this.actionButton('A', KEY_A, $r('app.color.gb_btn_a'))
            }
            Row({ space: 14 }) {
              this.pillButton('SELECT', KEY_SELECT)
              this.pillButton('START', KEY_START)
            }
            .margin({ top: 8 })
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 18 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1C1A')
    .focusable(true)
    .focusOnTouch(true)
    .onKeyEvent((event: KeyEvent) => {
      this.handleKeyEvent(event);
    })
  }
}
