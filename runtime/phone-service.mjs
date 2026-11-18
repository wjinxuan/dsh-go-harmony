import { randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync, renameSync, rmSync, lstatSync } from 'node:fs';
import { join } from 'node:path';
const instances = new Map();
const supported = new Set(['screen', 'tap', 'type', 'scroll', 'handoff', 'open', 'clipboard', 'notify', 'key', 'collect', 'intent', 'tap_xy']);
export class PhoneController {
  constructor(root) {
    this.path = join(root, '.harmony-phone-enabled.json'); this.pending = new Map(); this.screens = new Map(); this.enabled = false;
    try { const stat = lstatSync(this.path); if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 1024) throw new Error('Invalid phone setting'); this.enabled = JSON.parse(readFileSync(this.path, 'utf8')).enabled === true; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  setEnabled(enabled) {
    if (typeof enabled !== 'boolean') throw new Error('Invalid phone setting');
    const stage = this.path + '.' + randomUUID() + '.tmp';
    try { writeFileSync(stage, JSON.stringify({ enabled }), { flag: 'wx', mode: 0o600 }); renameSync(stage, this.path); }
    finally { rmSync(stage, { force: true }); }
    this.enabled = enabled; if (!enabled) this.cancelAll('Phone tools were disabled');
  }
  request(tool, args, caller, signal, taskId = caller) {
    if (!this.enabled) return Promise.reject(new Error('Phone control is disabled. Open Phone control and enable model requests.'));
    if (!supported.has(tool)) return Promise.reject(new Error(`Installed-app enumeration requires system_basic GET_BUNDLE_INFO_PRIVILEGED or enterprise-only installed-bundle access; this ordinary phone HAP has neither. No app list was fabricated.`));
    if (args.background === true) return Promise.reject(new Error('Harmony virtual displays require system_basic ACCESS_VIRTUAL_SCREEN; this ordinary phone HAP cannot acquire it. No action was executed.'));
    if (tool === 'intent' && !['dial', 'calendar', 'share', 'navigate', 'settings', 'sms_draft'].includes(args.kind)) return Promise.reject(new Error('Harmony has no public equivalent of the Android clock intent. Alarm/timer reminders require separately approved reminder-agent entitlement; ask the user to create it in Clock.'));
    if (tool === 'collect' && (args.max_pages !== undefined && (!Number.isInteger(args.max_pages) || args.max_pages < 1 || args.max_pages > 30))) return Promise.reject(new Error('max_pages must be 1–30'));
    if (tool === 'key' && !['back','home','recents','notifications'].includes(args.key)) return Promise.reject(new Error('Unsupported system key'));
    if (tool === 'type' && args.submit === true) return Promise.reject(new Error('Automatic submit is unavailable. Fill the field and ask the user to submit it.'));
    if (tool === 'open') {
      if (args.app || typeof args.url !== 'string') return Promise.reject(new Error('Opening a bundle by name needs privileged launch-Want lookup. Use the app’s documented deep link in url instead.'));
      let url; try { url = new URL(args.url); } catch { return Promise.reject(new Error('Invalid app link')); }
      if (['file:','data:','javascript:','intent:','dshgo:','about:'].includes(url.protocol) || url.username || url.password || args.url.length > 8192) return Promise.reject(new Error('Unsafe or oversized link'));
    }
    if (tool === 'clipboard' && ((typeof args.set !== 'string') === (args.get !== true) || (args.set?.length ?? 0) > 8192)) return Promise.reject(new Error('Choose clipboard set text or get, within 8192 characters.'));
    if (tool === 'notify' && (typeof args.title !== 'string' || typeof args.text !== 'string' || args.title.length > 120 || args.text.length > 2000)) return Promise.reject(new Error('Invalid phone notification'));
    if (tool === 'scroll' && !['up', 'down', 'left', 'right'].includes(args.direction)) return Promise.reject(new Error('Invalid scroll direction'));
    if (!caller || signal?.aborted) return Promise.reject(new Error('Phone call was cancelled'));
    if (this.pending.size >= 8) return Promise.reject(new Error('Phone request queue is full'));
    let summary = tool === 'open' ? args.url : tool === 'clipboard' ? typeof args.set === 'string' ? `Write clipboard: ${args.set}` : 'Read clipboard text' : tool === 'notify' ? `${args.title}\n${args.text}` : tool === 'handoff' ? args.reason : tool === 'intent' ? JSON.stringify(args) : tool === 'key' ? `System key: ${args.key}` : args.image === true ? 'Read the screen and send its screenshot to this conversation and model' : 'Read the current screen';
    if (tool === 'tap_xy') {
      const screen = this.screens.get(caller), picture = screen?.image;
      if (!picture || picture.taskId !== taskId || screen.id !== args.observation || Date.now() - screen.createdAt > 30000) return Promise.reject(new Error('No fresh screenshot was actually returned to this task. Read screen with image:true again.'));
      const action = args.action ?? 'tap', duration = args.duration_ms ?? (action === 'long' ? 800 : action === 'swipe' ? 400 : 100);
      if (!['tap','long','swipe'].includes(action) || !Number.isInteger(duration) || duration < 100 || duration > 2000 ||
          ![args.x, ...(action === 'swipe' ? [args.x2] : [])].every(n => Number.isInteger(n) && n >= 0 && n < picture.width) ||
          ![args.y, ...(action === 'swipe' ? [args.y2] : [])].every(n => Number.isInteger(n) && n >= 0 && n < picture.height)) return Promise.reject(new Error('Screenshot coordinates or gesture duration are invalid'));
      summary = `${screen.bundle} · ${action} (${args.x}, ${args.y})${action === 'swipe' ? ` → (${args.x2}, ${args.y2})` : ''}`;
      args = { ...args, action, screen: screen.id, duration, width: picture.viewportWidth, height: picture.viewportHeight,
        x: Math.floor(args.x * picture.viewportWidth / picture.width), y: Math.floor(args.y * picture.viewportHeight / picture.height),
        x2: Math.floor((args.x2 ?? args.x) * picture.viewportWidth / picture.width), y2: Math.floor((args.y2 ?? args.y) * picture.viewportHeight / picture.height) };
      delete screen.image; // Every returned screenshot grants at most one coordinate attempt, including cancelled attempts.
    }
    if (['tap', 'type', 'scroll', 'collect', 'key'].includes(tool)) {
      const screen = this.screens.get(caller);
      if (tool === 'key' && screen && !args.screen) args = { ...args, screen: screen.id };
      if (!screen || screen.id !== args.screen || Date.now() - screen.createdAt > 30000) return Promise.reject(new Error('The screen belongs to another call or has expired. Read the screen again.'));
      if (tool === 'scroll' && args.id === undefined) {
        const action = args.direction === 'up' ? 'scrollBackward' : 'scrollForward';
        const target = screen.nodes.find(node => node.actions.includes(action));
        if (!target) return Promise.reject(new Error('No scrollable node was returned; read the screen or hand off to the user.'));
        args = { ...args, id: target.id };
      }
      if (tool === 'collect') args = { ...args, id: args.list, initial: structuredClone(screen), max_pages: args.max_pages ?? 10 };
      const target = screen.nodes.find(node => node.id === (tool === 'key' ? 0 : args.id));
      if (!target) return Promise.reject(new Error('The requested node was not in the returned screen.'));
      if (tool === 'collect' && !target.actions.includes('scrollForward')) return Promise.reject(new Error('The requested list is not scrollable'));
      summary = `${tool === 'key' ? args.key + ' · ' : tool === 'collect' ? `Collect up to ${args.max_pages} pages · ` : ''}${screen.bundle} · #${target.id} ${target.type || ''}\n${String(target.text || '').slice(0, 500)}${tool === 'type' ? '\nNew text: ' + args.text : ''}`;
    }
    const id = randomUUID(), expires = Date.now() + (tool === 'handoff' ? 600000 : 30000);
    return new Promise((resolve, reject) => {
      const dispose = () => { clearTimeout(timer); signal?.removeEventListener('abort', cancel); this.pending.delete(id); };
      const cancel = () => { dispose(); reject(new Error('Phone call was cancelled')); };
      const timer = setTimeout(() => { dispose(); reject(new Error('Phone confirmation or execution timed out; no success was reported')); }, expires - Date.now());
      this.pending.set(id, { id, tool, args: structuredClone(args), caller, taskId, expires, summary: String(summary || '').slice(0, 2000),
        finish: (value, error) => { dispose(); if (error) reject(new Error(String(error).slice(0, 300))); else {
          const screen = tool === 'screen' ? value : value?.screen;
          if (screen?.id && Array.isArray(screen.nodes)) {
            if (this.screens.size >= 64) this.screens.delete(this.screens.keys().next().value);
            this.screens.set(caller, { id: screen.id, nodes: screen.nodes, bundle: screen.bundle, truncated: screen.truncated === true, createdAt: Date.now() });
          }
          else if (tool !== 'handoff') this.screens.delete(caller);
          resolve(value);
        } }
      }); signal?.addEventListener('abort', cancel, { once: true });
    });
  }
  next() { const item = this.pending.values().next().value; return { enabled: this.enabled, request: item ? { id: item.id, taskId: item.taskId, tool: item.tool, args: item.args, summary: item.summary, expires: item.expires } : null }; }
  observeImage(caller, taskId, screenId, image) {
    const screen = this.screens.get(caller);
    if (!screen || screen.id !== screenId || !['width','height','viewportWidth','viewportHeight'].every(key => Number.isInteger(image[key]) && image[key] > 0 && image[key] <= 16384)) throw new Error('Screenshot geometry is invalid');
    screen.image = { taskId, width: image.width, height: image.height, viewportWidth: image.viewportWidth, viewportHeight: image.viewportHeight };
  }
  complete(id, value, error) { const item = this.pending.get(id); if (!item) throw new Error('Phone request is no longer active'); item.finish(value, error); }
  cancelAll(reason) { for (const item of [...this.pending.values()]) item.finish(undefined, reason); this.screens.clear(); }
}
export function phoneController(root = process.env.DSH_HOME) { if (!instances.has(root)) instances.set(root, new PhoneController(root)); return instances.get(root); }
export function createPhoneHandler(root) {
  const controller = phoneController(root);
  return { handle(request, response) {
    if (!['/phone/pending', '/phone/enable', '/phone/complete', '/phone/stop'].includes(request.url)) return false;
    const send = (status, value) => response.writeHead(status, { 'content-type': 'application/json' }).end(JSON.stringify(value));
    if (request.url === '/phone/pending' && request.method === 'GET') { send(200, controller.next()); return true; }
    if (request.method !== 'POST') { send(405, { error: 'Method not allowed' }); return true; }
    let body = '', size = 0; request.on('data', chunk => { size += chunk.length; if (size <= 3000000) body += chunk; });
    request.on('end', () => { try {
      if (size > 3000000) throw new Error('Phone response too large'); const value = JSON.parse(body || '{}');
      if (request.url === '/phone/enable') controller.setEnabled(value.enabled);
      else if (request.url === '/phone/stop') controller.setEnabled(false);
      else controller.complete(value.id, value.value, value.error);
      send(200, controller.next());
    } catch (error) { send(400, { error: String(error.message).slice(0, 300) }); } }); return true;
  }, async close() { controller.cancelAll('Local engine stopped'); instances.delete(root); } };
}
