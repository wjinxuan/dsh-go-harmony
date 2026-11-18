import { join } from 'node:path';
import { FsError } from '@deepseek-ai/dsh-fs';

const fileReferencePath = /^([a-f0-9]{2})\/([a-f0-9]{64})\/([^/]+)$/;

export function attachmentPath(path) {
  const prefix = join(process.env.DSH_HOME, 'attachments', 'v1', 'files') + '/';
  return path.startsWith(prefix) ? fileReferencePath.exec(path.slice(prefix.length)) : null;
}

export async function sessionAttachmentRead(ctx, exec, path) {
  const root = join(process.env.DSH_HOME, 'attachments', 'v1', 'files');
  if (!path.startsWith(`${root}/`)) return undefined;
  const denied = () => new FsError('This file was not attached to the current session.', 'FS_SANDBOX_DENIED');
  const match = attachmentPath(path);
  if (!match || !exec.agent || !match[2].startsWith(match[1])) throw denied();
  const { signal } = exec;
  signal?.throwIfAborted();
  const observation = await ctx.sessionQuery.observeSession(exec.agent.id, { signal });
  try {
    for (const event of observation.events) {
      if (event?.type !== 'user/message' || event.data.source?.kind !== 'user') continue;
      const part = event.data.content?.find(item => item.type === 'file' &&
        item.attachment?.attachmentId === `sha256:${match[2]}` && item.attachment.name === match[3]);
      if (!part || ctx.attachments.fileHostPath(part.attachment) !== path) continue;
      return readAttachmentText(ctx.attachments.readFileStream(part.attachment, signal));
    }
  } finally { observation[Symbol.dispose](); }
  throw denied();
}

async function* readAttachmentText(source) {
  const decoder = new TextDecoder('utf-8', { fatal: true });
  try {
    for await (const bytes of source) {
      const text = decoder.decode(bytes, { stream: true });
      if (text.includes('\0')) throw new TypeError('Binary data');
      yield text;
    }
    yield decoder.decode();
  } catch (error) {
    if (error instanceof TypeError) throw new FsError('This attachment is not UTF-8 text.', 'FS_NOT_TEXT');
    throw error;
  }
}
