import { router } from '@kit.ArkUI';
import { getBool, setBool, getNum, setNum, SET_GUIDE, SET_PAD, SET_SHARP, SET_FF } from '../common/Lib';

// 设置页：引导 / 显示 / 游戏 / 关于
@Entry
@Component
struct Settings {
  @State padOn: boolean = true;
  @State sharp: boolean = false;
  @State ff: number = 1;

  aboutToAppear(): void {
    const ctx = getContext(this);
    this.padOn = getBool(ctx, SET_PAD, true);
    this.sharp = getBool(ctx, SET_SHARP, false);
    this.ff = getNum(ctx, SET_FF, 1);
  }

  @Builder
  groupLabel(t: string) {
    Text(t)
      .fontSize(13)
      .fontColor('#7A857A')
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
          .fontColor('#E8F0E0')
        if (sub.length > 0) {
          Text(sub)
            .fontSize(12)
            .fontColor('#7A857A')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor('#8BC34A')
        .onChange((v: boolean) => {
          change(v);
        })
    }
    .width('86%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor('#232723')
  }

  @Builder
  rowLink(title: string, trailing: string, action: () => void) {
    Row({ space: 12 }) {
      Text(title)
        .fontSize(16)
        .fontColor('#E8F0E0')
        .layoutWeight(1)
      Text(trailing)
        .fontSize(13)
        .fontColor('#7A857A')
      Text('›')
        .fontSize(18)
        .fontColor('#7A857A')
    }
    .width('86%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor('#232723')
    .onClick(() => {
      action();
    })
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        Text('‹')
          .fontSize(28)
          .fontColor('#8BC34A')
          .padding({ left: 14, right: 6 })
          .onClick(() => {
            router.back();
          })
        Text('设置')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#E8F0E0')
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
              .fontColor('#E8F0E0')
              .layoutWeight(1)
            ForEach([1, 2, 4], (n: number) => {
              Button(`${n}×`)
                .width(48)
                .height(32)
                .fontSize(14)
                .backgroundColor(this.ff === n ? '#8BC34A' : '#2B2F2B')
                .fontColor(this.ff === n ? '#162016' : '#E8F0E0')
                .onClick(() => {
                  this.ff = n;
                  setNum(getContext(this), SET_FF, n);
                })
            }, (n: number) => n.toString())
          }
          .width('86%')
          .padding(14)
          .borderRadius(12)
          .backgroundColor('#232723')

          this.groupLabel('关于')
          Column({ space: 8 }) {
            Text('Gearboy 鸿蒙 PC 版')
              .fontSize(16)
              .fontColor('#E8F0E0')
            Text('版本 1.0.0')
              .fontSize(13)
              .fontColor('#7A857A')
            Text('基于开源项目 Gearboy（GPL-3.0）适配\n仅用于学习交流，请在合法途径获取游戏文件')
              .fontSize(12)
              .fontColor('#7A857A')
              .textAlign(TextAlign.Center)
              .lineHeight(20)
          }
          .width('86%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor('#232723')
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
    .backgroundColor('#141614')
  }
}
