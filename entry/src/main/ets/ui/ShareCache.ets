import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'

export async function pruneShareCache(root: string, now: number = Date.now() / 1000): Promise<void> {
  try {
    for (const name of await fileIo.listFile(root)) {
      if (!/^dsh-share-[a-f0-9-]{36}\.dshgo$/i.test(name)) continue
      try {
        const path = root + '/' + name, stat = await fileIo.lstat(path)
        if (stat.isFile() && Number.isFinite(stat.mtime) && now - stat.mtime > 86400) await fileIo.unlink(path)
      } catch { /* A failed expiry must not prevent a new share. */ }
    }
  } catch { /* The system may already have cleared its cache. */ }
}

export async function writeShareCache(root: string, value: string): Promise<string> {
  await pruneShareCache(root)
  const path = root + '/dsh-share-' + util.generateRandomUUID() + '.dshgo'
  if (await fileIo.access(path)) throw new Error('分享缓存已存在，请重试')
  const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.NOFOLLOW | fileIo.OpenMode.WRITE_ONLY)
  let complete = false
  try {
    const bytes = util.TextEncoder.create('utf-8').encodeInto(value)
    if (await fileIo.write(file.fd, bytes.buffer) !== bytes.byteLength) throw new Error('分享文件写入不完整')
    await fileIo.fsync(file.fd)
    complete = true
  } finally {
    try { await fileIo.close(file) } finally { if (!complete) await fileIo.unlink(path).catch(() => {}) }
  }
  return path
}
