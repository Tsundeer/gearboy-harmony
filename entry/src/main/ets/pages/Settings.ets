import { router } from '@kit.ArkUI';
import { getBool, setBool, getNum, setNum, SET_GUIDE, SET_PAD, SET_SHARP, SET_FF, SET_SOUND } from '../common/Lib';

// 设置页：引导 / 显示 / 声音 / 游戏 / 关于
@Entry
@Component
struct Settings {
  @State padOn: boolean = true;
  @State sharp: boolean = false;
  @State ff: number = 1;
  @State soundOn: boolean = true;

  aboutToAppear(): void {
    const ctx = getContext(this);
    this.padOn = getBool(ctx, SET_PAD, true);
    this.sharp = getBool(ctx, SET_SHARP, false);
    this.ff = getNum(ctx, SET_FF, 1);
    this.soundOn = getBool(ctx, SET_SOUND, true);
  }

  @Builder
  groupLabel(t: string) {
    Text(t)
      .fontSize(13)
      .fontColor($r('app.color.gb_sub'))
      .width('86%')
      .textAlign(TextAlign.Start)
      .margin({ top: 18, bottom: 6 })
  }

  @Builder
  rowToggle(title: string, sub: string, on: boolean, change: (v: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.gb_text'))
        if (sub.length > 0) {
          Text(sub)
            .fontSize(12)
            .fontColor($r('app.color.gb_sub'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor($r('app.color.gb_accent'))
        .onChange((v: boolean) => {
          change(v);
        })
    }
    .width('86%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.gb_card'))
  }

  @Builder
  rowLink(title: string, trailing: string, action: () => void) {
    Row({ space: 12 }) {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.gb_text'))
        .layoutWeight(1)
      Text(trailing)
        .fontSize(13)
        .fontColor($r('app.color.gb_sub'))
      Text('›')
        .fontSize(18)
        .fontColor($r('app.color.gb_sub'))
    }
    .width('86%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.gb_card'))
    .onClick(() => {
      action();
    })
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        Text('‹')
          .fontSize(28)
          .fontColor($r('app.color.gb_accent'))
          .padding({ left: 14, right: 6 })
          .onClick(() => {
            router.back();
          })
        Text('设置')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.gb_text'))
        Blank()
      }
      .width('100%')
      .padding({ top: 12, bottom: 4 })

      Scroll() {
        Column() {
          this.groupLabel('引导')
          this.rowLink('重新查看新手引导', '三步上手', (): void => {
            router.pushUrl({ url: 'pages/Guide' });
          })

          this.groupLabel('显示')
          this.rowToggle('显示虚拟手柄', '隐藏后使用键盘游玩', this.padOn, (v: boolean): void => {
            this.padOn = v;
            setBool(getContext(this), SET_PAD, v);
          })
          this.rowToggle('像素完美显示', '关闭后画面边缘更平滑', this.sharp, (v: boolean): void => {
            this.sharp = v;
            setBool(getContext(this), SET_SHARP, v);
          })

          this.groupLabel('游戏')
          Row({ space: 12 }) {
            Text('快进倍速')
              .fontSize(16)
              .fontColor($r('app.color.gb_text'))
              .layoutWeight(1)
            ForEach([1, 2, 4], (n: number) => {
              Button(`${n}×`)
                .width(48)
                .height(32)
                .fontSize(14)
                .backgroundColor(this.ff === n ? $r('app.color.gb_accent') : $r('app.color.gb_chip'))
                .fontColor(this.ff === n ? $r('app.color.gb_on_accent') : $r('app.color.gb_text'))
                .onClick(() => {
                  this.ff = n;
                  setNum(getContext(this), SET_FF, n);
                })
            }, (n: number) => n.toString())
          }
          .width('86%')
          .padding(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.gb_card'))

          this.groupLabel('声音')
          this.rowToggle('游戏音效', '还原真机扬声器体验', this.soundOn, (v: boolean): void => {
            this.soundOn = v;
            setBool(getContext(this), SET_SOUND, v);
          })

          this.groupLabel('关于')
          Column({ space: 8 }) {
            Text('Gearboy 鸿蒙 PC 版')
              .fontSize(16)
              .fontColor($r('app.color.gb_text'))
            Text('版本 1.0.0')
              .fontSize(13)
              .fontColor($r('app.color.gb_sub'))
            Text('基于开源项目 Gearboy（GPL-3.0）适配\n仅用于学习交流，请在合法途径获取游戏文件')
              .fontSize(12)
              .fontColor($r('app.color.gb_sub'))
              .textAlign(TextAlign.Center)
              .lineHeight(20)
          }
          .width('86%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor($r('app.color.gb_card'))
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .padding({ bottom: 30 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.gb_bg'))
  }
}
