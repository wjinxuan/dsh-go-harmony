import { conversation } from './share-codec.mjs';
import { redactConversation } from './share-redact.mjs';

export function exportRounds(source) {
  const messages = Array.isArray(source.messages) ? source.messages : [], turns = source.turns || [];
  return messages.filter(m => m.role === 'user' && Number.isSafeInteger(m.seq)).map((m, index) => {
    const turn = turns.find(t => t.startSeq <= m.seq && (t.endSeq === undefined || t.endSeq >= m.seq));
    return { index: index + 1, startSeq: turn?.startSeq ?? m.seq, prompt: m.text.replace(/\s+/g, ' ').slice(0, 160) };
  });
}

export function exportConversation(source, options = {}, now = Date.now()) {
  if (!source || !Array.isArray(source.messages) || !Array.isArray(source.records) || !Array.isArray(source.tools) ||
    source.messages.length + source.records.length + source.tools.length > 80000) throw new Error('会话快照无效或过大');
  const rounds = exportRounds(source), only = Array.isArray(options.only) ? new Set(options.only) : undefined;
  if (only && (!only.size || [...only].some(id => typeof id !== 'string'))) throw new Error('请至少选择一条消息');
  const picked = source.messages.filter(m => only?.has(m.id));
  if (only && picked.length !== only.size) throw new Error('选中的消息已经发生变化，请重新选择');
  const roundOf = seq => Math.max(0, rounds.findLastIndex(r => r.startSeq <= seq));
  let from = options.from ?? 1, to = options.to ?? rounds.length;
  if (only) { const indexes = picked.map(m => roundOf(m.seq) + 1); from = Math.min(...indexes); to = Math.max(...indexes); }
  if (!Number.isInteger(from) || !Number.isInteger(to) || from < 1 || to < from || to > rounds.length) throw new Error('分享回合范围无效');
  const pickedRounds = new Set(picked.map(m => roundOf(m.seq))), replyRounds = new Set(picked.filter(m => m.role === 'assistant').map(m => roundOf(m.seq)));
  const inRange = seq => only ? pickedRounds.has(roundOf(seq)) : seq >= (from === 1 ? -Infinity : rounds[from - 1].startSeq) && seq < (rounds[to]?.startSeq ?? Infinity);
  const workIn = seq => only ? replyRounds.has(roundOf(seq)) : inRange(seq);
  const times = new Map(source.records.map(r => [r.seq, r.time])), modelSpans = new Map(), toolSpans = new Map();
  const timed = [], push = (seq, at, entry, end) => {
    if (!Number.isFinite(at) || at < 0) return;
    const d = Number.isFinite(end) && end >= at ? end - at : undefined;
    timed.push({ seq, at, entry: { ...entry, ...(d === undefined ? {} : { d }) } });
  };
  for (const turn of source.turns || []) {
    if (inRange(turn.startSeq)) push(turn.startSeq, turn.start, { type: 'turn', end: turn.reason, steps: turn.steps,
      tokens: turn.spans?.reduce((sum, span) => sum + (span.usage?.totalTokens ?? (span.usage?.inputTokens || 0) + (span.usage?.outputTokens || 0)), 0) }, turn.end);
    for (const span of turn.spans || []) {
      if (span.kind === 'model') modelSpans.set(span.seq, span);
      if (span.kind === 'tool' && span.callId) toolSpans.set(span.callId, span);
    }
  }
  let lastModel;
  for (const m of source.messages) {
    if (!Number.isInteger(m.seq) || !(only ? only.has(m.id) : inRange(m.seq))) continue;
    if (m.role === 'user') {
      const content = m.content || [], images = [], files = [];
      for (const part of content) {
        const ref = part.attachment;
        if (!ref) continue;
        if (part.type === 'image' && options.images !== false) {
          const image = source.images?.[ref.attachmentId];
          if (image) images.push({ id: image.id, w: image.w, h: image.h, name: ref.name });
        } else if (part.type === 'file') files.push({ name: ref.name || '附件', size: ref.bytes });
      }
      push(m.seq, times.get(m.seq), { type: 'user', text: m.text, images, files });
    } else if (m.role === 'assistant' && !m.streaming) {
      const span = modelSpans.get(m.seq), model = m.model || span?.model;
      if (model) lastModel = model;
      push(m.seq, span?.firstToken ?? span?.start ?? times.get(m.seq), { type: 'reply', text: m.text.trimEnd(),
        think: options.thinking === false ? undefined : m.reasoning?.trim(), model, cut: span?.cutShort === true }, span?.lastToken ?? span?.end ?? times.get(m.seq));
    }
  }
  if (options.tools !== false) for (const tool of source.tools) {
    if (!workIn(tool.seq) || tool.result === undefined) continue;
    let args;
    try { args = JSON.parse(tool.arguments || '{}'); } catch { continue; }
    const span = toolSpans.get(tool.callId);
    push(tool.seq, span?.start ?? times.get(tool.seq), { type: 'tool', name: tool.name, args,
      summary: tool.name, status: ['denied', 'cancelled'].includes(span?.outcome) ? span.outcome : tool.isError ? 'failed' : 'ok',
      result: options.toolOutput === false ? undefined : tool.result, error: tool.failure?.reason }, span?.end);
  }
  for (const notice of source.notices || []) if (inRange(notice.seq)) push(notice.seq, times.get(notice.seq), { type: 'notice', kind: notice.kind, text: notice.text });
  if (!only) for (const command of source.commands || []) if (command.done && inRange(command.seq)) {
    push(command.seq, times.get(command.seq), { type: 'command', line: '/' + command.name + (command.args ? ' ' + command.args : ''), ok: command.success !== false, text: command.text });
  }
  if (options.tools !== false) for (const record of source.records) {
    if (!workIn(record.seq)) continue;
    if (record.type === 'todo/write') push(record.seq, record.time, { type: 'todos', items: (record.data.todos || []).map(t => ({ text: t.content || t.text, status: t.status })) });
    else if (record.type === 'goal/change') push(record.seq, record.time, { type: 'goal',
      text: record.data.operation === 'clear' ? undefined : record.data.goal?.objective,
      phase: record.data.operation === 'clear' ? undefined : record.data.goal?.phase });
  }
  timed.sort((a, b) => a.seq - b.seq);
  const origin = timed.length ? Math.min(...timed.map(t => t.at)) : now;
  const body = { v: 2, kind: 'conversation', schema: 1, title: source.title || '对话', model: lastModel || source.model,
    app: 'dsh-go Harmony', start: new Date(origin).toISOString(), created: new Date(now).toISOString(),
    range: only || from !== 1 || to !== rounds.length ? { from, to, of: rounds.length } : undefined,
    include: { thinking: options.thinking !== false, tools: options.tools !== false && options.toolOutput !== false },
    entries: timed.map(t => ({ ...t.entry, t: Math.max(0, Math.min(2 ** 40, t.at - origin)) })) };
  return conversation(redactConversation(conversation(body)));
}
