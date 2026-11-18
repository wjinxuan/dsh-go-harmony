// Dollar rules follow the fixed upstream math_syntax.dart, including price and code exclusions.
export interface MathPart { text: string; math: boolean; display: boolean; pending: boolean }

function dollarCloser(text: string, open: number): number {
  if (!text[open + 1] || /[\s$]/.test(text[open + 1]) || text[open - 1] === '$') return -1;
  let end = open + 1;
  while (end < text.length) {
    if (text[end] === '\n' || text[end] === '`') return -1;
    if (text[end] === '\\') { end += 2; continue; }
    if (text[end] === '$') break;
    end++;
  }
  if (end >= text.length || text[end + 1] === '$' || /\s/.test(text[end - 1]) || /[0-9]/.test(text[end + 1] || '')) return -1;
  const body = text.slice(open + 1, end);
  return /^[0-9]/.test(body) && /\s/.test(body) && !/[\\^_{}=+<>]/.test(body) ? -1 : end;
}

export function mathParts(text: string, streaming: boolean = false): MathPart[] {
  const parts: MathPart[] = [];
  let from = 0;
  let at = 0;
  while (at < text.length) {
    const lineStart = at === 0 || text[at - 1] === '\n';
    if (lineStart) {
      const opening = /^[ \t]*(?:>[ \t]?)*[ \t]*(`{3,}|~{3,})[^\n]*\n?/.exec(text.slice(at));
      if (opening) {
        const fence = opening[1];
        const close = new RegExp('^[ \\t]*(?:>[ \\t]?)*[ \\t]*' + fence[0] + '{' + fence.length + ',}[ \\t]*$', 'm');
        const tail = text.slice(at + opening[0].length);
        const match = close.exec(tail);
        at = match ? at + opening[0].length + match.index + match[0].length : text.length;
        continue;
      }
    }
    if (text[at] === '`') {
      let run = 1;
      while (text[at + run] === '`') run++;
      let end = at + run;
      let found = false;
      const blank = /\n[ \t>]*\n/.exec(text.slice(end));
      const limit = blank ? end + blank.index : text.length;
      while (end < limit) {
        const next = text.indexOf('`', end);
        if (next < 0 || next >= limit) break;
        let size = 1;
        while (text[next + size] === '`') size++;
        if (size === run) { at = next + size; found = true; break; }
        end = next + size;
      }
      if (!found) at += run;
      continue;
    }
    let width = 0;
    let display = false;
    let close = '';
    let end = -1;
    if (text.startsWith('$$', at)) { width = 2; display = true; close = '$$'; }
    else if (text.startsWith('\\[', at)) { width = 2; display = true; close = '\\]'; }
    else if (text.startsWith('\\(', at)) { width = 2; close = '\\)'; }
    else if (text[at] === '$') { width = 1; end = dollarCloser(text, at); }
    else if (text[at] === '\\') { at += 2; continue; }
    if (!width) { at++; continue; }
    if (close) {
      end = text.indexOf(close, at + width);
      while (end > 0 && text[end - 1] === '\\') end = text.indexOf(close, end + close.length);
      if (display && end >= 0 && /^\s*(?:>[ \t]?)*[ \t]*(`{3,}|~{3,})/m.test(text.slice(at + width, end))) end = -1;
    }
    const pending = end < 0 && display && streaming && !!text.slice(at + width).trim();
    if ((end >= 0 && text.slice(at + width, end).trim()) || pending) {
      if (at > from) parts.push({ text: text.slice(from, at), math: false, display: false, pending: false });
      parts.push({ text: text.slice(at + width, pending ? text.length : end), math: true, display, pending });
      at = pending ? text.length : end + (close ? close.length : 1);
      from = at;
    } else at += width;
  }
  if (from < text.length) parts.push({ text: text.slice(from), math: false, display: false, pending: false });
  return parts;
}

export function mathBlockSource(text: string, streaming: boolean = false): string {
  return mathParts(text, streaming).map((part: MathPart) => {
    if (!part.math || !part.display) return part.math ? '\\(' + part.text + '\\)' : part.text;
    let fence = '```';
    while (part.text.includes(fence)) fence += '`';
    return '\n\n' + fence + (part.pending ? 'dsh-math-pending' : 'dsh-math') + '\n' + part.text.trim() + '\n' + fence + '\n\n';
  }).join('');
}
