import { router } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { GameItem, loadGames, addGame, touchGame, removeGame, getBool, SET_GUIDE, fmtLast } from '../common/Lib';

const ROM_DIR = '/roms';
const LEGACY_ROM = '/last_rom.gb';

// 首页：游戏库
@Entry
@Component
struct Index {
  @State games: GameItem[] = [];
  @State importing: boolean = false;
  @State statusText: string = '';
  private palette: string[] = ['#8BC34A', '#4FC3F7', '#FFB74D', '#BA68C8', '#F06292', '#4DB6AC'];

  aboutToAppear(): void {
    this.migrateLegacy();
    this.refresh();
    if (!getBool(getContext(this), SET_GUIDE, false)) {
      router.pushUrl({ url: 'pages/Guide' });
    }
  }

  onPageShow(): void {
    this.refresh();
  }

  private migrateLegacy(): void {
    const ctx = getContext(this);
    if (loadGames(ctx).length > 0) {
      return;
    }
    const legacy = ctx.filesDir + LEGACY_ROM;
    try {
      if (fs.accessSync(legacy)) {
        addGame(ctx, '上次导入的游戏', legacy);
      }
    } catch (err) {
    }
  }

  private refresh(): void {
    this.games = loadGames(getContext(this));
  }

  private sorted(): GameItem[] {
    const arr: GameItem[] = [];
    for (let i = 0; i < this.games.length; i++) {
      arr.push(this.games[i]);
    }
    arr.sort((a: GameItem, b: GameItem): number => {
      return b.last - a.last;
    });
    return arr;
  }

  private colorOf(id: string): string {
    let h = 0;
    for (let i = 0; i < id.length; i++) {
      h = (h * 31 + id.charCodeAt(i)) % 997;
    }
    return this.palette[h % this.palette.length];
  }

  private playGame(g: GameItem): void {
    touchGame(getContext(this), g.id);
    const clean = g.name.replace(/\.(gb|gbc)$/i, '');
    router.pushUrl({ url: 'pages/Play', params: { file: g.file, name: clean, id: g.id } });
  }

  private confirmRemove(g: GameItem): void {
    AlertDialog.show({
      title: '删除游戏',
      message: `将从游戏库移除「${g.name}」，游戏文件与存档不受影响。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#F0625A',
        action: (): void => {
          this.games = removeGame(getContext(this), g.id);
          this.statusText = '已从游戏库移除';
        }
      }
    });
  }

  private async importRom(): Promise<void> {
    if (this.importing) {
      return;
    }
    this.importing = true;
    this.statusText = '正在选择文件…';
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 1;
      opt.fileSuffixFilters = ['.gb', '.gbc'];
      const uris: Array<string> = await docPicker.select(opt);
      if (uris.length < 1) {
        this.statusText = '';
        this.importing = false;
        return;
      }
      this.statusText = '正在导入…';
      const ctx = getContext(this);
      const dir = ctx.filesDir + ROM_DIR;
      try {
        fs.mkdirSync(dir, true);
      } catch (err) {
      }
      let disp = '新游戏';
      try {
        const tail = uris[0].substring(uris[0].lastIndexOf('/') + 1);
        const dec = decodeURIComponent(tail);
        if (dec.length > 0) {
          disp = dec;
        }
      } catch (err) {
      }
      const src = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      const fname = `${Date.now()}.gb`;
      const dstPath = `${dir}/${fname}`;
      fs.copyFileSync(src.fd, dstPath);
      fs.closeSync(src);
      const item: GameItem = addGame(ctx, disp, dstPath);
      this.refresh();
      this.statusText = '';
      this.importing = false;
      this.playGame(item);
    } catch (err) {
      const e = err as BusinessError;
      this.statusText = `导入失败: ${e.code}`;
      this.importing = false;
    }
  }

  @Builder
  cover(g: GameItem, size: number) {
    Text(g.name.substring(0, 1).toUpperCase())
      .width(size)
      .height(size)
      .borderRadius(10)
      .backgroundColor(this.colorOf(g.id))
      .fontColor('#162016')
      .fontSize(Math.round(size * 0.42))
      .fontWeight(FontWeight.Bold)
      .textAlign(TextAlign.Center)
  }

  build() {
    Column() {
      // ---------- 顶栏 ----------
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('Gearboy')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#8BC34A')
          Text('Game Boy · Game Boy Color 模拟器')
            .fontSize(12)
            .fontColor('#7A857A')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('？')
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor('#232723')
          .fontColor('#8BC34A')
          .fontSize(18)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.pushUrl({ url: 'pages/Guide' });
          })
        Text('⚙')
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor('#232723')
          .fontColor('#E8F0E0')
          .fontSize(17)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 10 })

      if (this.games.length === 0) {
        // ---------- 空状态 ----------
        Column({ space: 14 }) {
          Text('🎮').fontSize(72).opacity(0.85)
          Text('还没有游戏')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#E8F0E0')
          Text('导入一个 .gb 或 .gbc 文件\n开始你的第一局游戏')
            .fontSize(14)
            .fontColor('#7A857A')
            .textAlign(TextAlign.Center)
            .lineHeight(22)
          Button(this.importing ? '处理中…' : '导入游戏')
            .width('46%')
            .height(46)
            .fontSize(17)
            .backgroundColor('#8BC34A')
            .fontColor('#162016')
            .margin({ top: 10 })
            .onClick(() => {
              this.importRom();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // ---------- 游戏列表（最近游玩排最前） ----------
        List({ space: 10 }) {
          ForEach(this.sorted(), (g: GameItem) => {
            ListItem() {
              Row({ space: 14 }) {
                this.cover(g, 52)
                Column({ space: 4 }) {
                  Text(g.name)
                    .fontSize(16)
                    .fontColor('#E8F0E0')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(fmtLast(g.last))
                    .fontSize(12)
                    .fontColor('#7A857A')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text('删除')
                  .fontSize(13)
                  .fontColor('#F0625A')
                  .padding(8)
                  .onClick(() => {
                    this.confirmRemove(g);
                  })
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor('#232723')
              .onClick(() => {
                this.playGame(g);
              })
            }
          }, (g: GameItem) => g.id)
        }
        .width('86%')
        .layoutWeight(1)
        .margin({ top: 6 })
        .scrollBar(BarState.Off)
      }

      if (this.games.length > 0) {
        Button(this.importing ? '处理中…' : '导入游戏 (.gb / .gbc)')
          .width('86%')
          .height(48)
          .fontSize(17)
          .backgroundColor('#8BC34A')
          .fontColor('#162016')
          .margin({ top: 6, bottom: 24 })
          .onClick(() => {
            this.importRom();
          })
      }
      if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(12)
          .fontColor('#7A857A')
          .padding({ bottom: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#141614')
  }
}
