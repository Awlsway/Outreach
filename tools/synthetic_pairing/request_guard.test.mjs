import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { test } from 'node:test';
import { pairingOnlyHandler } from './request_guard.mjs';

async function withServer(surface, handler, run) {
  const server = http.createServer(pairingOnlyHandler(surface, handler));
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try { await run(`http://127.0.0.1:${server.address().port}`); }
  finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
}

test('upload and status requests never reach parsing or operation storage', async () => {
  let parsedBodies = 0;
  const storedOperations = [];
  await withServer('device', (req, res) => {
    parsedBodies++;
    storedOperations.push(req.url);
    res.end('Unexpected backend processing');
  }, async base => {
    for (const route of ['/api/v1/sync/batches', '/api/v1/sync/status', '/api/v1/pairing/requests/', '/api/v1/%70airing/requests', '/api/v1/pairing/requests?upload=true']) {
      const result = await fetch(base + route, {method: 'POST', body: '{invalid JSON'});
      assert.equal(result.status, 403, route);
      assert.equal((await result.json()).success, false);
    }
    assert.equal(parsedBodies, 0);
    assert.deepEqual(storedOperations, []);
  });
});

test('permitted pairing retains existing backend rejection and health behavior', async () => {
  const calls = [];
  await withServer('device', (req, res) => {
    calls.push(`${req.method} ${req.url}`);
    res.writeHead(req.method === 'POST' ? 401 : 200);
    res.end('Existing backend result');
  }, async base => {
    assert.equal((await fetch(base + '/api/v1/health')).status, 200);
    assert.equal((await fetch(base + '/api/v1/pairing/requests', {method:'POST'})).status, 401);
    assert.equal((await fetch(base + '/api/v1/pairing/requests')).status, 403);
    assert.deepEqual(calls, ['GET /api/v1/health', 'POST /api/v1/pairing/requests']);
  });
});

test('browser guard blocks MIS/LMIS mutations and device revocation', async () => {
  let backendCalls = 0;
  await withServer('browser', (_req, res) => { backendCalls++; res.end(); }, async base => {
    for (const route of ['/api/upload', '/api/reset', '/api/users', '/api/outreach/backups', '/api/outreach/devices/test/revoke', '/api/outreach/pairing-codes?bypass=true']) {
      assert.equal((await fetch(base + route, {method:'POST', body:'{}'})).status, 403, route);
    }
    assert.equal(backendCalls, 0);
  });
});

test('code issuance and cancellation still require existing session authorization', async () => {
  let authorizationCalls = 0;
  await withServer('browser', (_req, res) => {
    authorizationCalls++;
    res.writeHead(401); res.end('Authentication required');
  }, async base => {
    const routes = ['/api/outreach/pairing-codes', '/api/outreach/pairing-codes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/cancel'];
    for (const route of routes) assert.equal((await fetch(base + route, {method:'POST'})).status, 401);
    assert.equal(authorizationCalls, 2);
  });
});

test('operator page is allowed only on browser surface with exact GET route', async () => {
  let rendered = 0;
  await withServer('browser', (_req, res) => { rendered++; res.end('Private operator page'); }, async base => {
    assert.equal((await fetch(base + '/operator')).status, 200);
    assert.equal((await fetch(base + '/operator', {method:'POST'})).status, 403);
    assert.equal((await fetch(base + '/operator?debug=true')).status, 403);
    assert.equal(rendered, 1);
  });
  await withServer('device', () => { assert.fail('Operator page reached device backend'); }, async base => {
    assert.equal((await fetch(base + '/operator')).status, 403);
  });
});

test('invalid guard configuration fails closed', () => {
  assert.throws(() => pairingOnlyHandler('unknown', () => {}));
  assert.throws(() => pairingOnlyHandler('device', null));
});
