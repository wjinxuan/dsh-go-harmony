import { array, object, string, WireObject } from '../dsh/DshWire'
export interface ChartSeries { name: string; values: (number | null)[] }
export interface DonutSlice { label: string; value: number | null; drawn: number }
export function chartCategories(chart: WireObject): string[] { return array(chart['categories']).slice(0, 60).map((value: Object) => String(value ?? '').slice(0, 40)) }
export function chartSeries(chart: WireObject): ChartSeries[] {
  const categories = chartCategories(chart)
  let items = chart['series']
  if (!items && Array.isArray(chart['values'])) { const series: WireObject = { 'values': chart['values'] }; items = [series] }
  if (items && !Array.isArray(items)) items = [items]
  if (array(items).every((value: Object) => typeof value === 'number' || typeof value === 'string' || value === null)) {
    const series: WireObject = { 'values': items }; items = [series]
  }
  return array(items).slice(0, 6).map((entry: Object): ChartSeries => {
    const row = object(entry), values = array(Array.isArray(entry) ? entry : row['values'])
    return { name: string(row['name']), values: categories.map((_category: string, index: number): number | null => {
      const value = values[index], n = typeof value === 'string' && value.trim() ? Number(value) : value
      return typeof n === 'number' && Number.isFinite(n) ? n : null
    }) }
  })
}
export function chartTicks(low: number, high: number): number[] {
  if (!Number.isFinite(low) || !Number.isFinite(high)) return [0, 1]
  let lo = low, hi = high
  if (lo === hi) { lo = Math.min(0, lo); hi = hi === 0 ? 1 : Math.max(0, hi) }
  if (lo === hi) hi = lo + 1
  if (lo > hi) { const swap = lo; lo = hi; hi = swap }
  const raw = (hi - lo) / 4, magnitude = Math.pow(10, Math.floor(Math.log10(raw)))
  if (!Number.isFinite(raw) || raw <= 0 || !Number.isFinite(magnitude) || magnitude <= 0) return [lo, hi]
  const scale = [1, 2, 2.5, 5, 10].find((n: number) => n * magnitude >= raw * (1 - 1e-12)) || 10
  const step = scale * magnitude, start = Math.floor(lo / step + 1e-9) * step, end = Math.ceil(hi / step - 1e-9) * step
  if (!Number.isFinite(start) || !Number.isFinite(end)) return [lo, hi]
  const ticks: number[] = []
  for (let index = 0; index < 24; index++) { const value = start + step * index; if (value > end + step / 2) break; ticks.push(Number(value.toPrecision(12))) }
  return ticks.length < 2 ? [lo, hi] : ticks
}
export function chartAxis(values: (number | null)[], zero: boolean): number[] {
  const finite = values.filter((v: number | null) => v !== null && Number.isFinite(v)) as number[]
  if (!finite.length) return chartTicks(0, 1)
  const lo = Math.min(...finite), hi = Math.max(...finite)
  if (zero) return chartTicks(Math.min(0, lo), Math.max(0, hi))
  let pad = (hi - lo) * 0.1
  if (!pad || !Number.isFinite(pad)) pad = Math.abs(hi) * 0.1
  if (!pad || !Number.isFinite(pad)) pad = 1
  return chartTicks(Number.isFinite(lo - pad) ? lo - pad : lo, Number.isFinite(hi + pad) ? hi + pad : hi)
}
export function chartRatio(value: number, low: number, high: number): number {
  if (high === low) return 0.5
  const scale = Math.max(Math.abs(low), Math.abs(high), Math.abs(value)) || 1
  return Math.max(0, Math.min(1, (value / scale - low / scale) / (high / scale - low / scale)))
}
export function donutSlices(chart: WireObject, other: string): DonutSlice[] {
  const categories = chartCategories(chart), values = chartSeries(chart)[0]?.values || [], keep = categories.length > 6 ? 5 : categories.length
  const slices: DonutSlice[] = categories.slice(0, keep).map((label: string, index: number): DonutSlice => ({ label: label, value: values[index] ?? null, drawn: Math.max(0, values[index] || 0) }))
  if (keep < categories.length) { const rest = values.slice(keep).reduce((sum: number, value: number | null) => sum + Math.max(0, value || 0), 0); slices.push({ label: other, value: rest, drawn: rest }) }
  return slices
}
export function donutHit(slices: DonutSlice[], x: number, y: number, radius: number): number {
  const total = slices.reduce((sum: number, value: DonutSlice) => sum + value.drawn, 0), distance = Math.hypot(x, y)
  if (distance > radius || distance < radius - 40 || total <= 0 || !Number.isFinite(total)) return -1
  let angle = Math.atan2(y, x) + Math.PI / 2, start = 0
  if (angle < 0) angle += Math.PI * 2
  for (let index = 0; index < slices.length; index++) { const sweep = slices[index].drawn / total * Math.PI * 2; if (angle >= start && angle < start + sweep) return index; start += sweep }
  return -1
}
