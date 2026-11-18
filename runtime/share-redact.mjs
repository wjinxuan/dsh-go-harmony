const mark = '••••••';
const placeholder = /^(?:\$|<|\{|\*|•|%|xxx)/i;
const secretName = /(?:^|[_-])(?:api[_-]?key|apikey|secret|token|password|passwd|access[_-]?key|private[_-]?key|auth[_-]?token|client[_-]?secret)$/i;
const formats = /sk-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{35}|gh[opusr]_[A-Za-z0-9]{36,}|github_pat_\w{22,}|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{36,}|hf_[A-Za-z0-9]{30,}|(?:AKIA|ASIA)[A-Z0-9]{16}\b|LTAI[A-Za-z0-9]{12,20}\b|AKID[A-Za-z0-9]{28,36}\b|xox[abprs]-[A-Za-z0-9-]{10,}|[sr]k_(?:live|test)_[A-Za-z0-9]{16,}|whsec_[A-Za-z0-9]{24,}|eyJ[A-Za-z0-9_-]{8,2048}\.eyJ[A-Za-z0-9_-]{8,2048}\.[A-Za-z0-9_-]{8,2048}/g;
export function redactText(text) {
  return text.replace(/(\b(?:proxy-)?authorization["']?\s*[:=]\s*["']?(?:Bearer|Basic)\s+)([A-Za-z0-9._~+/=-]+)/gi, '$1' + mark)
    .replace(/(-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----)([\s\S]*?)(-----END [A-Z0-9 ]*PRIVATE KEY-----)/g,
      (_, begin, value, end) => begin + value.replace(/[^\r\n]/gu, '•') + end)
    .replace(/([a-z][a-z0-9+.-]*:\/\/[^\s/:@?#]+:)([^\s/@?#]+)(@)/gi, (_, prefix, value, end) => prefix + '•'.repeat([...value].length) + end)
    .replace(formats, value => value.startsWith('sk-') && !/\d/.test(value.slice(3, 259)) ? value : value.slice(0, 8) + '•'.repeat([...value.slice(8)].length))
    .replace(/(?<![A-Za-z0-9])((?:[A-Za-z0-9]+[_-])*(?:api[_-]?key|apikey|secret|token|password|passwd|access[_-]?key|private[_-]?key|auth[_-]?token|client[_-]?secret)"?'?)(\s*[:=]\s*["']?)([^\s"',;)}]{6,})/gi,
      (all, key, separator, value) => placeholder.test(value) ? all : key + separator + (value.length > 12 ? value.slice(0, 4) : '') + mark)
    .replace(/(?<![\w.~-])(?:\/home|\/Users)\/[A-Za-z0-9._-]+(?=\/|\b)/g, '~')
    .replace(/(?<!\w)[A-Za-z]:\\Users\\[^\\/\s"<>|:*?]+/gi, '~')
    .replace(/\/data\/(?:user\/\d+|data)\/[A-Za-z0-9._]+(?=\/|\b)/g, '…')
    .replace(/\/data\/storage\/el[0-9]+\/base(?=\/|\b)/g, '…');
}
export function cutText(text, max) {
  if (text.length <= max) return { text, omitted: 0 };
  let a = Math.round(max * .6), b = text.length - (max - a);
  if (/[\uD800-\uDBFF]/.test(text[a - 1])) a--;
  if (/[\uDC00-\uDFFF]/.test(text[b])) b++;
  return { text: text.slice(0, a) + '\n…\n' + text.slice(b), omitted: b - a };
}
export function redactJson(value, max = 2000, depth = 0) {
  if (depth > 32) throw new Error('工具参数嵌套过深，无法安全分享');
  if (typeof value === 'string') return cutText(redactText(value), max).text;
  if (Array.isArray(value)) return value.slice(0, 200).map(v => redactJson(v, max, depth + 1));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).slice(0, 200).map(([key, v]) =>
    [redactText(key), secretName.test(key) && typeof v === 'string' && !placeholder.test(v) ? mark : redactJson(v, max, depth + 1)]));
  return value;
}
export function markdownWithoutImages(markdown) {
  let fence;
  return markdown.split('\n').map(line => {
    if (fence) { if (line.trimStart().startsWith(fence)) fence = undefined; return line; }
    const open = /^\s{0,3}(`{3,}|~{3,})/.exec(line);
    if (open) { fence = open[1].slice(0, 3); return line; }
    return line.replace(/!\[([^\]\n]*)\]\((?:[^()\s]|\([^()\s]*\))+(?:\s+"[^"\n]*")?\)/g, (_, alt) => alt.trim() ? '〔' + alt.trim() + '〕' : '');
  }).join('\n');
}
export function redactConversation(body) {
  return { ...body, title: redactText(body.title), model: body.model ? redactText(body.model) : undefined,
    entries: body.entries.map(e => {
      const result = { ...e };
      for (const key of ['text', 'think', 'plain', 'summary', 'error', 'line', 'model', 'name', 'verb']) {
        if (typeof result[key] === 'string') result[key] = redactText(result[key]);
      }
      if (e.type === 'reply') result.text = markdownWithoutImages(result.text);
      if (e.type === 'tool') {
        result.args = redactJson(e.args);
        if (typeof e.result === 'string') { const cut = cutText(redactText(e.result), 2400); result.result = cut.text; result.more = (e.more || 0) + cut.omitted; }
      }
      if (e.type === 'user') {
        result.files = e.files?.map(f => ({ ...f, name: redactText(f.name) }));
        result.images = e.images?.map(i => ({ ...i, name: i.name ? redactText(i.name) : undefined }));
      }
      if (e.type === 'todos') result.items = e.items.map(i => ({ ...i, text: redactText(i.text) }));
      return result;
    }) };
}
