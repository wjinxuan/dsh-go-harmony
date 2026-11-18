export interface ShareLaunch { link: string; file: string }
export function shareLinkInput(value: string): string {
  const text = value.trim().replace(/^dshgo:\/\/go\.dshtui\.com\//, 'https://go.dshtui.com/')
  return /^https:\/\/go\.dshtui\.com\/c\/[A-Za-z0-9]{10}\/?#k=[A-Za-z0-9_-]{43}$/.test(text) ? text : ''
}
export function inlineShareCode(value: string): string {
  const text = value.trim()
  if (!text || text.length > 1024 * 1024 + 256 || /[\x00-\x20\x7f]/.test(text)) return ''
  const match = /^(?:dshgo:\/\/share\/(?:conversation|profile|plugin)\?|https?:\/\/(?:go\.dshtui\.com\/share|ccch1mneyyy\.github\.io\/dsh-go\/share)(?:\/index\.html|\/)?#)p=([^&]+)$/.exec(text)
  if (!match) return ''
  try { const code = decodeURIComponent(match[1]); return /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{8}$/.test(code) && code.length <= 1024 * 1024 ? code : '' } catch { return '' }
}
export function shareLaunch(uri: string, mime: string = ''): ShareLaunch | undefined {
  if (!uri || /[\x00-\x20\x7f]/.test(uri)) return undefined
  if (inlineShareCode(uri)) return { link: uri, file: '' }
  if (uri.length > 8192) return undefined
  const link = shareLinkInput(uri)
  if (link) return { link: link, file: '' }
  if (/^(?:file|content):\/\//.test(uri) && (mime === 'application/vnd.dshgo+json' || /\.dshgo(?:[?#]|$)/i.test(uri))) return { link: '', file: uri }
  return undefined
}
