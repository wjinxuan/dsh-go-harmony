export const util = {
  TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value) } },
  TextDecoder: { create(encoding, options) { const decoder = new TextDecoder(encoding, options); return { decodeWithStream: value => decoder.decode(value) } } },
  Base64Helper: class {
    encodeToStringSync(value) { return Buffer.from(value).toString('base64') }
    decodeSync(value) { return Buffer.from(value, 'base64') }
  }
}
