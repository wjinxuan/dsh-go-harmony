import { fileIo as fs } from '@kit.CoreFileKit'
import type { BusinessError } from '@kit.BasicServicesKit'

export async function ensurePrivateDirectory(path: string): Promise<void> {
  try { await fs.mkdir(path, true) }
  catch (error) {
    // Harmony recursive mkdir still rejects an existing final directory.
    if ((error as BusinessError).code !== 13900015) throw error as Error
    const entry = await fs.lstat(path)
    if (!entry.isDirectory() || entry.isSymbolicLink()) throw error as Error
  }
}
