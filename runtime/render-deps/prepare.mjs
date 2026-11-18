import { cp, copyFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const target = new URL('../../entry/src/main/resources/rawfile/render/', import.meta.url);
await mkdir(target, { recursive: true });
for (const [source, destination] of [
  ['mermaid/dist/mermaid.min.js', 'mermaid.min.js'], ['mermaid/LICENSE', 'MERMAID-LICENSE.txt'],
  ['katex/dist/katex.min.js', 'katex.min.js'], ['katex/dist/katex.min.css', 'katex.min.css'], ['katex/LICENSE', 'KATEX-LICENSE.txt']
]) await copyFile(new URL('node_modules/' + source, import.meta.url), new URL(destination, target));
await cp(fileURLToPath(new URL('node_modules/katex/dist/fonts/', import.meta.url)), fileURLToPath(new URL('fonts/', target)), { recursive: true });
