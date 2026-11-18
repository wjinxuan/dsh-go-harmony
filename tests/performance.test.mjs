import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
const wire = 'data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(await readFile(new URL('../entry/src/main/ets/dsh/DshWire.ets', import.meta.url), 'utf8')));
const source = (await readFile(new URL('../entry/src/main/ets/ui/PerformanceData.ets', import.meta.url), 'utf8')).replace("'../dsh/DshWire'", JSON.stringify(wire));
const { performancePreferences, performanceState, performanceFrames, ThermalPolicy } = await import('data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source)));
test('automatic performance follows memory, retains manual overrides, and animation gates fluid effects', () => {
  const low = performanceState(performancePreferences(), 4 * 1024 ** 3);
  assert.equal(low.lightweight, true); assert.equal(low.blur, false); assert.equal(low.animations, false);
  assert.equal(performanceState(performancePreferences(), 5 * 1024 ** 3).lightweight, false);
  assert.equal(performanceState().tier, 'medium');
  const hot = performanceState(performancePreferences({ mode: 'full', blur: true, animations: false, fluid: true }), 8 * 1024 ** 3, 3, true);
  assert.equal(hot.lightweight, true); assert.equal(hot.blur, true); assert.equal(hot.fluid, false);
  assert.deepEqual(performancePreferences({ mode: 'unknown', refreshRate: 'unknown', blur: 'true' }), performancePreferences());
});
test('temperature recovery requires thirty continuous cool seconds and ignores invalid sensor values', () => {
  const policy = new ThermalPolicy(); policy.update(2, 100); assert.equal(policy.lightweight, true);
  policy.update(1, 200); policy.advance(30199); assert.equal(policy.lightweight, true);
  policy.update(3, 30200); assert.equal(policy.coolSince, -1);
  policy.update(0, 40000); policy.update(NaN, 70000); assert.equal(policy.lightweight, true);
  policy.advance(70000); assert.equal(policy.lightweight, false);
  policy.update(8, 80000); assert.equal(policy.level, 0);
});
test('refresh leases release in background, idle automatic mode and system mode', () => {
  assert.equal(performanceFrames('max', false, true, 120), 0);
  assert.equal(performanceFrames('auto', true, false, 120), 0);
  assert.equal(performanceFrames('system', true, true, 120), 0);
  assert.equal(performanceFrames('auto', true, true, 120), 120);
  assert.equal(performanceFrames('max', true, false, NaN), 60);
  assert.equal(performanceFrames('max', true, true, 999), 240);
});
