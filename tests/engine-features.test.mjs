import assert from 'node:assert/strict';
import test from 'node:test';
import {
  marketEntries, marketTarget, pluginOperationNotice, pluginTitle,
  scheduleFailure, scheduleTargetSession, scheduleTiming, teamMessage
} from './ui/EngineFeatureData.ts';

test('builds the official local time and interval request, rejecting invalid input', () => {
  assert.deepEqual(scheduleTiming('at', '2027-01-20 09:00', 'Asia/Shanghai', []), {
    kind: 'at', at: { date: '2027-01-20', time: '09:00:00', time_zone: 'Asia/Shanghai' }
  });
  assert.deepEqual(scheduleTiming('weekly', '18:45', 'UTC', [7, 1]), {
    kind: 'weekly', weekly: { time: '18:45:00', time_zone: 'UTC', weekdays: [1, 7] }
  });
  assert.deepEqual(scheduleTiming('every', '60', '', []), { kind: 'every', every_seconds: 60 });
  assert.throws(() => scheduleTiming('every', '59', '', []), /至少/);
  assert.throws(() => scheduleTiming('after', '9007199254740993', '', []), /整秒数/);
  assert.throws(() => scheduleTiming('weekly', '12:00', 'UTC', []), /选一天/);
  assert.throws(() => scheduleTiming('weekly', '12:00', 'UTC', [3, 3]), /重复/);
  assert.throws(() => scheduleTiming('weekly', '12:00', 'UTC', [8]), /1 到 7/);
  assert.throws(() => scheduleTiming('at', '2027-02-29 09:00', 'Asia/Shanghai', []), /日历日期/);
  assert.throws(() => scheduleTiming('daily', '24:00', 'UTC', []), /24 小时/);
  assert.throws(() => scheduleTiming('cron', '* * * *', 'UTC', []), /五段/);
});

test('picks an exact newest market version and its matching sidecar only', () => {
  const npm = { type: 'npm', registry: 'https://registry.npmjs.org/' };
  const index = { format: 1, plugins: [{ name: '@author/plugin', title: { zh: '索引' }, versions: [
    { version: '2.1.0-rc.10', source: npm }, { version: '2.1.0-rc.2', source: npm },
    { version: '2.0.0', source: npm }, { version: '3.0.0', source: { type: 'npm', registry: 'https://a@host/' } }
  ] }] };
  const [row] = marketEntries(index, { schema: 1, plugins: { '@author/plugin': { version: '2.0.0', title: { zh: '旧版本' } } } });
  assert.equal(row.version, '2.1.0-rc.10');
  assert.equal(pluginTitle(row), '索引');
  assert.deepEqual(marketTarget(row.name, row.release), {
    spec: '@author/plugin@2.1.0-rc.10', registry: 'https://registry.npmjs.org/', version: '2.1.0-rc.10'
  });
  assert.equal(marketTarget('plugin', { version: '1.0.0', source: {
    type: 'git', url: 'https://github.com/a/b', commit: '0'.repeat(40), path: '../other'
  } }), undefined);
  assert.throws(() => marketEntries({ format: 2, plugins: [] }, {}), /目录格式/);
});

test('distinguishes accepted operations, restarts, conflicts and host failures', () => {
  assert.match(pluginOperationNotice({ application: 'restart-required' }), /重启/);
  assert.throws(() => pluginOperationNotice({ application: 'failed', error: { code: 'unsupported-platform' } }), /unsupported-platform/);
  assert.throws(() => pluginOperationNotice({ changed: true }), /未确认/);
  assert.throws(() => scheduleFailure({ code: 'schedule_execution_pending' }), /排队/);
  assert.equal(scheduleTargetSession({ target: { kind: 'new_once', sessionId: 'reserved' } }), '');
  assert.equal(scheduleTargetSession({ sessionId: 'legacy' }), 'legacy');
});

test('reads team inbox messages and excludes ordinary subagent messages', () => {
  const event = { type: 'user/message', seq: 9, time: 1000, data: {
    source: { kind: 'agent-message', senderSessionId: 's1' },
    content: [{ type: 'text', text: 'Team message from reviewer:' }, { type: 'text', text: 'All done.' }]
  } };
  assert.deepEqual(teamMessage(event, 's2'), {
    id: 's2|9', recipient: 's2', senderId: 's1', senderName: 'reviewer', time: 1000, text: 'All done.'
  });
  assert.equal(teamMessage({ ...event, data: { ...event.data, content: event.data.content.slice(1) } }, 's2'), undefined);
});
