import { constants, createReadStream } from 'node:fs';
import { lstat, mkdir, open, rename, rm, statfs } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { get } from 'node:https';
import { join, dirname } from 'node:path';

const modelMirror = 'https://www.modelscope.cn/models/pengzhendong/sherpa-onnx-sense-voice-zh-en-ja-ko-yue/resolve/73eca47697f980daa3d16112404174b6b950b514/';
const modelOrigin = 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/2365baeacb507f821a0c8120fcee3d484dba7a07/';
export const senseVoiceAssets = [
  { path: 'sensevoice-onnx/model.int8.onnx', bytes: 239233841,
    sha256: 'c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51',
    urls: [modelMirror + 'model.int8.onnx', modelOrigin + 'model.int8.onnx'] },
  { path: 'sensevoice-onnx/tokens.txt', bytes: 315894,
    sha256: 'f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc',
    urls: [modelMirror + 'tokens.txt', modelOrigin + 'tokens.txt'] },
  { path: 'silero/silero_vad.onnx', bytes: 1807522,
    sha256: 'a35ebf52fd3ce5f1469b2a36158dba761bc47b973ea3382b3186ca15b1f5af28',
    urls: ['https://www.modelscope.cn/models/pengzhendong/silero-vad/resolve/370539c71ec0ac703627938064cf31c1852186d7/v4/silero_vad.onnx',
      'https://huggingface.co/csukuangfj/vad/resolve/fba88cd2e921609e7675c3aaf51e0b9b295da4bc/silero_vad.onnx'] }
];
export const senseVoiceTotalBytes = senseVoiceAssets.reduce((sum, asset) => sum + asset.bytes, 0);
export const spareBytes = 100 * 1024 * 1024;

export function modelFailure(reason, message) { return Object.assign(new Error(message), { reason }); }
export async function privateDirectory(path) {
  await mkdir(path, { recursive: true, mode: 0o700 });
  const info = await lstat(path);
  if (!info.isDirectory() || info.isSymbolicLink()) throw modelFailure('storage', 'Model directory is not a private directory');
}
export async function fileBytes(path) {
  try {
    const info = await lstat(path);
    if (!info.isFile() || info.isSymbolicLink()) throw modelFailure('storage', 'Unsafe model file');
    return info.size;
  } catch (error) { if (error.code === 'ENOENT') return 0; throw error; }
}
export async function matchesAsset(path, asset, signal) {
  if (await fileBytes(path) !== asset.bytes) return false;
  const hash = createHash('sha256');
  for await (const bytes of createReadStream(path, { flags: constants.O_RDONLY | constants.O_NOFOLLOW, signal })) hash.update(bytes);
  return hash.digest('hex') === asset.sha256;
}

export function openModelUrl(url, offset, signal, redirects = 0) {
  const target = new URL(url);
  if (target.protocol !== 'https:' || target.username || target.password || redirects > 5) {
    return Promise.reject(modelFailure('network', 'Unsafe model download URL'));
  }
  return new Promise((resolve, reject) => {
    let headerDeadline;
    // Set the initial socket budget before the Agent creates it. setTimeout()
    // alone only takes over after connect and otherwise inherits its 5s default.
    const request = get(target, { signal, timeout: 60000,
      // Match upstream voice_model_download.dart; the mirror CDN rejects an absent user agent.
      headers: { 'user-agent': 'dsh-go', 'accept-encoding': 'identity', ...(offset ? { range: `bytes=${offset}-` } : {}) } }, response => {
      clearTimeout(headerDeadline);
      if ([301, 302, 303, 307, 308].includes(response.statusCode)) {
        response.destroy();
        if (!response.headers.location) { reject(modelFailure('network', 'Missing model redirect location')); return; }
        try { resolve(openModelUrl(new URL(response.headers.location, target), offset, signal, redirects + 1)); }
        catch (error) { reject(error); }
      } else {
        response.setTimeout(60000, () => response.destroy(modelFailure('timeout', 'Model download stalled')));
        resolve(response);
      }
    });
    // Socket inactivity does not reliably bound DNS/TLS/header establishment.
    // Stop this deadline once headers arrive; an active large download may take longer.
    headerDeadline = setTimeout(() => request.destroy(modelFailure('timeout', 'Model connection timed out')), 60000);
    request.setTimeout(60000, () => request.destroy(modelFailure('timeout', 'Model download timed out')));
    request.once('close', () => clearTimeout(headerDeadline));
    request.on('error', error => { clearTimeout(headerDeadline); reject(error); });
  });
}

export async function downloadAsset(root, asset, signal, progress, openUrl = openModelUrl) {
  const target = join(root, asset.path), partial = target + '.dsh-go.part';
  await privateDirectory(dirname(target));
  signal.throwIfAborted();
  if (await matchesAsset(target, asset, signal)) { progress(asset.bytes); return; }
  let last;
  for (const url of asset.urls) {
    signal.throwIfAborted();
    let response, output;
    try {
      let offset = await fileBytes(partial);
      if (offset > asset.bytes) { await rm(partial); offset = 0; }
      if (offset === asset.bytes) {
        if (await matchesAsset(partial, asset, signal)) { await rename(partial, target); progress(offset); return; }
        await rm(partial); offset = 0;
      }
      response = await openUrl(url, offset, signal);
      if (![200, 206].includes(response.statusCode)) throw modelFailure('http', `Model server returned ${response.statusCode}`);
      if (response.headers['content-encoding'] && response.headers['content-encoding'] !== 'identity') throw modelFailure('integrity', 'Encoded model response');
      if (response.statusCode === 206) {
        const expected = `bytes ${offset}-${asset.bytes - 1}/${asset.bytes}`;
        if (response.headers['content-range'] !== expected) throw modelFailure('integrity', 'Invalid model resume range');
      } else offset = 0;
      const length = response.headers['content-length'];
      if (length !== undefined && (!/^\d+$/.test(length) || Number(length) !== asset.bytes - offset)) throw modelFailure('integrity', 'Invalid model response length');
      output = await open(partial, constants.O_WRONLY | constants.O_CREAT | constants.O_NOFOLLOW |
        (offset ? constants.O_APPEND : constants.O_TRUNC), 0o600);
      if (!(await output.stat()).isFile()) throw modelFailure('storage', 'Unsafe partial model file');
      progress(offset);
      for await (const chunk of response) {
        signal.throwIfAborted();
        if (offset + chunk.length > asset.bytes) throw modelFailure('integrity', 'Model response exceeds pinned length');
        let written = 0;
        while (written < chunk.length) {
          const result = await output.write(chunk, written, chunk.length - written);
          if (!result.bytesWritten) throw modelFailure('storage', 'Model write made no progress');
          written += result.bytesWritten;
        }
        offset += chunk.length;
        progress(offset);
      }
      await output.sync(); await output.close(); output = undefined;
      if (offset !== asset.bytes || !await matchesAsset(partial, asset, signal)) {
        await rm(partial, { force: true });
        throw modelFailure('integrity', 'Model SHA-256 does not match the pinned asset');
      }
      signal.throwIfAborted();
      await rename(partial, target);
      return;
    } catch (error) {
      last = error;
      if (signal.aborted || error.code === 'ENOSPC' || error.reason === 'storage') throw error;
    } finally { response?.destroy(); await output?.close(); }
  }
  throw last ?? modelFailure('network', 'No model download source');
}

export async function presentBytes(root, assets = senseVoiceAssets) {
  let total = 0;
  for (const asset of assets) {
    const size = await fileBytes(join(root, asset.path));
    total += size === asset.bytes ? size : Math.min(asset.bytes, await fileBytes(join(root, asset.path) + '.dsh-go.part'));
  }
  return total;
}
export async function checkModelSpace(root, neededBytes) {
  const info = await statfs(root);
  if (info.bavail * info.bsize < neededBytes + spareBytes) throw Object.assign(
    modelFailure('storage', 'Not enough free storage for the speech model'), { neededBytes: neededBytes + spareBytes });
}
