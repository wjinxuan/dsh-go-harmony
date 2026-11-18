import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

export async function loadMediaModules(clientClass = 'export class DshClient {}') {
  const root = new URL('../entry/src/main/ets/dsh/', import.meta.url);
  let source = 0;
  const url = code => 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(code) + `\n//# sourceURL=media-fixture-${source++}.js`);
  const wire = url(await readFile(new URL('DshWire.ets', root), 'utf8'));
  const presets = url((await readFile(new URL('MediaPresets.ets', root), 'utf8')).replace(/^import type .*\n/, ''));
  const data = url((await readFile(new URL('MediaData.ets', root), 'utf8'))
    .replace(', WireObject', '').replace("'./DshWire'", JSON.stringify(wire)).replace("'./MediaPresets'", JSON.stringify(presets)));
  const api = url((await readFile(new URL('MediaApi.ets', root), 'utf8'))
    .replace("import { util } from '@kit.ArkTS'", "const util = { Base64Helper: class { decodeSync(value) { return Uint8Array.from(Buffer.from(value, 'base64')); } } }")
    .replace("'./DshClient'", JSON.stringify(url(clientClass))).replace(', WireObject', '')
    .replace('MediaCatalog, MediaNamespace, MediaService, mediaCatalog', 'mediaCatalog').replace("'./DshWire'", JSON.stringify(wire))
    .replace("'./MediaData'", JSON.stringify(data)));
  const binary = url((await readFile(new URL('DshBinaryResponse.ets', root), 'utf8'))
    .replace("import { util } from '@kit.ArkTS'", "const util = { TextDecoder: { create() { return { decodeToString(value) { return new TextDecoder().decode(value); } }; } } }")
    .replace(', WireObject', '').replace("'./DshWire'", JSON.stringify(wire)));
  return { ...await import(data), ...await import(api), ...await import(binary) };
}
