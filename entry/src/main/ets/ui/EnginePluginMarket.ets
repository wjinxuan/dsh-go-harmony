import { util } from '@kit.ArkTS'
import { rcp } from '@kit.RemoteCommunicationKit'
import { object, string, strings, WireObject } from '../dsh/DshWire'
import { marketEntries, PluginTarget } from './EngineFeatureData'

const MARKETS: string[] = ['https://dl.dshtui.com/market/', 'https://go.dshtui.com/market/']
async function fetchJson(session: rcp.Session, url: string, allowMissing: boolean): Promise<WireObject> {
  const response = await session.fetch(new rcp.Request(url, 'GET'))
  if (response.statusCode === 404 && allowMissing) return {}
  if (response.statusCode !== 200) throw new Error(`插件目录读取失败（HTTP ${response.statusCode}）`)
  if (!response.body || response.body.byteLength > 4 * 1024 * 1024) throw new Error('插件目录返回的文件无效')
  const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(response.body))
  return object(JSON.parse(text))
}

export async function fetchPluginMarket(): Promise<WireObject[]> {
  const session = rcp.createSession({ requestConfiguration: {
    transfer: { autoRedirect: true, timeout: { connectMs: 8000, transferMs: 15000 } }
  } })
  let failure = '插件目录没打开'
  try {
    for (const base of MARKETS) {
      try {
        const pair = await Promise.all([fetchJson(session, `${base}index.json`, false), fetchJson(session, `${base}dsh-go.json`, true)])
        return marketEntries(pair[0], pair[1])
      } catch (error) {
        if (error instanceof Error) failure = error.message || failure
      }
    }
    throw new Error(failure)
  } finally {
    session.close()
  }
}

export async function verifyMarketRelease(name: string, target: PluginTarget, listing: WireObject): Promise<void> {
  if (strings(listing['blockedVersions']).includes(target.version)) throw new Error('官方目录已屏蔽这个版本')
  const expected = string(listing['integrity'])
  if (!expected || target.spec.startsWith('git+')) return
  const registry = target.registry || 'https://registry.npmjs.org/'
  const session = rcp.createSession({ requestConfiguration: {
    transfer: { autoRedirect: false, timeout: { connectMs: 8000, transferMs: 12000 } }
  } })
  try {
    const result = await fetchJson(session, `${registry.replace(/\/+$/, '')}/${encodeURIComponent(name)}/${target.version}`, false)
    if (result['name'] !== name || result['version'] !== target.version || object(result['dist'])['integrity'] !== expected) {
      throw new Error('软件包完整性与官方目录不一致')
    }
  } finally {
    session.close()
  }
}
