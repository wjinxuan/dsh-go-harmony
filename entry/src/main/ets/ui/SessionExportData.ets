export const SESSION_ARCHIVE_UTD: string = 'general.zip-archive'
export const EXPORT_CACHE_MAX_AGE_SECONDS: number = 24 * 60 * 60

export function sessionArchiveName(sessionId: string): string {
  if (!sessionId || sessionId.length > 256 || /[\x00-\x1f\x7f]/.test(sessionId)) throw new Error('无效的对话编号')
  return `dsh-session-${sessionId.replace(/[^A-Za-z0-9_-]/g, '_')}.zip`
}

export function isStaleExportFolder(name: string, mtime: number, now: number): boolean {
  return /^export-[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(name) &&
    Number.isFinite(mtime) && mtime > 0 && now - mtime > EXPORT_CACHE_MAX_AGE_SECONDS
}
