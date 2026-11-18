import { constants } from 'node:fs';
import { open, mkdir, rename, rm, lstat } from 'node:fs/promises';
import { join, dirname } from 'node:path';

const keepPaths = {
  uiAndSkills: ['dsh-go', 'skills', 'workspace/.dsh/skills', 'workspace/.agents/skills'],
  pluginsAndSettings: ['profile', 'cordis.patch.yml', '.env', '.harmony-bundled-bot.json', '.harmony-provider-credentials.json']
};
async function exists(path) { try { await lstat(path); return true; } catch (error) { if (error.code === 'ENOENT') return false; throw error; } }
async function planAt(path) {
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = await file.stat();
    if (!info.isFile() || info.size > 1024) throw new Error('Invalid reset plan');
    const value = JSON.parse(await file.readFile('utf8'));
    if (value?.version !== 1 || typeof value.uiAndSkills !== 'boolean' || typeof value.pluginsAndSettings !== 'boolean' ||
      Object.keys(value).some(key => !['version', 'uiAndSkills', 'pluginsAndSettings'].includes(key))) throw new Error('Invalid reset plan');
    return value;
  } finally { await file.close(); }
}
async function directory(path) {
  await mkdir(path, { recursive: true, mode: 0o700 });
  const info = await lstat(path);
  if (!info.isDirectory() || info.isSymbolicLink()) throw new Error('Unsafe reset directory');
}
export async function resetBeforeStart(root) {
  const retired = root + '.retired', request = root + '.reset-request';
  let plan;
  if (await exists(retired)) {
    await directory(retired);
    plan = await planAt(join(retired, 'harmony-reset-plan.json'));
  } else {
    if (!await exists(request)) return false;
    plan = await planAt(request);
    await directory(root);
    const file = await open(join(root, 'harmony-reset-plan.json'), constants.O_CREAT | constants.O_WRONLY | constants.O_TRUNC | constants.O_NOFOLLOW, 0o600);
    try { await file.writeFile(JSON.stringify(plan)); await file.sync(); } finally { await file.close(); }
    await rename(root, retired);
  }
  await rm(request, { force: true });
  await directory(root);
  const paths = Object.entries(keepPaths).flatMap(([key, paths]) => plan[key] ? paths : []);
  for (const path of paths) {
    const source = join(retired, path), destination = join(root, path);
    let ancestor = retired;
    for (const part of dirname(path).split('/').filter(p => p !== '.')) {
      ancestor = join(ancestor, part);
      if (await exists(ancestor)) {
        const info = await lstat(ancestor);
        if (!info.isDirectory() || info.isSymbolicLink()) throw new Error('Unsafe reset source directory');
      }
    }
    if (!await exists(source)) continue;
    const info = await lstat(source);
    if (info.isSymbolicLink()) throw new Error('Refusing a symbolic link in reset preservation');
    if (await exists(destination)) throw new Error('Reset preservation conflicts with existing data');
    // No user data is deleted until all selected paths have moved successfully.
    let parent = root;
    for (const part of dirname(path).split('/').filter(p => p !== '.')) { parent = join(parent, part); await directory(parent); }
    await rename(source, destination);
  }
  await rm(retired, { recursive: true, force: true });
  return true;
}
