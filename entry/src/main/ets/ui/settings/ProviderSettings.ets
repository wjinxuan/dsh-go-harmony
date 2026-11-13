import { DshClient } from '../../dsh/DshClient';
import { array, DshSettingsOp, number, object, string, WireObject } from '../../dsh/DshWire';
import { DshGlyphs, ThemeColors, themeColors } from '../DshTheme';
import {
  PROVIDER_SETTINGS_NAMESPACE, providerDiscoveryArgs, providerEndpointValid, providerModelIds, providerRouteValid
} from './ProviderDraft';

const PROTOCOLS: string[] = ['openai-completions', 'anthropic-messages', 'openai-responses'];
const OPTIONS: SelectOption[] = [{ value: 'OpenAI' }, { value: 'Anthropic' }, { value: 'Responses' }];

interface CustomChannel {
  route: string;
  name: string;
  api: string;
  baseUrl: string;
  keyRef: string;
  models: WireObject[];
}

@Component
export struct ProviderSettings {
  @Prop colors: ThemeColors = themeColors();
  client: DshClient = new DshClient();
  onChange: () => void = () => {};
  onBackHandler?: (handler: (() => boolean) | undefined) => void;
  @State private channels: CustomChannel[] = [];
  @State private loaded: boolean = false;
  @State private supported: boolean = false;
  @State private writable: boolean = false;
  @State private revision: number = 0;
  @State private editing: boolean = false;
  @State private creating: boolean = false;
  @State private busy: boolean = false;
  @State private route: string = '';
  @State private name: string = '';
  @State private api: string = PROTOCOLS[0];
  @State private baseUrl: string = '';
  @State private credentialDraft: string = '';
  @State private modelIds: string = '';
  @State private found: string[] = [];
  @State private message: string = '';
  @State private failure: string = '';
  private active: boolean = true;
  private cleanDraft: string = '';

  aboutToAppear(): void {
    this.active = true;
    this.onBackHandler?.(() => this.back());
    void this.refresh();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.onBackHandler?.(undefined);
    this.credentialDraft = '';
  }

  private async refresh(): Promise<boolean> {
    try {
      const result = await this.client.describeSettings();
      if (!this.active) return false;
      const entry = array(result['namespaces']).map(object).find((item: WireObject) =>
        item['ns'] === PROVIDER_SETTINGS_NAMESPACE);
      this.supported = entry !== undefined;
      this.writable = this.supported && result['writable'] !== false && entry?.['writable'] !== false;
      this.revision = number(entry?.['revision'], 0);
      const profiles = object(object(entry?.['value'])['providers']);
      this.channels = Object.keys(profiles).map((route: string): CustomChannel => {
        const profile = object(profiles[route]);
        return {
          route: route, name: string(profile['displayName']), api: string(profile['api']),
          baseUrl: string(profile['baseURL']), keyRef: string(profile['apiKeyEnv']),
          models: array(profile['models']).map(object).filter((model: WireObject) => string(model['id']).length > 0)
        };
      });
      return true;
    } catch {
      if (this.active) this.failure = '无法读取自定义渠道。';
      return false;
    } finally {
      if (this.active) this.loaded = true;
    }
  }

  private edit(channel?: CustomChannel): void {
    this.failure = '';
    this.message = '';
    this.creating = !channel;
    this.route = channel?.route || '';
    this.name = channel?.name || '';
    this.api = channel?.api || PROTOCOLS[0];
    this.baseUrl = channel?.baseUrl || '';
    this.credentialDraft = '';
    this.modelIds = channel?.models.map((item: WireObject) => string(item['id'])).join('\n') || '';
    this.found = [];
    this.editing = true;
    this.cleanDraft = this.draftSignature();
  }

  private cancel(): void {
    this.editing = false;
    this.credentialDraft = '';
    this.found = [];
    this.failure = '';
    this.message = '';
  }

  private back(): boolean {
    if (this.busy) return true;
    if (!this.editing) return false;
    if (!this.credentialDraft && this.cleanDraft === this.draftSignature()) {
      this.cancel();
      return true;
    }
    this.getUIContext().showAlertDialog({
      title: '放弃更改？', message: '还没有保存渠道更改。',
      primaryButton: { value: '继续编辑', action: () => {} },
      secondaryButton: { value: '放弃', action: () => this.cancel() }
    });
    return true;
  }

  private draftSignature(): string {
    return JSON.stringify([this.route, this.name, this.api, this.baseUrl, this.modelIds]);
  }

  private async discover(): Promise<void> {
    const address = this.baseUrl.trim();
    if (!this.writable || this.busy || !providerEndpointValid(address)) return;
    this.failure = '';
    this.message = '';
    this.found = [];
    this.busy = true;
    const profile = this.channels.find((item: CustomChannel) => item.route === this.route);
    try {
      const args = providerDiscoveryArgs(address, this.api, this.credentialDraft.trim(),
        profile?.route, profile?.baseUrl, profile?.api);
      const result = await this.client.request('llm/discoverModels', args);
      if (this.active) {
        this.found = array(result).map((item: Object) => string(object(item)['id'])).filter((id: string) => id.length > 0);
        if (!this.found.length) this.message = '该端点没有返回模型。';
      }
    } catch {
      if (this.active) this.failure = '无法从端点读取模型，请检查地址、协议和 API Key。';
    } finally {
      if (this.active) this.busy = false;
    }
  }

  private addFound(id: string): void {
    const ids = providerModelIds(this.modelIds);
    if (!ids.includes(id)) this.modelIds = ids.concat(id).join('\n');
    this.found = this.found.filter((item: string) => item !== id);
  }

  private async save(): Promise<void> {
    if (!this.writable || this.busy) return;
    const route = this.route.trim();
    const name = this.name.trim();
    const address = this.baseUrl.trim();
    const ids = providerModelIds(this.modelIds);
    const current = this.channels.find((item: CustomChannel) => item.route === route);
    if (!providerRouteValid(route) || (this.creating && current)) {
      this.failure = '渠道 ID 必须唯一，由小写字母、数字和单连字符组成，以字母开头。';
      return;
    }
    if (!name || !providerEndpointValid(address) || ids.length === 0 || !PROTOCOLS.includes(this.api)) {
      this.failure = '填写渠道名称、有效的 HTTP(S) 地址及至少一个模型 ID。';
      return;
    }
    const key = this.credentialDraft.trim();
    const keyRef = current?.keyRef || `${route.toUpperCase().replace(/-/g, '_')}_API_KEY`;
    const models = ids.map((id: string): WireObject => {
      const model: WireObject = {};
      model['id'] = id;
      return current?.models.find((item: WireObject) => item['id'] === id) || model;
    });
    const values: WireObject = {};
    values['displayName'] = name;
    values['api'] = this.api;
    values['baseURL'] = address;
    values['models'] = models;
    if (key || current?.keyRef) values['apiKeyEnv'] = keyRef;
    const ops: DshSettingsOp[] = [];
    if (current) {
      for (const field of Object.keys(values)) {
        ops.push({ op: 'set', path: ['providers', route, field], value: values[field] });
      }
    } else {
      ops.push({ op: 'set', path: ['providers', route], value: values });
    }
    this.busy = true;
    this.failure = '';
    this.message = '';
    try {
      await this.client.mutateSettings(PROVIDER_SETTINGS_NAMESPACE, ops, this.revision);
      if (!this.active) return;
      if (!await this.refresh()) return;
      const saved = this.channels.find((item: CustomChannel) => item.route === route);
      if (!saved || saved.name !== name || saved.api !== this.api || saved.baseUrl !== address ||
        (key && saved.keyRef !== keyRef) ||
        saved.models.map((item: WireObject) => string(item['id'])).join('\n') !== ids.join('\n')) {
        this.failure = '主机读回的渠道与提交值不同。';
        return;
      }
      this.creating = false;
      if (key) {
        try {
          await this.client.setProviderKey(key, keyRef);
          const credentials = await this.client.describeCredentials([keyRef]);
          if (object(credentials[keyRef])['configured'] !== true) throw new Error('凭据状态不可用');
        } catch {
          if (this.active) this.failure = '渠道已保存，API Key 尚未确认。可以重试保存凭据。';
          this.onChange();
          return;
        }
      }
      if (this.active) {
        this.cancel();
        this.message = '渠道已保存。';
        this.onChange();
      }
    } catch {
      if (this.active) {
        await this.refresh();
        this.failure = '主机未保存渠道，请检查配置或刷新后重试。';
      }
    } finally {
      if (this.active) this.busy = false;
    }
  }

  private async remove(channel: CustomChannel): Promise<void> {
    if (!this.writable || this.busy) return;
    this.busy = true;
    this.failure = '';
    this.message = '';
    try {
      await this.client.mutateSettings(PROVIDER_SETTINGS_NAMESPACE,
        [{ op: 'unset', path: ['providers', channel.route] }], this.revision);
      if (await this.refresh() && this.active) {
        if (this.channels.some((item: CustomChannel) => item.route === channel.route)) {
          this.failure = '主机仍在提供此渠道，可能来自继承配置。';
        } else {
          this.cancel();
          this.message = '渠道已移除。';
          this.onChange();
        }
      }
    } catch {
      if (this.active) {
        await this.refresh();
        this.failure = '主机未能移除渠道。';
      }
    } finally {
      if (this.active) this.busy = false;
    }
  }

  @Builder
  private note(message: () => string, color: () => string) {
    Text(message()).width('100%').fontSize(14).fontColor(color());
  }

  @Builder
  private form() {
    Column({ space: 8 }) {
      this.note(() => this.creating ? '添加渠道' : '编辑渠道', () => this.colors.text);
      TextInput({ text: this.route, placeholder: '渠道 ID，如 gateway' }).fontColor(this.colors.text)
        .backgroundColor(this.colors.surfaceAlt).enabled(this.creating && !this.busy)
        .onChange((value: string) => this.route = value);
      TextInput({ text: this.name, placeholder: '渠道名称' }).fontColor(this.colors.text)
        .backgroundColor(this.colors.surfaceAlt).enabled(!this.busy).onChange((value: string) => this.name = value);
      Select(OPTIONS).value(PROTOCOLS.includes(this.api) ? OPTIONS[PROTOCOLS.indexOf(this.api)].value : this.api)
        .fontColor(this.colors.text).width('100%').backgroundColor(this.colors.surfaceAlt).enabled(!this.busy)
        .onSelect((index: number) => this.api = PROTOCOLS[index]);
      TextInput({ text: this.baseUrl, placeholder: 'Base URL' }).fontColor(this.colors.text)
        .backgroundColor(this.colors.surfaceAlt).enabled(!this.busy).onChange((value: string) => this.baseUrl = value);
      TextInput({ text: this.credentialDraft, placeholder: this.creating ? 'API Key（可选）' : 'API Key（留空保留）' })
        .type(InputType.Password).fontColor(this.colors.text).backgroundColor(this.colors.surfaceAlt)
        .enabled(!this.busy).onChange((value: string) => this.credentialDraft = value);
      TextArea({ text: this.modelIds, placeholder: '模型 ID，每行一个' }).height(98).fontColor(this.colors.text)
        .backgroundColor(this.colors.surfaceAlt).enabled(!this.busy).onChange((value: string) => this.modelIds = value);
      Button('从端点读取模型').width('100%').backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.text)
        .enabled(!this.busy && providerEndpointValid(this.baseUrl.trim())).onClick(() => { void this.discover(); });
      ForEach(this.found, (id: string) => {
        Button(`添加 ${id}`).width('100%').backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.text)
          .enabled(!this.busy).onClick(() => this.addFound(id));
      }, (id: string) => id);
      Button(this.busy ? '正在处理…' : '保存').width('100%').backgroundColor(this.colors.primary)
        .fontColor(this.colors.onPrimary).enabled(!this.busy && this.writable).onClick(() => { void this.save(); });
      Button('取消').width('100%').backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.text)
        .enabled(!this.busy).onClick(() => { this.back(); });
    }.width('100%');
  }

  build() {
    Column({ space: 10 }) {
      if (!this.loaded) {
        this.note(() => '正在读取渠道…', () => this.colors.muted);
      }
      if (this.failure) {
        this.note(() => this.failure, () => this.colors.danger);
      }
      if (this.message) {
        this.note(() => this.message, () => this.colors.success);
      }
      if (this.loaded && !this.supported && !this.failure) {
        this.note(() => '当前主机未提供自定义渠道。', () => this.colors.muted);
      }
      if (this.supported) {
        if (this.editing) {
          this.form();
        } else {
          ForEach(this.channels, (channel: CustomChannel) => {
            Row({ space: 8 }) {
              Button({ type: ButtonType.Normal }) {
                Column({ space: 3 }) {
                  Text(channel.name || channel.route).fontSize(15).fontColor(this.colors.text).width('100%');
                  Text(channel.route).fontSize(13).fontColor(this.colors.muted).width('100%');
                }.alignItems(HorizontalAlign.Start).padding(6);
              }.layoutWeight(1).backgroundColor(Color.Transparent).enabled(this.writable && !this.busy)
                .onClick(() => this.edit(channel));
              if (this.writable) {
                Button({ type: ButtonType.Circle }) {
                  Text(DshGlyphs.more).fontFamily(DshGlyphs.family).fontSize(20).fontColor(this.colors.text);
                }.backgroundColor(this.colors.surfaceAlt).width(40).height(40).enabled(!this.busy)
                  .accessibilityText('渠道操作').onClick(() => {
                    this.getUIContext().showAlertDialog({
                      title: '移除渠道', message: `移除「${channel.name || channel.route}」的渠道配置。`,
                      primaryButton: { value: '取消', action: () => {} },
                      secondaryButton: { value: '移除', action: () => { void this.remove(channel); } }
                    });
                  });
              }
            }.width('100%');
          }, (channel: CustomChannel) => `${channel.route}|${channel.name}|${this.revision}`);
          if (this.writable) {
            Button('添加渠道').width('100%').backgroundColor(this.colors.surfaceAlt).fontColor(this.colors.text)
              .enabled(!this.busy).onClick(() => this.edit());
          } else {
            this.note(() => '当前主机的渠道设置为只读。', () => this.colors.muted);
          }
        }
      }
    }.width('100%').padding(15).borderRadius(14).backgroundColor(this.colors.surface);
  }
}
