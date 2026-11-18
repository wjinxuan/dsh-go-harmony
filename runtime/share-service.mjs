import { constants } from 'node:fs';
import { open, unlink, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { conversationFile, decodeFile, conversationHtml, assetId } from './share-codec.mjs';
import { exportConversation, exportRounds } from './share-export.mjs';
import { uploadShare, downloadShare, deleteShare, hostedLink } from './share-hosted.mjs';
import { profileSource, selectProfile, decodeProfileFile, shareKind, profileFile, profilePayload, planProfile, shareSafeProfile } from './share-profile.mjs';
import { readProfileFiles, applyProfileFiles, backupProfile } from './share-profile-files.mjs';
import { PrivateVault } from './private-vault.mjs';
import { redactConversation } from './share-redact.mjs';

const MAX_REQUEST = 24 * 1024 * 1024;
export function createShareHandler(root, options = {}) {
  const path = join(root, '.harmony-share-links.json'), active = new Set(), pending = new Set();
  let busy = false, stopped = false;
  const template = readFile(new URL('./vendor/replay/viewer.html', import.meta.url), 'utf8');
  async function readLinks(masterKey) {
    const vault = new PrivateVault(root, '.harmony-share-links-v2.json', masterKey);
    try {
      const stored = await vault.load();
      if (stored !== undefined) return validateLinks(stored);
    } finally { vault.destroy(); }
    let file;
    try { file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK); }
    catch (e) { if (e.code === 'ENOENT') return []; throw new Error('无法读取分享链接管理记录'); }
    try {
      const stat = await file.stat();
      if (!stat.isFile() || stat.size > 1024 * 1024 || stat.mode & 0o077) throw new Error();
      const links = validateLinks(JSON.parse(await file.readFile('utf8')));
      await writeLinks(links, masterKey);
      await unlink(path);
      return links;
    } catch { throw new Error('分享管理记录损坏，未覆盖原文件'); }
    finally { await file.close(); }
  }
  function validateLinks(links) {
    if (!Array.isArray(links) || links.length > 500 || links.some(v => !v || hostedLink(v.url).id !== v.id ||
      typeof v.deleteToken !== 'string' || !v.deleteToken || v.deleteToken.length > 4096)) throw new Error('分享链接管理记录无效');
    return links;
  }
  async function writeLinks(links, masterKey) {
    const vault = new PrivateVault(root, '.harmony-share-links-v2.json', masterKey);
    try { await vault.save(links); } finally { vault.destroy(); }
  }
  const publicLink = v => ({ id: v.id, url: v.url, title: v.title, created: v.created, expiresAt: v.expiresAt });
  async function action(name, body, signal) {
    if (name === 'profile-source') return profileSource(body.snapshot || {}, body.local === true ? readProfileFiles(root) : {});
    if (name === 'profile-prepare') return selectProfile(body.source, body.selected, body.name, body.pluginOnly === true);
    if (name === 'profile-plan') {
      const payload = profilePayload(body.payload), snapshot = body.snapshot || {};
      // Only the fixed public npm endpoint is contacted, with no credentials or redirects.
      const plugins = payload.kind === 'plugin' ? [payload.plugin] : payload.plugins, facts = {};
      await Promise.all(plugins.filter(p => p.source === 'npm').map(async p => {
        try {
          const response = await (options.fetcher || fetch)('https://registry.npmjs.org/' + encodeURIComponent(p.name) + '/' + encodeURIComponent(p.version),
            { signal: AbortSignal.any([signal, AbortSignal.timeout(8000)]), redirect: 'error', headers: { accept: 'application/json' } });
          if (!response.ok || Number(response.headers.get('content-length')) > 1024 * 1024) return;
          const reader=response.body.getReader();let size=0;const chunks=[];
          try { while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>1024*1024)throw new Error();chunks.push(value);} }
          finally { await reader.cancel().catch(()=>{}); }
          const value=JSON.parse(Buffer.concat(chunks).toString('utf8'));
          if(value.name===p.name&&value.version===p.version&&typeof value.dist?.integrity==='string')facts[p.name]={integrity:value.dist.integrity};
        } catch { /* Unverifiable is explicitly shown in the import preview. */ }
      }));
      signal.throwIfAborted();
      return planProfile(payload, { ...snapshot, facts }, snapshot.local === true ? readProfileFiles(root, payload) : {});
    }
    if (name === 'profile-backup') return backupProfile(root, body.confirmed);
    if (name === 'profile-files-apply') return applyProfileFiles(root, body, signal);
    if (name === 'links') return { links: (await readLinks(body.masterKey)).map(publicLink) };
    if (name === 'rounds') return { rounds: exportRounds(body.source) };
    if (name === 'prepare') {
      const source = body.source;
      const assets = Object.create(null); source.images = Object.create(null);
      for (const picture of body.images || []) {
        if (!picture || typeof picture.attachmentId !== 'string' || typeof picture.data !== 'string' || picture.data.length > 4 * 1024 * 1024) throw new Error('分享图片无效');
        const id = assetId(Buffer.from(picture.data, 'base64'));
        assets[id] = { type: picture.type, data: picture.data, w: picture.w, h: picture.h };
        source.images[picture.attachmentId] = { id, w: picture.w, h: picture.h };
      }
      const result = conversationFile(exportConversation(source, body.options), assets);
      return { ...result, html: conversationHtml(result.file, result.body.title, await template) };
    }
    if (name === 'decode') {
      const file = body.link ? await downloadShare(body.link, { signal, fetcher: options.fetcher }) : body.text;
      if (shareKind(file) !== 'conversation') return decodeProfileFile(file);
      const result = decodeFile(file), rebuilt = conversationFile(result.body, result.assets);
      return { ...rebuilt, html: conversationHtml(rebuilt.file, result.body.title, await template) };
    }
    if (name === 'upload' || name === 'delete') {
      if (busy) throw new Error('另一个链接操作正在进行');
      busy = true;
      try {
        const links = await readLinks(body.masterKey);
        if (name === 'delete') {
          const link = links.find(v => v.id === body.id);
          if (!link) throw new Error('找不到这个链接的删除凭据');
          await deleteShare(link, { signal, fetcher: options.fetcher });
          await writeLinks(links.filter(v => v.id !== body.id), body.masterKey);
          return { deleted: body.id };
        }
        if (links.length >= 500) throw new Error('分享链接管理记录已满，请先删除旧链接');
        const decoded = shareKind(body.file) === 'conversation' ? decodeFile(body.file) : decodeProfileFile(body.file);
        const result = decoded.body.kind === 'conversation' ? conversationFile(redactConversation(decoded.body), decoded.assets) : profileFile(shareSafeProfile(decoded.body));
        await writeLinks(links, body.masterKey);
        const link = await uploadShare(result.file, body.ttl, { signal, fetcher: options.fetcher });
        link.title = result.body.title || result.body.name || result.body.plugin?.title || result.body.plugin?.name || '配置'; link.created = new Date().toISOString();
        try { await writeLinks(links.concat(link), body.masterKey); }
        catch {
          // Never discard an uploaded link's deletion credentials on a failed local save.
          try { await deleteShare(link, { signal: AbortSignal.timeout(15000), fetcher: options.fetcher }); }
          catch { return { link: publicLink(link), recovery: JSON.stringify(link), warning: '管理记录保存失败，远端清理也失败。请保存恢复凭据，以便删除此链接。' }; }
          throw new Error('链接管理记录保存失败，刚上传的链接已撤回');
        }
        return { link: publicLink(link) };
      } finally { busy = false; }
    }
    throw new Error('未知分享操作');
  }
  return {
    handle(request, response) {
      if (!request.url?.startsWith('/share/')) return false;
      const name = request.url.slice(7), reply = (status, value) => {
        if (!response.destroyed) response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' }).end(JSON.stringify(value));
      };
      if (stopped || request.method !== 'POST' || !['links', 'rounds', 'prepare', 'decode', 'upload', 'delete', 'profile-source', 'profile-prepare', 'profile-plan', 'profile-backup', 'profile-files-apply'].includes(name)) { request.resume(); reply(404, { error: '未知分享操作' }); return true; }
      if (!/^application\/json(?:;|$)/i.test(request.headers['content-type'] || '') || Number(request.headers['content-length']) > MAX_REQUEST) { request.resume(); reply(413, { error: '分享请求无效或过大' }); return true; }
      const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 90000);
      active.add(controller);
      response.on('close', () => { if (!response.writableEnded) controller.abort(); });
      const work = (async () => {
        const chunks = []; let size = 0;
        for await (const chunk of request) { size += chunk.length; if (size > MAX_REQUEST) throw new Error('分享请求过大'); chunks.push(chunk); }
        const body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)));
        if (!body || typeof body !== 'object' || Array.isArray(body) || controller.signal.aborted) throw new Error('分享请求无效');
        reply(200, await action(name, body, controller.signal));
      })().catch(error => reply(400, { error: controller.signal.aborted ? '分享操作已取消或超时' : error instanceof Error ? error.message.slice(0, 300) : '分享操作失败' }))
        .finally(() => { clearTimeout(timer); active.delete(controller); pending.delete(work); });
      pending.add(work);
      return true;
    },
    async close() { stopped = true; for (const controller of active) controller.abort(); await Promise.allSettled([...pending]); }
  };
}
