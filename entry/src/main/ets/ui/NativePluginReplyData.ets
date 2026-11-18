import { DshMessage, array, object, string, WireObject } from '../dsh/DshWire'
import { PluginNode, PluginView } from './NativePluginData'
export interface ModelUiState { state: string; text: string }
export interface ModelUiAnswer { key: string; selected: string[]; free: string; confirmed?: boolean }
export function modelUiReplyState(messages: DshMessage[], messageId: string, running: boolean, pending: string[] = []): ModelUiState {
  const index = messages.findIndex((message: DshMessage) => message.role === 'assistant' && message.id === messageId)
  if (index < 0) return { state: 'expired', text: '' }
  let later = false
  for (let i = index + 1; i < messages.length; i++) {
    if (messages[i].role === 'user') return { state: messages[i].text.trimStart().startsWith('[dsh-ui reply]') ? 'answered' : 'expired', text: messages[i].text }
    if (messages[i].role === 'assistant' && messages[i].text.trim()) later = true
  }
  if (pending.length) return { state: pending[0].trimStart().startsWith('[dsh-ui reply]') ? 'answered' : 'expired', text: pending[0] }
  return { state: later ? 'expired' : running ? 'running' : 'live', text: '' }
}
export function modelUiAnswer(view: PluginView, text: string): ModelUiAnswer | undefined {
  const lines = text.trimStart().split(/\r?\n/); const head = lines[0]
  if (!head.startsWith('[dsh-ui reply]')) return undefined
  const title = head.slice(14).trim(); if (title && view.title && title !== view.title) return undefined
  const body = lines.slice(1).map((line: string) => line.trim()).filter((line: string) => !!line)
  const choice = /^(?:选择|Select|Choice|Selected)[：:]\s*(.*)$/i.exec(body[0] || '')
  const other = body.find((line: string) => /^(?:其他|Other)[：:]/i.test(line))
  const free = other ? other.replace(/^(?:其他|Other)[：:]\s*/i, '') : ''
  const nodes: PluginNode[] = []
  const walk = (node: PluginNode): void => { nodes.push(node); node.children.forEach(walk) }; walk(view.root)
  if (choice || free) {
    for (const node of nodes) {
      if (node.type !== 'options') continue
      const labels = array(node.raw['options']).map((option: Object) => typeof option === 'string' ? option : string(object(option)['label']))
      const selected = labels.filter((label: string) => ('、' + (choice?.[1] || '') + '、').includes('、' + label + '、'))
      const typed = node.raw['freetext'] ? free : ''
      if (selected.length || typed) return { key: node.key, selected: node.raw['multi'] === true ? selected : selected.slice(0, 1), free: typed }
    }
  }
  if (/^(?:确认|Confirm|取消|Cancel)(?:[：:]|$)/i.test(body[0] || '')) {
    const node = nodes.find((item: PluginNode) => item.type === 'confirm')
    if (node) return { key: node.key, selected: [], free: '', confirmed: /^(?:确认|Confirm)/i.test(body[0]) }
  }
  return undefined
}
