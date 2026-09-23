import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticPhoneHandler } from './request_guard.mjs';

function attempt({source='192.168.1.4', available=true, url='/api/v1/sync/batches', headers={}} = {}) {
  let forwarded=false, status;
  syntheticPhoneHandler('device', () => { forwarded=true; }, '192.168.1.4', () => available)(
    {method:'POST', url, socket:{remoteAddress:source}, headers},
    {writeHead(code) { status=code; }, end() {}});
  return {forwarded,status};
}
test('approved socket source forwards only exact upload route', () => {
  assert.equal(attempt().forwarded,true);
  assert.deepEqual(attempt({url:'/api/v1/sync/batches?extra=1'}),{forwarded:false,status:403});
});
test('another phone cannot spoof approval through forwarded headers', () => {
  assert.deepEqual(attempt({source:'192.168.1.9',headers:{'x-forwarded-for':'192.168.1.4'}}),{forwarded:false,status:403});
});
test('unavailable or expired window blocks approved phone too', () => {
  assert.deepEqual(attempt({available:false}),{forwarded:false,status:403});
});
