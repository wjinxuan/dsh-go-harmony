'use strict';
let generation = 0;
window.renderDiagram = async (source, dark, background, foreground, revision) => {
  const current = ++generation;
  document.body.style.background = background; document.body.style.color = foreground;
  const root = document.getElementById('chart'); root.replaceChildren();
  try {
    mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark ? 'dark' : 'default',
      maxTextSize: 50000, maxEdges: 500, suppressErrorRendering: true,
      secure: ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'maxEdges', 'suppressErrorRendering', 'dompurifyConfig'] });
    const result = await mermaid.render('dsh-chart-' + current, source);
    if (current !== generation) return;
    root.innerHTML = result.svg;
    // No diagram navigation or embedded external media, including malicious init directives.
    root.querySelectorAll('a').forEach(node => { node.removeAttribute('href'); node.removeAttribute('xlink:href'); });
    root.querySelectorAll('image,iframe,object,embed,script').forEach(node => node.remove());
    window.renderBridge?.status('ready', revision);
  } catch {
    if (current === generation) { root.replaceChildren(); window.renderBridge?.status('syntax', revision); }
  }
};
document.addEventListener('click', event => { if (event.target.closest('a')) event.preventDefault(); });
