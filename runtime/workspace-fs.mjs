import { lstatSync, realpathSync } from 'node:fs';
import { link, lstat, mkdir, opendir, readdir } from 'node:fs/promises';
import { once } from 'node:events';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { watch } from 'chokidar';
import { FsError } from '@deepseek-ai/dsh-fs';
import { SandboxedFileSystem } from '@deepseek-ai/dsh-fs-sandbox';
import { DirectoryPicker, DirectoryPickerError } from '@deepseek-ai/dsh-host-directory-picker';
import { boundedInsert } from '@deepseek-ai/dsh-host-directory-picker-browse';

function inside(root, path) {
  const suffix = relative(root, path);
  return suffix !== '..' && !suffix.startsWith(`..${sep}`) && !isAbsolute(suffix);
}

function denied() {
  return new FsError('File access is limited to the local workspace. Symbolic links and parent traversal are unavailable.',
    'FS_SANDBOX_DENIED');
}

function stagingSegment(name) {
  return /^\..+\.\d+\.[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.tmpdir$/s.test(name);
}

export default class WorkspaceFileSystem extends SandboxedFileSystem {
  constructor(ctx, config) {
    if (!isAbsolute(config.cwd) || !lstatSync(config.cwd).isDirectory()) throw denied();
    super(ctx, config);
    this.configuredRoot = resolve(config.cwd);
    this.root = realpathSync(config.cwd);
    this.internals.linkFile = (staged, final) => typeof globalThis.dshHarmonyPublishWorkspaceFile === 'function'
      ? globalThis.dshHarmonyPublishWorkspaceFile(staged, final) : link(staged, final);
  }

  async scopedPath(path, cwd = this.root, signal) {
    signal?.throwIfAborted();
    if (typeof path !== 'string' || !path.trim() || path.includes('\0') ||
        path.startsWith('~') || path.split(sep).includes('..')) throw denied();
    const candidate = resolve(cwd, path);
    const rooted = inside(this.configuredRoot, candidate)
      ? join(this.root, relative(this.configuredRoot, candidate)) : candidate;
    if (!inside(this.root, rooted)) throw denied();
    if (!(await lstat(this.root)).isDirectory()) throw denied();
    const suffix = relative(this.root, rooted);
    const segments = suffix ? suffix.split(sep) : [];
    if (segments.some(stagingSegment)) throw denied();
    let current = this.root;
    for (const segment of segments) {
      current = join(current, segment);
      try {
        if ((await lstat(current)).isSymbolicLink()) throw denied();
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
        break;
      }
      signal?.throwIfAborted();
    }
    return rooted;
  }

  async resolve(path, opts) {
    const scoped = await this.scopedPath(path, opts?.cwd, opts?.signal);
    const target = await super.resolve(scoped, opts);
    if (!inside(this.root, target.targetKey) || target.targetKey !== scoped) throw denied();
    return target;
  }

  async workspaceDirectory(path = this.root) {
    if (!isAbsolute(path)) throw denied();
    const target = await this.resolve(path);
    if ((await super.stat(target))?.type !== 'directory') throw denied();
    return target.targetKey;
  }

  async lstat(path, opts, signal) {
    return super.lstat(await this.scopedPath(path, opts?.cwd, signal), opts, signal);
  }

  async stat(target, signal) {
    return super.stat(await this.checkedRead(target, signal), signal);
  }

  async readText(target, signal) {
    return super.readText(await this.checkedRead(target, signal), signal);
  }

  async streamText(target, signal) {
    return super.streamText(await this.checkedRead(target, signal), signal);
  }

  async readBytes(target, signal, maxBytes) {
    return super.readBytes(await this.checkedRead(target, signal), signal, maxBytes);
  }

  async readByteRange(target, range, signal) {
    return super.readByteRange(await this.checkedRead(target, signal), range, signal);
  }

  async watch(target, changed, signal) {
    const safe = await this.checkedRead(target, signal);
    const path = safe.targetKey;
    const directory = (await this.stat(safe, signal))?.type === 'directory';
    signal.throwIfAborted();
    const root = directory ? path : dirname(path);
    const watcher = watch(root, {
      ignoreInitial: true, depth: 0, followSymlinks: false,
      ignored: (entry, info) => info?.isSymbolicLink() === true || stagingSegment(basename(entry)) ||
        (!directory && entry !== root && entry !== path)
    });
    watcher.on('all', (_event, entry) => {
      if (directory || entry === path) changed();
    });
    watcher.on('error', changed);
    try {
      await once(watcher, 'ready', { signal });
      return () => watcher.close();
    } catch (error) {
      await watcher.close();
      throw error;
    }
  }

  async listDir(target, signal) {
    const safe = await this.checkedRead(target, signal);
    const info = await super.stat(safe, signal);
    if (!info) throw new FsError('Workspace directory does not exist.', 'FS_NOT_FOUND');
    if (info.type !== 'directory') throw new FsError('Workspace path is not a directory.', 'FS_NOT_DIRECTORY');
    const result = [];
    const entries = await readdir(safe.targetKey, { withFileTypes: true });
    for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
      signal?.throwIfAborted();
      if (entry.isSymbolicLink() || stagingSegment(entry.name)) continue;
      const child = await this.resolve(join(safe.targetKey, entry.name), { signal });
      const childInfo = await this.stat(child, signal);
      result.push({ name: entry.name, target: child, type: childInfo?.type ?? 'other',
        size: childInfo?.size, version: childInfo?.version });
    }
    return result;
  }

  async checkedTarget(target, policy) {
    await this.checkedRead(target);
    const checked = await super.checkedTarget(target, policy);
    return this.checkedRead(checked);
  }

  async checkedRead(target, signal) {
    const fresh = await this.resolve(target.displayPath, { signal });
    if (fresh.targetKey !== target.targetKey) throw denied();
    return fresh;
  }

  processPathFromHostPath(path) {
    const candidate = super.processPathFromHostPath(path);
    return candidate && inside(this.root, candidate) ? candidate : undefined;
  }
}

export class WorkspaceDirectoryPicker extends DirectoryPicker {
  static inject = ['fs'];

  browse = {
    kind: 'browse',
    list: (path, signal) => this.list(path, signal),
    createDirectory: (path, name) => this.createDirectory(path, name)
  };

  capability() {
    return this.browse;
  }

  async list(path, signal) {
    const root = this.ctx.fs.root;
    let target;
    const entries = [];
    let truncated = false;
    try {
      if (path !== undefined && !isAbsolute(path)) throw denied();
      target = await this.ctx.fs.scopedPath(path ?? root, root, signal);
      const directory = await opendir(target);
      for await (const entry of directory) {
        signal?.throwIfAborted();
        if (entry.isDirectory() && !stagingSegment(entry.name)) {
          const row = { name: entry.name, path: join(target, entry.name), hidden: entry.name.startsWith('.') };
          truncated = boundedInsert(entries, row, 1000) || truncated;
        }
      }
    } catch {
      signal?.throwIfAborted();
      throw new DirectoryPickerError('directory-unreadable', root, 'Cannot list that local workspace directory.');
    }
    const crumbs = [];
    for (let current = target; ; current = dirname(current)) {
      crumbs.unshift({ name: basename(current), path: current, hidden: false });
      if (current === root) break;
    }
    return { path: target, home: root, crumbs, entries, truncated };
  }

  async createDirectory(path, name) {
    const root = this.ctx.fs.root;
    let target;
    try {
      if (!isAbsolute(path) || !name.trim() || name === '.' || name === '..' || /[/\\\u0000]/.test(name) ||
          stagingSegment(name)) throw denied();
      const parent = await this.ctx.fs.scopedPath(path);
      target = join(parent, name);
      await mkdir(target);
      return target;
    } catch (error) {
      if (error.code === 'EEXIST') {
        throw new DirectoryPickerError('directory-exists', target, 'A workspace entry already has that name.');
      }
      throw new DirectoryPickerError('directory-create-failed', root, 'Cannot create that local workspace directory.');
    }
  }
}
