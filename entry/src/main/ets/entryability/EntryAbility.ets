import { UIAbility, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

export default class EntryAbility extends UIAbility {
  onConfigurationUpdate(configuration: Configuration): void {
    AppStorage.setOrCreate('dshSystemDark', configuration.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.onConfigurationUpdate(this.context.config);
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(0x0000, 'DSHGo', 'Failed to load the main page (%{public}d)', error.code);
      }
    });
  }
}
