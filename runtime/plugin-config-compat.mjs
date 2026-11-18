// Build-time port of the fixed v1.0.15 ConfigEditor patches. The bridge supplies its
// own route guard, so no unrelated host-webserver changes are applied here.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
const destination = process.argv[2];
for (const name of ['zzz-config-editor-path.diff', 'zzzz-plugin-config-readability.diff', 'zzzzz-plugin-config-bundles.diff']) {
  const lines = readFileSync(new URL('./vendor/plugin-config-patches/' + name, import.meta.url), 'utf8').split('\n');
  let file, before = [], after = [];
  const flush = () => {
    if (!file || !before.length) return;
    if (!['node_modules/@deepseek-ai/dsh-config-editor/lib/index.js', 'node_modules/@deepseek-ai/dsh-app-boot/lib/index.js'].includes(file)) { before = []; after = []; return; }
    const path = join(destination, file), source = readFileSync(path, 'utf8'), match = before.join('\n') + '\n';
    if (source.split(match).length !== 2) throw new Error(`Unexpected fixed-source patch location: ${name}: ${file}`);
    writeFileSync(path, source.replace(match, after.join('\n') + '\n')); before = []; after = [];
  };
  for (const line of lines) {
    if (line.startsWith('--- a/')) { flush(); file = line.slice(6); }
    else if (line.startsWith('+++ ') || line.startsWith('#')) continue;
    else if (line.startsWith('@@')) flush();
    else if (line.startsWith(' ')) { before.push(line.slice(1)); after.push(line.slice(1)); }
    else if (line.startsWith('-')) before.push(line.slice(1));
    else if (line.startsWith('+')) after.push(line.slice(1));
  }
  flush();
}
const inventory = join(destination, 'node_modules/@deepseek-ai/dsh-host-plugin-inventory/lib/index.js');
const source = readFileSync(inventory, 'utf8');
const match = 'const management = ctx.get("pluginManager") === void 0 ? {} : { managementAvailable: true };';
if (source.split(match).length !== 2) throw new Error('Unexpected inventory management source');
writeFileSync(inventory, source.replace(match, 'const manager = ctx.get("pluginManager");\n\tconst management = { managementAvailable: manager !== undefined && manager.harmonyReadOnly !== true };'));
