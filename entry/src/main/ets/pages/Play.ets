import emu from 'libgearboy.so';
import { fileIo as fs } from '@kit.CoreFileKit';
import { router } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';

// Virtual key codes understood by the native setKey()
const KEY_UP = 0;
const KEY_DOWN = 1;
const KEY_LEFT = 2;
const KEY_RIGHT = 3;
const KEY_A = 4;
const KEY_B = 5;
const KEY_SELECT = 6;
const KEY_START = 7;
const FRAME_INTERVAL_MS = 16;

const ROM_PATH_SUFFIX = '/last_rom.gb';
const SLOTS: number[] = [1, 2, 3];

@Entry
@Component
struct Play {
  @State romLoaded: boolean = false;
  @State statusText: string = '';
  @State showMenu: boolean = true;
  @State slot: number = 1;
  private timerId: number = -1;

  aboutToAppear(): void {
    emu.setSaveDir(getContext(this).filesDir);
    this.loadRomFromSandbox();
  }

  aboutToDisappear(): void {
    this.stopLoop();
  }

  onBackPress(): boolean {
    this.stopLoop();
    return false; // let the system perform the default back navigation
  }

  private loadRomFromSandbox(): void {
    const romPath: string = getContext(this).filesDir + ROM_PATH_SUFFIX;
    try {
      const stat = fs.statSync(romPath);
      const file = fs.openSync(romPath, fs.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      this.romLoaded = emu.loadRom(buf, 'last_rom');
      this.statusText = this.romLoaded ? '' : 'ROM 加载失败（文件不是有效的 .gb/.gbc？）';
    } catch (err) {
      this.romLoaded = false;
      this.statusText = '读取沙箱 ROM 失败，请返回重新导入';
    }
  }

  private startLoop(): void {
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setInterval(() => {
      emu.runFrame();
    }, FRAME_INTERVAL_MS);
  }

  private stopLoop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  // Maps an ArkUI key event (PC keyboard) to a Game Boy key; -1 = unmapped.
  private mapKeyCode(keyCode: number): number {
    switch (keyCode) {
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
      case KeyCode.KEYCODE_SHIFT_LEFT:
      case KeyCode.KEYCODE_SHIFT_RIGHT:
        return KEY_SELECT;
      default:
        return -1;
    }
  }

  private handleKeyEvent(event: KeyEvent): void {
    if (!this.romLoaded) {
      return;
    }
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

  private doReset(): void {
    if (this.romLoaded && emu.reset()) {
      this.statusText = '已重置';
    } else {
      this.statusText = '重置失败';
    }
  }

  private doSaveState(): void {
    if (emu.saveState(this.slot)) {
      this.statusText = `已写入存档 槽位 ${this.slot}`;
    } else {
      this.statusText = `写存档失败（槽位 ${this.slot}）`;
    }
  }

  private doLoadState(): void {
    if (emu.loadState(this.slot)) {
      this.statusText = `已读取存档 槽位 ${this.slot}`;
    } else {
      this.statusText = `读存档失败：槽位 ${this.slot} 无存档`;
    }
  }

  private goBack(): void {
    this.stopLoop();
    router.back();
  }

  @Builder
  padButton(label: string, keyCode: number) {
    Text(label)
      .fontSize(22)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.gb_text'))
      .textAlign(TextAlign.Center)
      .width(56)
      .height(56)
      .borderRadius(10)
      .backgroundColor($r('app.color.gb_panel'))
      .onTouch((event: TouchEvent) => {
        if (!this.romLoaded) {
          return;
        }
        if (event.type === TouchType.Down) {
          emu.setKey(keyCode, true);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          emu.setKey(keyCode, false);
        }
      })
  }

  @Builder
  actionButton(label: string, keyCode: number, bgColor: ResourceColor) {
    Text(label)
      .fontSize(26)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.gb_text'))
      .textAlign(TextAlign.Center)
      .width(76)
      .height(76)
      .borderRadius(38)
      .backgroundColor(bgColor)
      .onTouch((event: TouchEvent) => {
        if (!this.romLoaded) {
          return;
        }
        if (event.type === TouchType.Down) {
          emu.setKey(keyCode, true);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          emu.setKey(keyCode, false);
        }
      })
  }

  @Builder
  pillButton(label: string, keyCode: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.gb_text'))
      .textAlign(TextAlign.Center)
      .width(84)
      .height(34)
      .borderRadius(17)
      .backgroundColor($r('app.color.gb_panel'))
      .onTouch((event: TouchEvent) => {
        if (!this.romLoaded) {
          return;
        }
        if (event.type === TouchType.Down) {
          emu.setKey(keyCode, true);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          emu.setKey(keyCode, false);
        }
      })
  }

  @Builder
  menuButton(label: string, onTap: () => void) {
    Button(label)
      .height(36)
      .fontSize(14)
      .backgroundColor($r('app.color.gb_panel'))
      .fontColor($r('app.color.gb_text'))
      .onClick(() => {
        onTap();
      })
  }

  build() {
    Column() {
      // ---------- top menu bar ----------
      Row({ space: 8 }) {
        this.menuButton(this.showMenu ? '收起' : '菜单', (): void => {
          this.showMenu = !this.showMenu;
        })
        if (this.showMenu) {
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
              .backgroundColor(this.slot === s ? $r('app.color.gb_accent') : $r('app.color.gb_panel'))
              .fontColor(this.slot === s ? $r('app.color.gb_dark') : $r('app.color.gb_text'))
              .onClick(() => {
                this.slot = s;
              })
          }, (s: number) => s.toString())
          Blank()
          this.menuButton('退回', (): void => {
            this.goBack();
          })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 4 })

      if (this.showMenu && this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(13)
          .fontColor($r('app.color.gb_accent'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(2)
      }

      // ---------- emulator screen ----------
      XComponent({ id: 'gearboyScreen', type: 'surface', libraryname: 'gearboy' })
        .width('96%')
        .aspectRatio(160 / 144)
        .backgroundColor(Color.Black)
        .onLoad(() => {
          this.startLoop();
        })
        .onDestroy(() => {
          this.stopLoop();
        })

      Blank()

      // ---------- virtual gamepad ----------
      Row() {
        // D-pad
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
              .backgroundColor($r('app.color.gb_dark'))
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

        // A / B
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
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.gb_dark'))
    .focusable(true)
    .focusOnTouch(true)
    .onKeyEvent((event: KeyEvent) => {
      this.handleKeyEvent(event);
    })
  }
}
