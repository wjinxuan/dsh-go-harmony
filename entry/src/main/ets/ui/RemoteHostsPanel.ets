import { common } from '@kit.AbilityKit';
import { DshGlyphs, ThemeColors, themeColors } from './DshTheme';
import {
  deleteRemoteHost, getRemoteHostConnection, listRemoteHosts, MAX_REMOTE_AUTHORIZATION,
  MAX_REMOTE_HOST_NAME, MAX_REMOTE_LAUNCH_URL, RemoteHost, RemoteHostConnection, RemoteHostDraft, RemoteHostError,
  remoteHostConnection, saveRemoteHost
} from '../remote/RemoteHosts';

@Component
export struct RemoteHostsPanel {
  @Prop colors: ThemeColors = themeColors();
  @Prop connected: boolean = false;
  @Prop currentId: string = '';
  @Prop currentName: string = '';
  @Prop connecting: boolean = false;
  @Prop errorText: string = '';
  onConnect: (connection: RemoteHostConnection) => Promise<boolean> = async () => false;
  onLocal: () => void = () => {};
  onClose: () => void = () => {};
  onBackHandler?: (handler: (() => boolean) | undefined) => void;

  @State private hosts: RemoteHost[] = [];
  @State private loaded: boolean = false;
  @State private loading: boolean = false;
  @State private busy: boolean = false;
  @State private editing: boolean = false;
  @State private profileId: string = '';
  @State private profileOrigin: string = '';
  @State private profileHasCredential: boolean = false;
  @State private hostName: string = '';
  @State private launchUrl: string = '';
  @State private authorization: string = '';
  @State private remember: boolean = false;
  @State private failure: string = '';
  private active: boolean = true;

  aboutToAppear(): void {
    this.active = true;
    this.onBackHandler?.(() => this.back());
    void this.reload();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.onBackHandler?.(undefined);
    this.launchUrl = '';
    this.authorization = '';
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async reload(): Promise<void> {
    if (this.loading) return;
    this.loading = true;
    this.failure = '';
    try {
      const hosts = await listRemoteHosts(this.context());
      if (this.active) {
        this.hosts = hosts;
        this.loaded = true;
      }
    } catch (error) {
      if (this.active) this.failure = error instanceof RemoteHostError ? error.message : '无法读取已保存的主机。';
    } finally {
      if (this.active) this.loading = false;
    }
  }

  private edit(host?: RemoteHost): void {
    this.failure = '';
    this.profileId = host?.id || '';
    this.profileOrigin = host?.origin || '';
    this.profileHasCredential = host?.hasCredential === true;
    this.hostName = host?.name || '';
    this.launchUrl = '';
    this.authorization = '';
    this.remember = this.profileHasCredential;
    this.editing = true;
  }

  private cancel(): void {
    this.launchUrl = '';
    this.authorization = '';
    this.failure = '';
    this.editing = false;
  }

  private blocked(): boolean {
    return this.busy || this.connecting;
  }

  private back(): boolean {
    if (this.blocked()) return true;
    if (!this.editing) return false;
    this.cancel();
    return true;
  }

  private draft(): RemoteHostDraft {
    return { id: this.profileId, name: this.hostName, launchUrl: this.launchUrl,
      authorization: this.authorization, remember: this.remember };
  }

  private replaceHost(host: RemoteHost): void {
    this.hosts = this.hosts.some((existing: RemoteHost) => existing.id === host.id) ?
      this.hosts.map((existing: RemoteHost) => existing.id === host.id ? host : existing) : this.hosts.concat(host);
  }

  private async connectTo(host: RemoteHost, connection?: RemoteHostConnection): Promise<boolean> {
    let target: RemoteHostConnection | undefined;
    try {
      target = connection || await getRemoteHostConnection(host);
    } catch (error) {
      if (this.active) this.failure = error instanceof RemoteHostError ? error.message : '无法读取已保存的主机凭据。';
      return false;
    }
    if (!this.active) return false;
    if (!target) {
      this.failure = '请重新输入这台主机的完整启动链接。';
      return false;
    }
    try {
      if (await this.onConnect(target)) return true;
    } catch {
      // The connection callback can fail before it updates the page status.
    }
    if (this.active && !this.errorText) this.failure = '无法连接这台主机。请检查启动链接、代理授权和主机状态。';
    return false;
  }

  private async select(host: RemoteHost): Promise<void> {
    if (this.blocked()) return;
    if (this.connected && this.currentId === host.id) {
      this.onClose();
      return;
    }
    this.edit(host);
    if (!host.hasCredential) return;
    this.busy = true;
    try {
      if (await this.connectTo(host) && this.active) this.cancel();
    } finally {
      if (this.active) this.busy = false;
    }
  }

  private async save(connect: boolean): Promise<void> {
    if (this.blocked()) return;
    this.failure = '';
    this.busy = true;
    const draft = this.draft();
    try {
      if (connect && !draft.launchUrl.trim() && !this.profileHasCredential) {
        this.failure = '请先输入完整的 DSH 启动链接。';
        return;
      }
      const host = await saveRemoteHost(this.context(), draft);
      if (!this.active) return;
      this.replaceHost(host);
      this.profileId = host.id;
      this.profileOrigin = host.origin;
      this.profileHasCredential = host.hasCredential;
      this.hostName = host.name;
      if (connect) {
        const connection = draft.launchUrl.trim() ? remoteHostConnection(host, draft.launchUrl, draft.authorization) : undefined;
        if (!await this.connectTo(host, connection)) return;
      }
      if (this.active) this.cancel();
    } catch (error) {
      if (this.active) {
        this.failure = error instanceof RemoteHostError ? error.message : '无法保存主机，请重试。';
        await this.reloadAfterFailure();
      }
    } finally {
      if (this.active) this.busy = false;
    }
  }

  private async reloadAfterFailure(): Promise<void> {
    try {
      const hosts = await listRemoteHosts(this.context());
      if (this.active) {
        this.hosts = hosts;
        this.profileHasCredential = hosts.find((host: RemoteHost) => host.id === this.profileId)?.hasCredential === true;
      }
    } catch {}
  }

  private confirmDelete(): void {
    if (this.blocked() || !this.profileId) return;
    const id = this.profileId;
    this.getUIContext().showAlertDialog({
      title: '删除这台主机？',
      message: '将删除手机上保存的主机资料和凭据。电脑上的 DSH、会话和当前连接会保留。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => { void this.remove(id); } }
    });
  }

  private async remove(id: string): Promise<void> {
    if (this.blocked()) return;
    this.busy = true;
    this.failure = '';
    try {
      await deleteRemoteHost(this.context(), id);
      if (!this.active) return;
      this.hosts = this.hosts.filter((host: RemoteHost) => host.id !== id);
      this.cancel();
    } catch (error) {
      if (this.active) {
        this.failure = error instanceof RemoteHostError ? error.message : '无法删除这台主机，请重试。';
        await this.reloadAfterFailure();
      }
    } finally {
      if (this.active) this.busy = false;
    }
  }

  @Builder
  private hostRow(host: RemoteHost) {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Text(DshGlyphs.host).fontFamily(DshGlyphs.family).fontSize(23).fontColor(this.colors.primary)
          Column({ space: 4 }) {
            Text(host.name).fontSize(16).fontColor(this.colors.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(host.origin).fontSize(13).fontColor(this.colors.muted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          if (this.connected && this.currentId === host.id) {
            Text('已连接').fontSize(13).fontColor(this.colors.success)
          } else {
            Text(host.hasCredential ? '已保存凭据' : '需输入链接').fontSize(12).fontColor(this.colors.hint)
          }
        }.width('100%').padding({ left: 12, right: 12 })
      }.height(66).backgroundColor(Color.Transparent).layoutWeight(1).enabled(!this.blocked())
        .onClick(() => { void this.select(host); })
      Button('编辑').fontSize(13).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
        .height(40).enabled(!this.blocked()).onClick(() => this.edit(host))
    }.width('100%').padding({ right: 8 }).borderRadius(14).backgroundColor(this.colors.surface)
  }

  @Builder
  private editor() {
    Column({ space: 10 }) {
      Text(this.profileId ? '编辑主机' : '添加主机').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.colors.text)
      if (this.profileOrigin) {
        Text(this.profileOrigin).fontSize(13).fontColor(this.colors.hint)
      }
      Text('名称').fontSize(13).fontColor(this.colors.muted)
      TextInput({ text: this.hostName, placeholder: '例如：家里的电脑' }).maxLength(MAX_REMOTE_HOST_NAME)
        .height(46).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).enabled(!this.blocked())
        .accessibilityText('主机名称').onChange((value: string) => { this.hostName = value; })
      Text('DSH 启动链接').fontSize(13).fontColor(this.colors.muted)
      TextInput({ text: this.launchUrl, placeholder: this.profileHasCredential ? '已保存，留空沿用' : '粘贴完整的 HTTPS 启动链接' })
        .type(InputType.Password).enableAutoFill(false).maxLength(MAX_REMOTE_LAUNCH_URL)
        .height(46).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).enabled(!this.blocked())
        .accessibilityText('DSH 启动链接').onChange((value: string) => { this.launchUrl = value; })
      Text('反向代理授权（可选）').fontSize(13).fontColor(this.colors.muted)
      TextInput({ text: this.authorization, placeholder: '反向代理要求时填写授权头的值' })
        .type(InputType.Password).enableAutoFill(false).maxLength(MAX_REMOTE_AUTHORIZATION)
        .height(46).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt).enabled(!this.blocked())
        .accessibilityText('反向代理授权').onChange((value: string) => { this.authorization = value; })
      Row({ space: 8 }) {
        Checkbox({ name: 'rememberRemoteHost' }).select(this.remember).selectedColor(this.colors.primary)
          .enabled(!this.blocked()).accessibilityText('安全保存连接凭据')
          .onChange((selected: boolean) => { this.remember = selected; })
        Text('安全保存连接凭据').fontSize(14).fontColor(this.colors.text)
      }.width('100%')
      Text(this.profileHasCredential ?
        '凭据保存在鸿蒙安全资产存储中。取消勾选并保存可移除已有凭据。' :
        '勾选后，启动链接和代理授权存入鸿蒙安全资产存储。')
        .fontSize(13).fontColor(this.colors.hint)
      Row({ space: 8 }) {
        Button('保存').fontSize(14).fontColor(this.colors.primary).backgroundColor(this.colors.surfaceAlt)
          .height(44).layoutWeight(1).enabled(!this.blocked() && (!!this.profileId || !!this.launchUrl.trim()))
          .onClick(() => { void this.save(false); })
        Button(this.blocked() ? '正在处理…' : '保存并连接').fontSize(14)
          .fontColor(this.colors.onPrimary).backgroundColor(this.colors.primary).height(44).layoutWeight(1)
          .enabled(!this.blocked() && (!!this.launchUrl.trim() || (this.profileHasCredential && this.remember)))
          .onClick(() => { void this.save(true); })
      }.width('100%')
      if (this.profileId) {
        Button('删除这台主机').fontSize(14).fontColor(this.colors.danger).backgroundColor(Color.Transparent)
          .height(42).enabled(!this.blocked()).onClick(() => this.confirmDelete())
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(16).backgroundColor(this.colors.surface)
  }

  @Builder
  private hostList() {
    if (this.connected && this.currentName) {
      Column({ space: 4 }) {
        Text('当前主机').fontSize(13).fontColor(this.colors.hint)
        Text(this.currentName).fontSize(17).fontColor(this.colors.text).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('已连接').fontSize(13).fontColor(this.colors.success)
      }.width('100%').alignItems(HorizontalAlign.Start).padding(14).borderRadius(14).backgroundColor(this.colors.surface)
    }
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Text(DshGlyphs.host).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.primary)
        Text('本机').fontSize(16).fontColor(this.colors.text).layoutWeight(1)
        if (this.connected && !this.currentId) {
          Text(DshGlyphs.check).fontFamily(DshGlyphs.family).fontSize(18).fontColor(this.colors.success)
        }
      }.width('100%').padding({ left: 14, right: 14 })
    }.height(54).width('100%').backgroundColor(this.colors.surface).borderRadius(14)
      .enabled(!this.blocked()).onClick(this.onLocal)
    if (this.loading) {
      LoadingProgress().width(26).height(26).color(this.colors.primary)
    } else if (!this.loaded) {
      Button('重试').height(42).fontColor(this.colors.primary).backgroundColor(this.colors.surface)
        .onClick(() => { void this.reload(); })
    } else {
      ForEach(this.hosts, (host: RemoteHost) => {
        this.hostRow(host)
      }, (host: RemoteHost) => JSON.stringify(host))
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Text(DshGlyphs.add).fontFamily(DshGlyphs.family).fontSize(18).fontColor(this.colors.primary)
          Text('连接电脑或服务器').fontSize(15).fontColor(this.colors.primary)
        }.padding({ left: 14, right: 14 })
      }.height(44).backgroundColor(this.colors.primaryContainer).borderRadius(22).enabled(!this.blocked())
        .onClick(() => this.edit())
    }
    Text('在电脑运行 dsh web，并通过 HTTPS 暴露 DSH。复制带 token 的完整启动链接，保留路径和查询参数。')
      .fontSize(13).fontColor(this.colors.hint).width('100%').lineHeight(20)
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Button({ type: ButtonType.Circle }) {
          Text(DshGlyphs.back).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.text)
        }.width(44).height(44).backgroundColor(this.colors.surface).accessibilityText('返回').enabled(!this.blocked())
          .onClick(() => { if (!this.back()) this.onClose(); })
        Text('远程主机').fontSize(21).fontWeight(FontWeight.Medium).fontColor(this.colors.text).layoutWeight(1)
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
      Scroll() {
        Column({ space: 12 }) {
          if (this.failure || this.errorText) {
            Text(this.failure || this.errorText)
              .fontSize(14).fontColor(this.colors.danger).width('100%')
          }
          if (this.editing) {
            this.editor()
          } else {
            this.hostList()
          }
        }.width('100%').constraintSize({ maxWidth: 640 }).alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 20 })
      }.width('100%').layoutWeight(1).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(this.colors.background)
  }
}
