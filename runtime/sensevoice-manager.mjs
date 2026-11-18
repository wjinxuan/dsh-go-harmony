import { constants } from 'node:fs';
import { open, readFile, rename, rm } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { senseVoiceAssets, privateDirectory, presentBytes, fileBytes,
  matchesAsset, downloadAsset, checkModelSpace, modelFailure } from './sensevoice-models.mjs';

export class SenseVoiceManager {
  constructor(root, native, { assets = senseVoiceAssets, download = downloadAsset, space = checkModelSpace } = {}) {
    this.root = root; this.native = native; this.assets = assets; this.download = download; this.space = space;
    this.models = join(root, 'models'); this.staging = join(root, 'dsh-go-staging');
    this.listeners = new Set(); this.loaded = false; this.wanted = false; this.closed = false;
    this.state = { phase: 'unprepared', completedBytes: 0, totalBytes: assets.reduce((sum, asset) => sum + asset.bytes, 0) };
    this.initialized = this.initialize();
  }
  async initialize() {
    await privateDirectory(this.root);
    await privateDirectory(this.models);
    await privateDirectory(this.staging);
    try { this.wanted = await readFile(join(this.root, 'wanted'), 'utf8') === '1'; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    this.change({ phase: 'unprepared', completedBytes: await presentBytes(this.models, this.assets) });
  }
  async resume() {
    await this.initialized;
    const complete = (await Promise.all(this.assets.map(asset => fileBytes(join(this.models, asset.path))))).every((n, i) => n === this.assets[i].bytes);
    if (this.wanted || complete) this.prepare();
  }
  snapshot() { return { ...this.state, wanted: this.wanted, nativeAvailable: !!this.native, loaded: this.loaded }; }
  subscribe(listener) { this.listeners.add(listener); return () => this.listeners.delete(listener); }
  change(patch) { this.state = { ...this.state, ...patch }; for (const listener of this.listeners) listener(); }
  async remember(wanted) {
    const path = join(this.root, 'wanted'), staged = path + '.tmp';
    const file = await open(staged, constants.O_CREAT | constants.O_WRONLY | constants.O_TRUNC | constants.O_NOFOLLOW, 0o600);
    try { await file.writeFile(wanted ? '1' : '0'); await file.sync(); } finally { await file.close(); }
    await rename(staged, path); this.wanted = wanted;
  }
  prepare(options) {
    if (options?.downloadSource && !['modelscope', 'huggingface'].includes(options.downloadSource)) throw modelFailure('network', 'Unknown model download source');
    this.start(false, options?.downloadSource).catch(() => {});
  }
  start(replace = false, source) {
    if (this.closed || this.deleting || this.cancelling) return Promise.reject(modelFailure('engine', 'SenseVoice is stopping'));
    if (this.running) return this.running;
    if (this.inference) return Promise.reject(modelFailure('engine', 'SenseVoice is transcribing'));
    this.change({ phase: 'checking', failure: undefined, download: undefined });
    const controller = new AbortController(); this.controller = controller;
    this.running = this.runDownload(replace, source, controller.signal).finally(() => {
      this.running = undefined; this.controller = undefined;
    });
    return this.running;
  }
  async runDownload(replace, source, signal) {
    const kept = this.loaded;
    try {
      await this.initialized;
      signal.throwIfAborted();
      if (!this.native) throw modelFailure('engine', 'This runtime has no Harmony SenseVoice inference bridge');
      await this.remember(true);
      const root = replace ? this.staging : this.models;
      if (replace) { await rm(root, { recursive: true, force: true }); await privateDirectory(root); }
      const present = await presentBytes(root, this.assets);
      let needed = 0;
      for (const asset of this.assets) {
        if (!await matchesAsset(join(root, asset.path), asset, signal)) {
          needed += asset.bytes - Math.min(asset.bytes, await fileBytes(join(root, asset.path) + '.dsh-go.part'));
        }
      }
      await this.space(this.root, needed);
      this.change({ phase: 'checking', completedBytes: present, failure: undefined, download: undefined });
      let done = 0;
      for (const pinned of this.assets) {
        signal.throwIfAborted();
        const asset = source === 'huggingface' ? { ...pinned, urls: pinned.urls.slice(1) } : pinned;
        await this.download(root, asset, signal, completedBytes => this.change({ phase: 'downloading',
          resource: asset.path, completedBytes: done + completedBytes }));
        done += asset.bytes;
      }
      signal.throwIfAborted();
      this.change({ phase: 'checking', completedBytes: done });
      for (const asset of this.assets) if (!await matchesAsset(join(root, asset.path), asset, signal)) {
        throw modelFailure('integrity', 'Model verification failed');
      }
      if (replace) {
        // Every replacement has the same pinned content; each rename preserves a complete old or new file.
        for (const asset of this.assets) {
          await privateDirectory(dirname(join(this.models, asset.path)));
          await rename(join(root, asset.path), join(this.models, asset.path));
        }
        await rm(root, { recursive: true, force: true });
      }
      signal.throwIfAborted();
      this.change({ phase: 'loading', completedBytes: done });
      try { await this.native.load(); } catch (error) { throw modelFailure('engine', error.message); }
      signal.throwIfAborted();
      this.loaded = true;
      await this.remember(false);
      this.change({ phase: 'ready', failure: undefined, download: undefined, resource: undefined });
    } catch (error) {
      if (!kept && this.native) { await this.native.unload(); this.loaded = false; }
      await this.remember(false);
      if (replace) await rm(this.staging, { recursive: true, force: true });
      const reason = error.reason ?? (error.code === 'ENOSPC' ? 'storage' : error.code?.includes('CERT') ? 'certificate' : 'network');
      this.change({ phase: kept ? 'ready' : signal.aborted ? 'cancelled' : 'failed',
        completedBytes: kept ? this.state.totalBytes : await presentBytes(this.models, this.assets),
        failure: signal.aborted ? undefined : { reason, neededBytes: error.neededBytes },
        download: signal.aborted ? undefined : { reason }, resource: undefined });
      throw error;
    }
  }
  cancel() {
    if (this.cancelling) return this.cancelling;
    this.cancelling = this.cancelRun().finally(() => { this.cancelling = undefined; });
    return this.cancelling;
  }
  async cancelRun() {
    if (this.running) {
      this.change({ phase: 'cancelling' });
      this.controller.abort(new Error('Model preparation cancelled'));
      this.native?.cancel();
      await this.running.catch(() => {});
    }
    await this.initialized;
    await this.remember(false);
  }
  remove() {
    if (this.removing) return this.removing;
    this.deleting = true;
    this.removing = this.removeRun().finally(() => { this.deleting = false; this.removing = undefined; });
    return this.removing;
  }
  async removeRun() {
    await this.cancel();
    this.change({ phase: 'cancelling' });
    try {
      this.native?.cancel();
      await this.inference?.catch(() => {});
      await this.native?.unload();
      this.loaded = false;
      await rm(this.models, { recursive: true, force: true });
      await rm(this.staging, { recursive: true, force: true });
      await privateDirectory(this.models);
      this.change({ phase: 'unprepared', completedBytes: 0, failure: undefined, download: undefined });
    } finally { this.deleting = false; }
  }
  async transcribe(input, signal) {
    if (!this.loaded || this.running || this.inference || this.deleting || this.closed) throw modelFailure('engine', 'SenseVoice is not ready or is busy');
    if (!['auto', 'zh', 'en', 'yue', 'ja', 'ko'].includes(input.language)) throw modelFailure('input', 'Unsupported SenseVoice language');
    signal.throwIfAborted();
    const audio = input.audio;
    const samples = new Float32Array((audio.length - 44) / 2);
    for (let i = 0; i < samples.length; i++) samples[i] = audio.readInt16LE(44 + i * 2) / 32768;
    const cancel = () => this.native.cancel();
    signal.addEventListener('abort', cancel, { once: true });
    const start = performance.now();
    this.inference = this.native.transcribe(samples, input.language);
    try {
      const text = await this.inference;
      signal.throwIfAborted();
      return { text: text.trim(), audioSeconds: samples.length / 16000, inferenceSeconds: (performance.now() - start) / 1000 };
    } finally { signal.removeEventListener('abort', cancel); this.inference = undefined; }
  }
  async close() {
    this.closed = true;
    const wanted = this.wanted;
    await this.cancel();
    this.native?.cancel();
    await this.inference?.catch(() => {});
    await this.native?.unload();
    this.loaded = false;
    if (wanted) await this.remember(true);
    this.listeners.clear();
  }
}
