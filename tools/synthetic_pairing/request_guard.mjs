// Local synthetic-test tooling only. Never mount this on the office dashboard.
const deviceRoutes = new Set([
  'GET /api/v1/health',
  'POST /api/v1/pairing/requests',
]);

const browserRoutes = new Set([
  'GET /operator',
  'GET /api/setup-status',
  'POST /api/setup-first-admin',
  'POST /api/login',
  'POST /api/logout',
  'GET /api/me',
  'POST /api/outreach/pairing-codes',
  'GET /api/outreach/devices',
  'GET /api/outreach/status',
]);

function routeKey(request) {
  // Reject alternate encodings, query strings and ambiguous paths instead of
  // letting the underlying router interpret a wider set of routes.
  const target = request.url;
  if (typeof target !== 'string' || !/^\/[A-Za-z0-9/_-]+$/.test(target)) return null;
  return `${request.method} ${target}`;
}

function permitted(request, surface) {
  const key = routeKey(request);
  if (!key) return false;
  if (surface === 'device') return deviceRoutes.has(key);
  if (surface === 'browser') {
    if (browserRoutes.has(key)) return true;
    return request.method === 'POST' &&
      /^\/api\/outreach\/pairing-codes\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/cancel$/i.test(request.url);
  }
  return false;
}

export function pairingOnlyHandler(surface, existingHandler) {
  if (!['device', 'browser'].includes(surface)) throw new Error('Unknown test surface.');
  if (typeof existingHandler !== 'function') throw new TypeError('Existing handler required.');
  return (request, response) => {
    if (permitted(request, surface)) return existingHandler(request, response);
    response.writeHead(403, {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      Connection: 'close',
    });
    response.end(JSON.stringify({success: false, error: 'Blocked by synthetic pairing-only test scope.'}));
  };
}
