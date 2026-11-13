import { array, DshSessionRecord, DshTokenUsage, DshTurnTrace, number, object, string, WireObject } from '../dsh/DshWire';

export interface SessionDiffLine {
  marker: string;
  text: string;
}

export interface SessionFileChange {
  path: string;
  created: boolean;
  edits: number;
  added: number;
  removed: number;
  turn: number;
  lines: SessionDiffLine[];
}

interface FileTool {
  name: string;
  args: WireObject;
}

function lines(text: string): string[] {
  const normalized = text.replace(/\r\n/g, '\n');
  return normalized ? normalized.replace(/\n$/, '').split('\n') : [];
}

function diff(before: string, after: string): SessionDiffLine[] {
  const oldLines = lines(before);
  const newLines = lines(after);
  const result: SessionDiffLine[] = [];
  let head = 0;
  while (head < oldLines.length && head < newLines.length && oldLines[head] === newLines[head]) {
    result.push({ marker: ' ', text: oldLines[head] });
    head++;
  }
  let oldTail = oldLines.length;
  let newTail = newLines.length;
  while (oldTail > head && newTail > head && oldLines[oldTail - 1] === newLines[newTail - 1]) {
    oldTail--;
    newTail--;
  }
  const oldCount = oldTail - head;
  const newCount = newTail - head;
  const stride = newCount + 1;
  const cells = (oldCount + 1) * stride;
  const matrix = new Uint32Array(cells <= 160000 ? cells : 0);
  if (matrix.length) {
    for (let left = oldCount - 1; left >= 0; left--) {
      for (let right = newCount - 1; right >= 0; right--) {
        const index = left * stride + right;
        matrix[index] = oldLines[head + left] === newLines[head + right] ? 1 + matrix[index + stride + 1] :
          Math.max(matrix[index + stride], matrix[index + 1]);
      }
    }
  }
  let left = 0;
  let right = 0;
  while (left < oldCount || right < newCount) {
    if (left < oldCount && right < newCount && oldLines[head + left] === newLines[head + right]) {
      result.push({ marker: ' ', text: oldLines[head + left++] });
      right++;
    } else if (left < oldCount && (right >= newCount || !matrix.length ||
      matrix[(left + 1) * stride + right] >= matrix[left * stride + right + 1])) {
      result.push({ marker: '-', text: oldLines[head + left++] });
    } else {
      result.push({ marker: '+', text: newLines[head + right++] });
    }
  }
  for (let index = oldTail; index < oldLines.length; index++) {
    result.push({ marker: ' ', text: oldLines[index] });
  }
  return result;
}

function resultDiff(tool: FileTool, meta: WireObject): SessionDiffLine[] {
  const result: SessionDiffLine[] = [];
  for (const raw of array(meta['diffs'])) {
    const block = object(raw);
    if (typeof block['newText'] === 'string') {
      if (result.length) result.push({ marker: '@', text: '下一处变更' });
      for (const line of diff(string(block['oldText']), string(block['newText']))) result.push(line);
    }
  }
  if (result.length) return result;
  const command = string(tool.args['command']);
  const previous = tool.args[tool.name === 'edit' ? 'old_string' : 'old_str'];
  const replacement = tool.args[tool.name === 'edit' ? 'new_string' : 'new_str'];
  if ((tool.name === 'edit' || command === 'str_replace') &&
    typeof previous === 'string' && typeof replacement === 'string') {
    return diff(previous, replacement);
  }
  if (command === 'insert') return diff('', string(replacement));
  if (tool.name === 'write' && meta['operation'] === 'create') return diff('', string(tool.args['content']));
  if (command === 'create') return diff('', string(tool.args['file_text']));
  return result;
}

export function sessionFileChanges(records: DshSessionRecord[]): SessionFileChange[] {
  const calls: Map<string, FileTool> = new Map();
  const changes: Map<string, SessionFileChange> = new Map();
  for (const record of records) {
    const data = record.data;
    if (record.type === 'tool/call') {
      const name = string(data['name']);
      if (['write', 'edit', 'str_replace_editor'].includes(name)) {
        try {
          const tool: FileTool = { name: name, args: object(JSON.parse(string(data['arguments'])) as Object) };
          calls.set(string(data['callId']), tool);
        } catch {
          // Ignore incomplete tool arguments.
        }
      }
    } else if (record.type === 'tool/result') {
      const message = object(data['message']);
      const callId = string(message['toolCallId']);
      const tool = calls.get(callId);
      calls.delete(callId);
      if (!tool || message['isError'] === true || data['error'] || data['failure']) continue;
      const meta = object(data['meta']);
      const path = (string(tool.args['file_path']) || string(tool.args['path']) || string(meta['path']))
        .replace(/^(?:\.\/)+/, '').replace(/\/{2,}/g, '/');
      if (!path) continue;
      const edits = resultDiff(tool, meta);
      const added = edits.filter((item: SessionDiffLine) => item.marker === '+').length;
      const removed = edits.filter((item: SessionDiffLine) => item.marker === '-').length;
      const created = meta['operation'] === 'create' ||
        (tool.name === 'str_replace_editor' && tool.args['command'] === 'create');
      if (!added && !removed && !created) continue;
      const turn = number(data['turn'], 0);
      const previous = changes.get(path);
      if (previous) {
        if (previous.lines.length && edits.length) previous.lines.push({ marker: '@', text: '下一次变更' });
        for (const line of edits) previous.lines.push(line);
        previous.edits++;
        previous.added += added;
        previous.removed += removed;
        previous.turn = turn;
      } else {
        changes.set(path, { path: path, created: created, edits: 1, added: added, removed: removed,
          turn: turn, lines: edits });
      }
    }
  }
  return Array.from(changes.values());
}

export function turnTotalTokens(turn: DshTurnTrace): number {
  let sum = 0;
  for (const span of turn.spans) {
    const usage: DshTokenUsage | undefined = span.usage;
    if (usage) sum += usage.totalTokens ?? usage.inputTokens + usage.outputTokens;
  }
  return sum;
}

export function goalRoundCap(value: string): number | undefined {
  const text = value.trim();
  if (!text) return undefined;
  const rounds = Number(text);
  if (!/^\d+$/.test(text) || !Number.isSafeInteger(rounds) || rounds < 1) {
    throw new Error('回合上限必须为正整数。');
  }
  return rounds;
}
