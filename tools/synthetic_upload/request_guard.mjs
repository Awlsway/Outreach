// Separate U1 synthetic-upload scope. The S3 pairing guard remains unchanged.
const routes = {
  device: new Set([
    'GET /api/v1/health', 'GET /api/v1/sync/status',
    'POST /api/v1/pairing/requests', 'POST /api/v1/sync/batches',
  ]),
  browser: new Set([
    'GET /operator', 'GET /api/setup-status', 'POST /api/setup-first-admin',
    'POST /api/login', 'POST /api/logout', 'GET /api/me',
    'POST /api/outreach/pairing-codes', 'GET /api/outreach/devices', 'GET /api/outreach/status',
  ]),
};

export function syntheticUploadHandler(surface, existingHandler) {
  if (!routes[surface] || typeof existingHandler !== 'function') throw new Error('Invalid synthetic scope.');
  return (request, response) => {
    const target = request.url;
    const plain = typeof target === 'string' && /^\/[A-Za-z0-9/_-]+$/.test(target);
    const cancel = surface === 'browser' && request.method === 'POST' && plain &&
      /^\/api\/outreach\/pairing-codes\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/cancel$/i.test(target);
    if (plain && (cancel || routes[surface].has(`${request.method} ${target}`))) return existingHandler(request, response);
    response.writeHead(403, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', Connection: 'close' });
    response.end(JSON.stringify({ success: false, error: 'Blocked by restricted synthetic-upload scope.' }));
  };
}
