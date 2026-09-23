import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticUploadHandler } from './request_guard.mjs';

function check(surface, method, url) {
  let forwarded = false;
  let status;
  const response = { writeHead(code) { status = code; }, end() {} };
  syntheticUploadHandler(surface, () => { forwarded = true; })({method, url}, response);
  return {forwarded, status};
}
test('only exact four device endpoints are forwarded to normal middleware', () => {
  for (const [method, url] of [
    ['GET', '/api/v1/health'], ['GET', '/api/v1/sync/status'],
    ['POST', '/api/v1/pairing/requests'], ['POST', '/api/v1/sync/batches'],
  ]) {
    assert.equal(check('device', method, url).forwarded, true);
    for (const variant of [url + '?x=1', url + '/', url.replace('/api/', '/%61pi/')]) {
      assert.equal(check('device', method, variant).status, 403);
    }
    assert.equal(check('device', method === 'POST' ? 'GET' : 'POST', url).status, 403);
  }
});
test('unrelated and administration routes are blocked on device surface', () => {
  for (const url of ['/operator', '/api/login', '/api/upload', '/api/v1/sync/batches/extra', '/api/outreach/devices']) {
    assert.deepEqual(check('device', 'POST', url), {forwarded: false, status: 403});
  }
});
test('browser cannot upload; exact code cancellation forwards to auth', () => {
  assert.equal(check('browser', 'POST', '/api/v1/sync/batches').status, 403);
  assert.equal(check('browser', 'POST', '/api/outreach/pairing-codes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/cancel').forwarded, true);
  assert.equal(check('browser', 'POST', '/api/outreach/devices/test/revoke').status, 403);
});
test('invalid configuration fails closed', () => {
  assert.throws(() => syntheticUploadHandler('unknown', () => {}));
  assert.throws(() => syntheticUploadHandler('device', null));
});
