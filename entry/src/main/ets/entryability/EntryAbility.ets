import { UIAbility, Configuration, ConfigurationConstant, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { appPageLink, launcherEntry } from '../ui/ShellNavigationData';
import { WireObject } from '../dsh/DshWire';
import { shareLaunch } from '../ui/ShareLaunchData';
import { forumAuthCallback } from '../forum/ForumCallback';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { backgroundCompletion } from '../ui/BackgroundCompletion';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void { this.receiveLaunch(want); }
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void { this.receiveLaunch(want); }

  private receiveLaunch(want: Want): void {
    const parameters = want.parameters;
    const page = parameters?.['dsh.page'] === 'companion' ? 'companion' : appPageLink(want.uri || '');
    const input: WireObject = { 'kind': parameters?.['dsh.kind'], 'text': parameters?.['dsh.text'],
      'sessionId': parameters?.['dsh.sessionId'], 'host': parameters?.['dsh.host'] };
    const entry = launcherEntry(input);
    const share = shareLaunch(want.uri || '', want.type || '');
    const forum = forumAuthCallback(want.uri || '');
    if (!page && !entry && !share && !forum) return;
    const request: WireObject = { 'page': page, 'entry': entry, 'share': share, 'forum': forum, 'nonce': Date.now() };
    AppStorage.setOrCreate('dshLaunchRequest', JSON.stringify(request));
  }

  onForeground(): void {
    backgroundCompletion.onForeground();
    AppStorage.setOrCreate('dshForeground', true);
  }

  onBackground(): void {
    backgroundCompletion.onBackground();
    AppStorage.setOrCreate('dshForeground', false);
  }

  onDestroy(): void { backgroundCompletion.destroy(); }

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
