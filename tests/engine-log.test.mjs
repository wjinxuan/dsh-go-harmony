import test from 'node:test';import assert from 'node:assert/strict';import { Writable } from 'node:stream';
import { captureEngineStream } from '../runtime/engine-log.mjs';import {redactEngineLog}from '../runtime/engine-lifecycle.mjs';
test('log capture preserves stream return/callback and redacts tokens split across writes',async()=>{
 const received=[],lines=[];const stream=new Writable({write(chunk,encoding,callback){received.push(chunk.toString());callback();}});
 const restore=captureEngineStream(stream,line=>lines.push(redactEngineLog(line)));
 stream.write('Bearer private');await new Promise(r=>stream.write('-secret\nnext\n',r));assert.deepEqual(lines,['Bearer [redacted]','next']);
 stream.write('a'.repeat(20000));stream.write('secret\n');assert.equal(lines.at(-1),'[日志行过长，已省略]');
 restore();stream.write('after\n');assert.equal(lines.length,3);assert.equal(received.join('').includes('private-secret'),true);
});
