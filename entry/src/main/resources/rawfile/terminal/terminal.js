'use strict';

const view = document.getElementById('terminal');
const fontFamily = 'ui-monospace, Menlo, Consolas, monospace';
const terminal = new Terminal({
  cols: 80, rows: 24, fontFamily, fontSize: 13, scrollback: 1000,
  cursorBlink: true, screenReaderMode: true, disableStdin: true,
  linkHandler: { activate() {} },
  theme: { background: '#12161e', foreground: '#e3e9f3', cursor: '#b8cdfb', selectionBackground: '#52678f' }
});
const fit = new FitAddon.FitAddon();
terminal.loadAddon(fit);
terminal.open(view);
terminal.textarea?.setAttribute('aria-label', '终端输入');

let modifier = '';
let live = false;
let framePending = false;
let generation = 0;
let inputRevision = -1;
let pending = Promise.resolve();
let buffered = 0;

function reportSize() {
  if (framePending) return;
  framePending = true;
  requestAnimationFrame(() => {
    framePending = false;
    const size = fit.proposeDimensions();
    if (size) window.terminalBridge?.size(size.cols, size.rows);
  });
}

new ResizeObserver(reportSize).observe(view);
function setState(cols, rows, writable) {
  terminal.resize(cols, rows);
  live = writable;
  terminal.options.disableStdin = !live;
}

function send(data) {
  if (modifier && data.length === 1) {
    if (modifier === 'alt') data = '\x1b' + data;
    else if (/^[a-z]$/i.test(data) || '@[\\]^_'.includes(data)) data = String.fromCharCode(data.toUpperCase().charCodeAt(0) & 31);
    else if (data === ' ' || data === '2') data = '\x00';
    else if (data === '?') data = '\x7f';
    modifier = '';
    window.terminalBridge?.modifierUsed();
  }
  window.terminalBridge?.input(data, inputRevision);
}

window.terminalDisplay = {
  clear() {
    generation++;
    inputRevision = -1;
    modifier = '';
    this.lock();
    pending = pending.then(() => { terminal.reset(); terminal.clear(); });
  },
  snapshot(cols, rows, screen, writable, revision) {
    this.clear();
    const owner = generation;
    pending = pending.then(() => {
      if (owner !== generation) return;
      setState(cols, rows, false);
      return new Promise(resolve => terminal.write(screen, () => {
        if (owner === generation) {
          inputRevision = revision;
          setState(cols, rows, writable);
          reportSize();
        }
        resolve();
      }));
    });
  },
  state(cols, rows, writable) {
    if (!writable) this.lock();
    const owner = generation;
    pending = pending.then(() => { if (owner === generation) setState(cols, rows, writable); });
  },
  output(data) {
    if (buffered + data.length > 2097152) { this.lock(); window.terminalBridge?.displayOverflow(); return; }
    const owner = generation;
    buffered += data.length;
    pending = pending.then(() => owner === generation ? new Promise(resolve => terminal.write(data, resolve)) : undefined)
      .finally(() => { buffered -= data.length; });
  },
  lock() { live = false; terminal.options.disableStdin = true; },
  modifier(key) { modifier = key; },
  paste(data) { if (live) terminal.paste(data); },
  key(name) {
    if (!live) return;
    const arrows = { up: 'A', down: 'B', right: 'C', left: 'D' };
    const keys = { esc: '\x1b', tab: '\t', enter: '\r', pipe: '|', tilde: '~', slash: '/', dash: '-' };
    const data = keys[name] ?? (arrows[name] ? `\x1b${terminal.modes.applicationCursorKeysMode ? 'O' : '['}${arrows[name]}` : '');
    if (data) send(data);
  }
};

terminal.onData(send);
reportSize();
