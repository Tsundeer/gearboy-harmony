import { router } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

const LAST_ROM_PATH = '/last_rom.gb';

@Entry
@Component
struct Index {
  @State statusText: string = '将 .gb / .gbc ROM 拷入沙箱后开始游戏';
  @State hasLastRom: boolean = false;
  @State importing: boolean = false;
  private lastRomPath: string = '';

  aboutToAppear(): void {
    this.lastRomPath = getContext(this).filesDir + LAST_ROM_PATH;
    this.refreshLastRom();
  }

  private refreshLastRom(): void {
    try {
      this.hasLastRom = fs.accessSync(this.lastRomPath);
    } catch (err) {
      this.hasLastRom = false;
    }
  }

  private async importRom(): Promise<void> {
    if (this.importing) {
      return;
    }
    this.importing = true;
    this.statusText = '正在选择 ROM...';
    try {
      const docPicker = new picker.DocumentViewPicker();
      const selectOptions = new picker.DocumentSelectOptions();
      selectOptions.maxSelectNumber = 1;
      selectOptions.fileSuffixFilters = ['.gb', '.gbc'];
      const uris: Array<string> = await docPicker.select(selectOptions);
      if (uris.length < 1) {
        this.statusText = '未选择文件';
        this.importing = false;
        return;
      }
      const srcUri: string = uris[0];
      this.statusText = '正在拷入沙箱...';
      const srcFile = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(srcFile.fd, this.lastRomPath);
      fs.closeSync(srcFile);
      this.refreshLastRom();
      this.statusText = '导入成功，启动游戏...';
      router.pushUrl({ url: 'pages/Play' });
    } catch (err) {
      const e = err as BusinessError;
      this.statusText = `导入失败: ${e.code} ${e.message}`;
    }
    this.importing = false;
  }

  private startLastRom(): void {
    router.pushUrl({ url: 'pages/Play' });
  }

  build() {
    Column({ space: 24 }) {
      Text('Gearboy')
        .fontSize(42)
        .fontWeight(FontWeight.Bold)
        .fontColor('#8BC34A')
      Text('Game Boy / Game Boy Color 模拟器')
        .fontSize(16)
        .fontColor('#E8F0E0')
        .opacity(0.8)

      Column() {
        Text('屏幕 160x144')
          .fontSize(12)
          .fontColor('#E8F0E0')
          .opacity(0.4)
        Text('▲')
          .fontSize(72)
          .fontColor('#8BC34A')
          .opacity(0.6)
        Text('No ROM loaded')
          .fontSize(14)
          .fontColor('#E8F0E0')
          .opacity(0.5)
      }
      .width('80%')
      .height('32%')
      .justifyContent(FlexAlign.Center)
      .borderRadius(12)
      .backgroundColor('#2B2F2B')

      Button(this.importing ? '处理中...' : '导入 ROM (.gb / .gbc)')
        .width('60%')
        .height(48)
        .fontSize(18)
        .backgroundColor('#8BC34A')
        .fontColor('#1A1C1A')
        .enabled(!this.importing)
        .onClick(() => {
          this.importRom();
        })

      if (this.hasLastRom) {
        Button('继续上次游戏')
          .width('60%')
          .height(48)
          .fontSize(18)
          .backgroundColor('#2B2F2B')
          .fontColor('#E8F0E0')
          .onClick(() => {
            this.startLastRom();
          })
      }

      Text(this.statusText)
        .fontSize(13)
        .fontColor('#E8F0E0')
        .opacity(0.6)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#1A1C1A')
  }
}
