import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import type { DshClient } from '../dsh/DshClient'
import type { DshMessage, WireObject } from '../dsh/DshWire'
import { object } from '../dsh/DshWire'
import type { DraftAttachment } from './AttachmentPicker'
import { deleteAttachments } from './AttachmentPicker'
import { regenerationImageInfo } from './MessageRegeneration'

export async function resendImages(client: DshClient, sourceId: string, prompt: DshMessage, cacheDir: string,
  current: () => boolean): Promise<DraftAttachment[]> {
  const files: DraftAttachment[] = []
  const check = (): void => { if (!current()) throw new Error('主机或对话已切换。') }
  try {
    check()
    const images = (prompt.content || []).filter((part: WireObject) => part['type'] === 'image')
    for (let index = 0; index < images.length; index++) {
      check()
      const reference = object(images[index]['attachment'])
      const bytes = await client.readSessionImage(sourceId, reference, undefined, current)
      check()
      const info = regenerationImageInfo(reference, bytes, index)
      const id = util.generateRandomUUID()
      const file: DraftAttachment = { id: id, name: info.name, path: `${cacheDir}/dsh-attachment-${id}`,
        size: bytes.byteLength, mediaType: info.mediaType }
      files.push(file)
      const output = await fileIo.open(file.path, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
      try {
        check()
        if (await fileIo.write(output.fd, bytes) !== bytes.byteLength) throw new Error('图片未完整写入缓存。')
      } finally { await fileIo.close(output) }
      check()
    }
    return files
  } catch (_) {
    await deleteAttachments(files)
    throw new Error(current() ? '无法读取原消息中的图片。' : '主机或对话已切换。')
  }
}
