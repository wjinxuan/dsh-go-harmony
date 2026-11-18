// Public vectors from dsh-Go v1.0.15 packages/dsh_remote/test/fixtures (MIT).
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { NoiseInitiator, noisePrologue, pairingProof, x25519Key, Fragments, parseWire } from '../runtime/dsh-remote-wire.mjs';

const load = async file => JSON.parse(await readFile(new URL('./fixtures/dsh-remote/' + file, import.meta.url), 'utf8'));
const decode = value => Buffer.from(value, 'base64url');

test('pinned Noise IK vector and authenticated replay rejection', async () => {
  const { vectors } = await load('noise-ik.json');
  for (const vector of vectors) {
    const keys = vector.staticKeys;
    const scope = vector.prologue;
    const prologue = noisePrologue(scope.connectionId, scope.hostDeviceId, scope.clientDeviceId);
    assert.deepEqual(prologue, decode(scope.bytes));
    assert.deepEqual(x25519Key(decode(keys.initiator.privateKey)), keys.initiator);
    const noise = new NoiseInitiator(keys.initiator, keys.responder.publicKey, prologue, decode(vector.ephemeralPrivateKeys.initiator));
    try {
      assert.deepEqual(noise.start(decode(vector.handshake.message1.payload)), decode(vector.handshake.message1.message));
      assert.deepEqual(noise.finish(decode(vector.handshake.message2.message)), decode(vector.handshake.message2.payload));
      let counter = 0;
      for (const row of vector.transport) {
        if (row.sender === 'initiator') {
          assert.equal(noise.encrypt(decode(row.plaintext)).ciphertext, row.ciphertext);
        } else {
          assert.deepEqual(noise.decrypt(counter, row.ciphertext), decode(row.plaintext));
          assert.throws(() => noise.decrypt(counter, row.ciphertext), /SECURE_CHANNEL_FAILED/);
          counter++;
        }
      }
    } finally { noise.destroy(); }
  }
});

test('pinned pairing proofs, strict JSON, and DSHF fragmentation', async () => {
  const fixture = await load('proof_v1.json');
  for (const row of fixture.vectors) {
    assert.equal(pairingProof(fixture.devicePrivateKey, fixture.serverPublicKey, fixture.sessionId, row.path, row.body, row.side),
      row.proof);
  }
  assert.throws(() => parseWire('{"a":{"x":1,"\\u0078":2}}'), /INVALID_MESSAGE/);
  assert.throws(() => parseWire(Buffer.of(0xff)), /INVALID_MESSAGE/);
  const fragments = new Fragments();
  const message = Buffer.alloc(100000, 45);
  const packets = [...fragments.split(message)];
  assert.throws(() => fragments.add(packets[1]), /INVALID_MESSAGE/);
  assert.equal(fragments.add(packets[0]), undefined);
  assert.equal(fragments.add(packets[1]), undefined);
  assert.deepEqual(fragments.add(packets[2]), message);
});
