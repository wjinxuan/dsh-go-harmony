import { createRequire } from 'node:module';
import { AttachmentError } from '@deepseek-ai/dsh-attachment';

const { PNG } = createRequire(new URL('./harmony-deps/package.json', import.meta.url))('pngjs');
const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

export async function inspectPng(data, limits) {
  const bytes = Buffer.from(data.buffer, data.byteOffset, data.byteLength);
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(signature) || bytes.toString('ascii', 12, 16) !== 'IHDR' ||
      bytes.readUInt32BE(8) !== 13 || bytes[24] !== 8 || bytes[28] !== 0) {
    throw new AttachmentError('Expected a non-interlaced 8-bit PNG.', 'INVALID_IMAGE');
  }
  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);
  if (!width || !height || width * height > Math.min(limits?.maxPixels ?? Infinity, 4194304)) {
    throw new AttachmentError('Image exceeds the decoded-pixel limit.', 'IMAGE_TOO_MANY_PIXELS');
  }
  if (Math.max(width, height) > Math.min(limits?.maxDimension ?? Infinity, 8192)) {
    throw new AttachmentError('Image exceeds the per-side limit.', 'IMAGE_DIMENSION_TOO_LARGE');
  }
  try {
    const image = PNG.sync.read(bytes);
    if (image.width !== width || image.height !== height || image.data.length !== width * height * 4) throw new Error();
    return { mediaType: 'image/png', width, height, animated: false, carriesMetadata: true,
      depth: 'uchar', space: 'srgb', hasAlpha: true, rgba: image.data };
  } catch (error) {
    throw new AttachmentError('Unsupported or malformed PNG.', 'INVALID_IMAGE', { cause: error });
  }
}

export function encodePng(source, width, height, maxBytes) {
  // shortcut: nearest-neighbor resampling, replace with a higher-quality filter when the embedded codec supports one.
  const bytes = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const from = (Math.floor(y * source.height / height) * source.width + Math.floor(x * source.width / width)) * 4;
      source.rgba.copy(bytes, (y * width + x) * 4, from, from + 4);
    }
  }
  const data = PNG.sync.write({ data: bytes, width, height }, { colorType: 6, filterType: -1 });
  if (data.length > maxBytes) throw new AttachmentError('PNG exceeds the encoded byte limit.', 'IMAGE_TOO_LARGE');
  return { data, width, height, mediaType: 'image/png', hasAlpha: true };
}
