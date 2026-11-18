// Isolated host-test counterpart of LocalEngine's AssetStore unlock. The caller
// retains the synthetic key for restart tests; it is never a production fallback.
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
export async function unlockTestCredentials(ready, masterKey = randomBytes(32).toString('base64url')) {
  const control = ready.transportControl;
  assert.ok(control && /^http:\/\/127\.0\.0\.1:\d+$/.test(control.url));
  const response = await fetch(control.url + '/credentials/unlock', { method: 'POST',
    headers: { authorization: control.authorization, 'content-type': 'application/json' },
    body: JSON.stringify({ masterKey }), signal: AbortSignal.timeout(15000) });
  assert.equal(response.status, 200, 'Synthetic credential vault unlock');
  assert.deepEqual(await response.json(), { unlocked: true }); return masterKey;
}
