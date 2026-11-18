import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
const moduleUrl = source => 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source));
const wire = moduleUrl(await readFile(new URL('../entry/src/main/ets/dsh/DshWire.ets', import.meta.url), 'utf8'));
const source = (await readFile(new URL('../entry/src/main/ets/ui/NativePluginChartData.ets', import.meta.url), 'utf8')).replace(', WireObject }', ' }').replace("'../dsh/DshWire'", JSON.stringify(wire));
const { chartCategories, chartSeries, chartTicks, chartAxis, chartRatio, donutSlices, donutHit } = await import(moduleUrl(source));
test('chart preserves missing data and original 60-point / 6-series caps', () => {
  const chart = { categories: Array.from({length: 65}, (_, i) => `point ${i}`), series: Array.from({length: 8}, (_, i) => ({ name: `series ${i}`, values: [1, '2.5', null, '', NaN, Infinity, '-3'] })) };
  assert.equal(chartCategories(chart).length, 60); assert.equal(chartSeries(chart).length, 6);
  assert.deepEqual(chartSeries(chart)[0].values.slice(0, 8), [1, 2.5, null, null, null, null, -3, null]);
  assert.deepEqual(chartSeries({ categories: ['a', 'b'], values: [1, 2] })[0].values, [1, 2]);
});
test('nice axes contain positive, negative, zero, constant and extreme finite values', () => {
  assert.deepEqual(chartTicks(0, 10), [0, 2.5, 5, 7.5, 10]);
  for (const values of [[0], [5], [-5], [2, 4], [-8, -1], [-1e308, 1e308], [1e308, 1.7e308]]) for (const zero of [false, true]) {
    const ticks = chartAxis(values, zero); assert.ok(ticks.length >= 2 && ticks.length <= 24); assert.ok(ticks.every(Number.isFinite));
    assert.ok(ticks[0] <= Math.min(...values)); assert.ok(ticks.at(-1) >= Math.max(...values));
    for (const value of values) assert.ok(Number.isFinite(chartRatio(value, ticks[0], ticks.at(-1))));
  }
  assert.equal(chartRatio(0, -1e308, 1e308), 0.5);
});
test('donut caps at six slices, aggregates Other and hit-tests actual ring sectors', () => {
  const slices = donutSlices({categories: ['a','b','c','d','e','f','g'], values: [1, 2, -3, null, 4, 5, 6]}, 'Other');
  assert.equal(slices.length, 6); assert.deepEqual(slices.at(-1), {label: 'Other', value: 11, drawn: 11});
  assert.equal(slices[2].value, -3); assert.equal(slices[2].drawn, 0);
  const halves = donutSlices({categories: ['a','b'], values: [1,1]}, 'Other');
  assert.equal(donutHit(halves, 80, 0, 96), 0); assert.equal(donutHit(halves, -80, 0, 96), 1);
  assert.equal(donutHit(halves, 0, 0, 96), -1); assert.equal(donutHit(halves, 100, 0, 96), -1);
  assert.equal(donutHit(donutSlices({categories:['zero'], values:[0]}, 'Other'), 80, 0, 96), -1);
});
