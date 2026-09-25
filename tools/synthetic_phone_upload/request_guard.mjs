import { syntheticUploadHandler } from '../synthetic_upload/request_guard.mjs';

// Check socket source, not forwarded headers. Existing exact routes stay mandatory.
export function syntheticPhoneHandler(surface, handler, sourceIp, available) {
  const scoped = syntheticUploadHandler(surface, handler);
  return (request, response) => {
    if (!available() || (surface === 'device' && request.socket.remoteAddress !== sourceIp)) {
      response.writeHead(403, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', Connection: 'close' });
      response.end(JSON.stringify({ ok: false, error_code: 'test_window_blocked', message: 'Phone test window is not available.' }));
      return;
    }
    scoped(request, response);
  };
}
