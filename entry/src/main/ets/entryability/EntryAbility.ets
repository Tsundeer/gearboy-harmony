import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'Gearboy', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'Gearboy', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'Gearboy', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'Gearboy', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'Gearboy', 'Succeeded in loading the content.');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'Gearboy', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'Gearboy', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'Gearboy', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'Gearboy', '%{public}s', 'Ability onBackground');
  }
}
