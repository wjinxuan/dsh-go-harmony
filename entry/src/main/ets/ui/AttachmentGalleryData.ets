import type { WireObject } from '../dsh/DshWire'

export interface GalleryImage {
  key: string;
  name: string;
  path?: string;
  reference?: WireObject;
}

export function fittedSize(width: number, height: number, edge: number): number[] {
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width < 1 || height < 1 ||
    width * height > 32000000) throw new Error('图片像素过多或格式无效。')
  const scale = Math.min(1, edge / Math.max(width, height))
  return [Math.max(1, Math.floor(width * scale)), Math.max(1, Math.floor(height * scale))]
}

export function boundedPan(offset: number, extent: number, scale: number): number {
  if (extent <= 0 || scale <= 1) return 0
  const limit = extent * (scale - 1) / 2
  return Math.min(limit, Math.max(-limit, offset))
}

// A few large attachment responses can otherwise arrive together when the chat scrolls.
export class GalleryLoadQueue {
  private running: number = 0
  private waiting: (() => void)[] = []

  async run<T>(current: () => boolean, load: () => Promise<T>): Promise<T> {
    await new Promise<void>(resolve => {
      if (this.running < 2) { this.running++; resolve() }
      else this.waiting.push(resolve)
    })
    try {
      if (!current()) throw new Error('图片请求已取消')
      return await load()
    } finally {
      const next = this.waiting.shift()
      if (next) next()
      else this.running--
    }
  }
}
