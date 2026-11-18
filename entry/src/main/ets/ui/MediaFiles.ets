import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { DshClient } from '../dsh/DshClient'
import { readMediaFile } from '../dsh/MediaApi'

const cleanedRoots: Set<string> = new Set()

export async function cacheMediaFile(client: DshClient, sessionId: string, remote: string, cacheDir: string,
  video: boolean, current: () => boolean): Promise<string> {
  if (!cleanedRoots.has(cacheDir)) {
    cleanedRoots.add(cacheDir)
    const names = await fileIo.listFile(cacheDir).catch((): string[] => [])
    for (const name of names) {
      if (!/^dsh-media-[a-f0-9-]{36}\.[a-z0-9]{1,12}$/.test(name)) continue
      try { if ((await fileIo.stat(`${cacheDir}/${name}`)).mtime < Date.now() / 1000 - 86400) await fileIo.unlink(`${cacheDir}/${name}`) }
      catch { /* The OS may already have evicted this cache entry. */ }
    }
  }
  const extension = /\.([a-z0-9]{1,12})$/i.exec(remote)?.[1].toLowerCase() || (video ? 'mp4' : 'image')
  const path = `${cacheDir}/dsh-media-${util.generateRandomUUID()}.${extension}`
  const output = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
  let complete = false
  try {
    await readMediaFile(client, sessionId, remote, video ? 200 * 1024 * 1024 : 20 * 1024 * 1024,
      async (chunk: Uint8Array): Promise<void> => {
        const buffer = chunk.buffer.slice(chunk.byteOffset, chunk.byteOffset + chunk.byteLength) as ArrayBuffer
        if (await fileIo.write(output.fd, buffer) !== buffer.byteLength) throw new Error('媒体缓存未完整写入')
      }, current)
    await fileIo.fsync(output.fd)
    complete = current()
    if (!complete) throw new Error('媒体读取已取消')
    return path
  } finally {
    await fileIo.close(output)
    if (!complete) await fileIo.unlink(path).catch(() => {})
  }
}

export async function clearMediaFiles(paths: string[]): Promise<void> {
  await Promise.all(paths.map((path: string) => fileIo.unlink(path).catch(() => {})))
}
