import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { camera, cameraPicker } from '@kit.CameraKit'
import { fileIo, fileUri, picker } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { image } from '@kit.ImageKit'

export interface DraftAttachment {
  id: string;
  name: string;
  path: string;
  size: number;
  mediaType?: string;
}

export const MAX_ATTACHMENTS: number = 9
export const MAX_ATTACHMENT_TOTAL: number = 400 * 1024 * 1024
const MAX_FILE: number = 200 * 1024 * 1024
const MAX_IMAGE: number = 20 * 1024 * 1024
const MAX_NORMALIZED_IMAGE: number = 4 * 1024 * 1024

export async function pickAttachments(context: common.UIAbilityContext, kind: string, remaining: number,
  budget: number, current: () => boolean): Promise<DraftAttachment[]> {
  let uris: string[]
  if (kind === 'camera') {
    const profile: cameraPicker.PickerProfile = { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK }
    const result = await cameraPicker.pick(context, [cameraPicker.PickerMediaType.PHOTO], profile)
    uris = result.resultCode === 0 && result.resultUri ? [result.resultUri] : []
  } else if (kind === 'photos') {
    const options = new photoAccessHelper.PhotoSelectOptions()
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
    options.maxSelectNumber = remaining
    uris = (await new photoAccessHelper.PhotoViewPicker().select(options)).photoUris
  } else {
    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = remaining
    uris = await new picker.DocumentViewPicker(context).select(options)
  }
  const selected: DraftAttachment[] = []
  try {
    for (const uri of uris.slice(0, remaining)) {
      if (!current()) break
      const file = await cacheAttachment(context.cacheDir, uri, kind !== 'files', budget)
      selected.push(file)
      budget -= file.size
    }
    if (current()) return selected
  } catch (error) {
    await deleteAttachments(selected)
    const detail = error instanceof Error ? error.message : ''
    throw new Error(/^[\u4e00-\u9fff]/.test(detail) ? detail : '无法读取所选附件。')
  }
  await deleteAttachments(selected)
  return []
}

async function cacheAttachment(cacheDir: string, uri: string, photo: boolean, budget: number): Promise<DraftAttachment> {
  const id = util.generateRandomUUID()
  const path = `${cacheDir}/dsh-attachment-${id}`
  const name = new fileUri.FileUri(uri).name.replace(/[\x00-\x1f\x7f/\\]/g, '').slice(0, 220) || '附件'
  const input = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
  try {
    const info = await fileIo.stat(input.fd)
    if (!info.isFile() || info.size < 0 || info.size > Math.min(photo ? MAX_IMAGE : MAX_FILE, budget)) {
      throw new Error(photo ? '图片超过 20 MiB 或附件总限额。' : '文件超过 200 MiB 或附件总限额。')
    }
    const head = new ArrayBuffer(12)
    const length = await fileIo.read(input.fd, head, { offset: 0 })
    const header = new Uint8Array(head, 0, length)
    const raster = photo || (length >= 3 && header[0] === 0xff && header[1] === 0xd8 && header[2] === 0xff) ||
      (length >= 8 && header[0] === 137 && header[1] === 80 && header[2] === 78 && header[3] === 71) ||
      (length >= 6 && header[0] === 71 && header[1] === 73 && header[2] === 70) ||
      (length >= 12 && header[0] === 82 && header[1] === 73 && header[2] === 70 && header[3] === 70 &&
        header[8] === 87 && header[9] === 69 && header[10] === 66 && header[11] === 80)
    const png = raster ? await preparePng(input.fd, info.size, budget) : undefined
    const output = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
    try {
      if (png) {
        if (await fileIo.write(output.fd, png) !== png.byteLength) throw new Error('图片未完整写入缓存。')
        return { id: id, name: `${name.replace(/\.[^.]+$/, '') || '图片'}.png`, path: path, size: png.byteLength,
          mediaType: 'image/png' }
      }
      const chunk = new ArrayBuffer(1024 * 1024)
      let copied = 0
      while (copied < info.size) {
        const count = await fileIo.read(input.fd, chunk, { offset: copied, length: Math.min(chunk.byteLength, info.size - copied) })
        if (count <= 0 || await fileIo.write(output.fd, chunk, { length: count }) !== count) {
          throw new Error('文件未完整写入缓存。')
        }
        copied += count
      }
      return { id: id, name: name, path: path, size: copied }
    } finally { await fileIo.close(output) }
  } catch (error) {
    await fileIo.unlink(path).catch(() => {})
    throw error as Error
  } finally { await fileIo.close(input) }
}

async function preparePng(fd: number, size: number, budget: number): Promise<ArrayBuffer> {
  if (size > MAX_IMAGE) throw new Error('图片超过 20 MiB。')
  const source = image.createImageSource(fd)
  try {
    const info = await source.getImageInfo()
    if (info.size.width < 1 || info.size.height < 1 || info.size.width * info.size.height > 64000000) {
      throw new Error('图片像素过多或格式无效。')
    }
    const packer = image.createImagePacker()
    try {
      for (const edge of [1280, 960, 640]) {
        const scale = Math.min(1, edge / Math.max(info.size.width, info.size.height))
        const pixels = await source.createPixelMap({ desiredSize: {
          width: Math.max(1, Math.floor(info.size.width * scale)), height: Math.max(1, Math.floor(info.size.height * scale))
        }, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 })
        try {
          const bytes = await packer.packing(pixels, { format: 'image/png', quality: 100 })
          if (bytes.byteLength > 0 && bytes.byteLength <= Math.min(MAX_NORMALIZED_IMAGE, budget)) return bytes
        } finally { await pixels.release() }
      }
    } finally { await packer.release() }
    throw new Error('图片压缩后仍超过附件限额。')
  } finally { await source.release() }
}

export async function deleteAttachments(items: DraftAttachment[]): Promise<void> {
  await Promise.all(items.map((item: DraftAttachment) => fileIo.unlink(item.path).catch(() => {})))
}
