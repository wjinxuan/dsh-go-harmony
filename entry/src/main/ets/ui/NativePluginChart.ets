import { localizedSettingsText } from './SettingsLocale'
import { chartCategories, chartSeries, chartAxis, chartRatio, donutSlices, donutHit, DonutSlice, ChartSeries } from './NativePluginChartData'
import { array, object, string, WireObject } from '../dsh/DshWire'
import { pluginText } from './NativePluginData'
import { ThemeColors, themeColors } from './DshTheme'

@Component
export struct NativePluginChart {
  @StorageProp('dshLanguage') language: string = 'system'
  private t(value: string): string { return localizedSettingsText(value, this.language) }
  @Prop @Watch('redraw') colors: ThemeColors = themeColors()
  @Prop @Watch('changed') chart: WireObject = {}
  @State private selected: number = -1
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private canvasWidth: number = 320
  private ready: boolean = false
  private chartHeight(): number { return ['hbar', 'barh', 'horizontal', 'horizontalBar'].includes(string(this.chart['kind'])) ? Math.max(40, this.series().length * 10 + 14) * this.categories().length + 42 : 220 }
  private categories(): string[] { return chartCategories(this.chart) }
  private series(): ChartSeries[] { return chartSeries(this.chart) }
  private slices(): DonutSlice[] { return donutSlices(this.chart, this.t('其他')) }
  private donut(): boolean { return ['donut', 'pie', 'doughnut', 'ring'].includes(string(this.chart['kind'])) }
  private changed(): void { this.selected = -1; this.redraw() }
  private value(value: number | null): string { if (value === null) return '—'; const unit = string(this.chart['unit']); return Number(value.toPrecision(6)).toLocaleString() + (unit ? unit === '%' ? '%' : ' ' + unit : '') }
  private percentage(slice: DonutSlice): string { const total = this.slices().reduce((sum: number, row: DonutSlice) => sum + row.drawn, 0); return total > 0 && Number.isFinite(total) ? (slice.drawn / total * 100).toFixed(1) + '%' : '—' }
  private palette(index: number): string { return [this.colors.primary, this.colors.success, this.colors.warning, this.colors.danger, '#8B5CF6', '#06B6D4'][index % 6] }
  private redraw(): void {
    if (!this.ready) return
    const ctx = this.context; const w = this.canvasWidth; const h = this.chartHeight(); const left = 45; const top = 14; const right = w - 12; const bottom = h - 28
    ctx.clearRect(0, 0, w, h)
    const categories = this.categories(); const series = this.series(); if (!categories.length || !series.length) return
    const kind = string(this.chart['kind']); const values = series.flatMap((item: ChartSeries) => item.values).filter((value: number | null) => value !== null) as number[]
    if (!values.length) return
    if (this.donut()) {
      const slices = this.slices(), total = slices.reduce((sum: number, item: DonutSlice) => sum + item.drawn, 0)
      if (!total || !Number.isFinite(total)) return
      let angle = -Math.PI / 2; const radius = 80
      slices.forEach((item: DonutSlice, index: number) => {
        const end = angle + item.drawn / total * Math.PI * 2
        ctx.globalAlpha = this.selected < 0 || this.selected === index ? 1 : 0.35
        ctx.beginPath(); ctx.arc(w / 2, h / 2 - 6, radius, angle, end); ctx.strokeStyle = this.palette(index); ctx.lineWidth = this.selected === index ? 36 : 32; ctx.stroke(); angle = end
      }); ctx.globalAlpha = 1; ctx.fillStyle = this.colors.text; ctx.font = '16vp sans-serif'; ctx.textAlign = 'center'
      ctx.fillText(this.value(this.selected >= 0 ? slices[this.selected]?.value ?? null : total), w / 2, h / 2 - 8)
      ctx.font = '11vp sans-serif'; ctx.fillText(this.selected >= 0 ? slices[this.selected]?.label || '' : this.t('合计'), w / 2, h / 2 + 14)
      return
    }
    const ticks = chartAxis(values, !['line', 'area', 'spline'].includes(kind))
    const low = ticks[0], high = ticks[ticks.length - 1]
    const horizontal = ['hbar', 'barh', 'horizontal', 'horizontalBar'].includes(kind)
    const y = (value: number): number => bottom - chartRatio(value, low, high) * (bottom - top)
    const step = (right - left) / categories.length
    ctx.font = '10vp sans-serif'; ctx.textAlign = 'right'; ctx.lineWidth = 0.5
    for (const value of ticks) {
      ctx.fillStyle = this.colors.muted; ctx.strokeStyle = this.colors.border; ctx.beginPath()
      if (horizontal) { const x = left + chartRatio(value, low, high) * (right - left); ctx.textAlign = 'center'; ctx.fillText(Number(value.toPrecision(4)).toString(), x, h - 8); ctx.moveTo(x, top); ctx.lineTo(x, bottom) }
      else { ctx.textAlign = 'right'; ctx.fillText(Number(value.toPrecision(4)).toString(), left - 5, y(value) + 3); ctx.moveTo(left, y(value)); ctx.lineTo(right, y(value)) }
      ctx.stroke()
    }
    series.forEach((entry: ChartSeries, seriesIndex: number) => {
      ctx.fillStyle = this.palette(seriesIndex); ctx.strokeStyle = this.palette(seriesIndex); ctx.lineWidth = 2; let started = false
      if (['line', 'area', 'spline'].includes(kind)) {
        ctx.beginPath(); entry.values.forEach((value: number | null, index: number) => {
          if (value === null) { started = false; return }
          if (started) ctx.lineTo(left + step * (index + 0.5), y(value)); else ctx.moveTo(left + step * (index + 0.5), y(value)); started = true
        }); ctx.stroke()
      } else if (['hbar', 'barh', 'horizontal', 'horizontalBar'].includes(kind)) {
        const row = (bottom - top) / categories.length
        entry.values.forEach((value: number | null, index: number) => {
          if (value === null) return
          const zero = left + chartRatio(0, low, high) * (right - left); const x = left + chartRatio(value, low, high) * (right - left)
          ctx.fillRect(Math.min(zero, x), top + row * index + row * 0.15 + seriesIndex * row * 0.7 / series.length, Math.abs(x - zero), row * 0.7 / series.length)
        })
      } else {
        entry.values.forEach((value: number | null, index: number) => {
          if (value === null) return
          const bw = step * 0.72 / series.length; ctx.fillRect(left + step * index + step * 0.14 + seriesIndex * bw, Math.min(y(0), y(value)), Math.max(0.5, bw - 1), Math.max(1, Math.abs(y(0) - y(value))))
        })
      }
    })
    ctx.fillStyle = this.colors.muted; ctx.textAlign = 'center'
    categories.forEach((label: string, index: number) => { if (horizontal) { ctx.textAlign = 'right'; ctx.fillText(label.slice(0, 7), left - 5, top + (bottom - top) / categories.length * (index + 0.5) + 3) } else if (index % Math.max(1, Math.ceil(categories.length / 6)) === 0) ctx.fillText(label.slice(0, 8), left + step * (index + 0.5), h - 8) })
  }
  private select(x: number, y: number): void {
    if (this.donut()) { const hit = donutHit(this.slices(), x - this.canvasWidth / 2, y - 104, 96); this.selected = hit === this.selected ? -1 : hit; this.redraw(); return }
    const n = this.categories().length; const horizontal = ['hbar', 'barh', 'horizontal', 'horizontalBar'].includes(string(this.chart['kind']))
    this.selected = Math.max(0, Math.min(n - 1, Math.floor(horizontal ? (y - 14) / (this.chartHeight() - 42) * n : (x - 45) / (this.canvasWidth - 57) * n)))
  }
  build() {
    Column({ space: 6 }) {
      Canvas(this.context).width('100%').height(this.chartHeight()).onReady(() => { this.ready = true; this.redraw() })
        .onAreaChange((_old: Area, current: Area) => { this.canvasWidth = Number(current.width); this.redraw() })
        .onTouch((event: TouchEvent) => { if (!this.donut() && event.touches.length) this.select(event.touches[0].x, event.touches[0].y) })
        .onClick((event: ClickEvent) => { if (this.donut()) this.select(event.x, event.y) })
      if (!this.donut() && this.selected >= 0) Text(this.categories()[this.selected] + ' · ' + this.series().map((entry: ChartSeries) =>
        (entry.name ? entry.name + ' ' : '') + this.value(entry.values[this.selected])).join(' / ')).fontSize(12).fontColor(this.colors.text)
      if (this.donut()) Column({ space: 4 }) { ForEach(this.slices(), (slice: DonutSlice, index: number) => {
        Button({ type: ButtonType.Normal }) { Row() { Text('● ' + slice.label).fontColor(this.palette(index)).layoutWeight(1); Text(this.value(slice.value) + ' · ' + this.percentage(slice)).fontColor(this.colors.text) }.width('100%') }
          .backgroundColor(this.selected === index ? this.colors.surfaceAlt : Color.Transparent).onClick(() => { this.selected = this.selected === index ? -1 : index; this.redraw() })
      }) }.width('100%')
      else Row({ space: 12 }) { ForEach(this.series(), (entry: ChartSeries, index: number) => { if (entry.name) Text('● ' + entry.name).fontSize(12).fontColor(this.palette(index)) }) }
      if (array(this.chart['categories']).length > 60 || array(this.chart['series']).length > 6) Text(this.t('已截断：最多显示 60 个点、6 组数据')).fontSize(11).fontColor(this.colors.muted)
      if (string(this.chart['caption'])) Text(string(this.chart['caption'])).fontSize(12).fontColor(this.colors.muted)
    }.width('100%').accessibilityText(this.categories().map((category: string, index: number) => category + ': ' + this.series().map((series: ChartSeries) => series.name + ' ' + this.value(series.values[index])).join(', ')).join('; '))
  }
}
