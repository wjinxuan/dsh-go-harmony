'use strict';
let revision = 0;
function report() { window.renderBridge?.height(Math.ceil(document.getElementById('content').getBoundingClientRect().height), revision); }
window.renderMath = (runs, options, next) => {
  revision = next;
  const root = document.getElementById('content');
  root.replaceChildren();
  root.style.fontSize = options.size + 'px'; root.style.color = options.color;
  root.style.fontWeight = options.bold ? '500' : '400'; root.style.setProperty('--accent', options.accent);
  for (const run of runs) {
    const node = document.createElement(run.kind === 'link' ? 'span' : run.kind === 'code' ? 'code' : 'span');
    // enum values are provided by the native caller as semantic names, never HTML.
    if (run.kind === 'math') {
      try { katex.render(run.text, node, { displayMode: options.display, throwOnError: true, trust: false,
        strict: 'ignore', maxExpand: 1000, maxSize: 20, output: 'htmlAndMathml' }); }
      catch { node.textContent = run.text; node.style.fontFamily = 'monospace'; }
    } else {
      node.textContent = run.text;
      if (run.kind === 'strong') node.style.fontWeight = '500';
      if (run.kind === 'emphasis') node.style.fontStyle = 'italic';
      if (run.kind === 'code') { node.style.fontFamily = 'monospace'; node.style.background = options.code; }
      if (run.kind === 'link') {
        node.style.color = options.accent; node.style.textDecoration = 'underline';
        node.setAttribute('role', 'link'); node.tabIndex = 0;
        const open = () => window.renderBridge?.link(run.url, revision);
        node.addEventListener('click', open); node.addEventListener('keydown', event => { if (event.key === 'Enter') open(); });
      }
    }
    root.append(node);
  }
  report(); document.fonts.ready.then(report);
};
new ResizeObserver(report).observe(document.getElementById('content'));
