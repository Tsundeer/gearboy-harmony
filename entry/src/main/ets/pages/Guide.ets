import { router } from '@kit.ArkUI';
import { setBool, SET_GUIDE } from '../common/Lib';

// 首次启动新手引导：三步卡片
@Entry
@Component
struct Guide {
  private finish(): void {
    setBool(getContext(this), SET_GUIDE, true);
    router.back();
  }

  @Builder
  slide(glyph: string, title: string, desc: string) {
    Column({ space: 18 }) {
      Text(glyph)
        .fontSize(64)
      Text(title)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E8F0E0')
      Text(desc)
        .fontSize(15)
        .fontColor('#B9C4B3')
        .textAlign(TextAlign.Center)
        .lineHeight(26)
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Blank()
        Text('跳过')
          .fontSize(14)
          .fontColor('#8BC34A')
          .padding(14)
          .onClick(() => {
            this.finish();
          })
      }
      .width('100%')

      Swiper() {
        this.slide('🎮', '欢迎使用 Gearboy', '在鸿蒙 PC 上重温\nGame Boy 与 Game Boy Color 的经典游戏')
        this.slide('📥', '两步开始游戏', '点击「导入游戏」，选择 .gb 或 .gbc 文件\n导入后自动开始，并保存到游戏库\n下次从游戏库一键进入')
        this.slide('🕹️', '操作方式', '虚拟手柄：方向键 ＋ A / B ＋ SELECT / START\n键盘：方向键移动，X ＝ A，Z ＝ B\n回车 ＝ START，右Shift ＝ SELECT')
      }
      .loop(false)
      .layoutWeight(1)

      Button('开始使用')
        .width('60%')
        .height(46)
        .fontSize(17)
        .backgroundColor('#8BC34A')
        .fontColor('#162016')
        .margin({ bottom: 40 })
        .onClick(() => {
          this.finish();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#141614')
  }
}
