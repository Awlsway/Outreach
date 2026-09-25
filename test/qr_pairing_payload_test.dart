import 'dart:convert';

import 'package:ansvk_outreach/sync/qr_pairing_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 23, 8);
  Map<String, Object?> valid() => {
    'type': 'ansvk-outreach-pairing',
    'version': 1,
    'protocol': 'ansvk-outreach-sync',
    'protocol_version': 1,
    'project_id': 'ansvk_outreach',
    'dashboard_id': 'office-dashboard-001',
    'api_base_url': 'https://192.168.1.4:3443/api/v1',
    'certificate_sha256': 'a' * 64,
    'pairing_code': '012345',
    'issued_at': '2026-09-23T08:00:00Z',
    'expires_at': '2026-09-23T08:05:00Z',
  };
  String qr(Map<String, Object?> payload) =>
      '${QrPairingPayload.prefix}${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';

  test('parses exact QR v1 values and preserves a leading-zero code', () {
    final result = QrPairingPayload.parse(qr(valid()), clock: () => now);
    expect(result.dashboardId, 'office-dashboard-001');
    expect(result.apiBaseUrl.toString(), 'https://192.168.1.4:3443/api/v1');
    expect(result.pairingCode, '012345');
    expect(result.certificateSha256, 'a' * 64);
  });

  test('rejects unknown fields and wrong project or protocol', () {
    expect(
      () => QrPairingPayload.parse(
        qr({...valid(), 'unexpected': true}),
        clock: () => now,
      ),
      throwsFormatException,
    );
    for (final changed in [
      {...valid(), 'project_id': 'another_project'},
      {...valid(), 'protocol_version': 2},
    ]) {
      expect(
        () => QrPairingPayload.parse(qr(changed), clock: () => now),
        throwsFormatException,
      );
    }
  });

  test('rejects expired, overlong, future and malformed validity windows', () {
    for (final changed in [
      {...valid(), 'expires_at': '2026-09-23T08:00:00Z'},
      {...valid(), 'expires_at': '2026-09-23T08:05:01Z'},
      {
        ...valid(),
        'issued_at': '2026-09-23T08:01:01Z',
        'expires_at': '2026-09-23T08:05:00Z',
      },
      {...valid(), 'issued_at': '2026-09-23 08:00:00Z'},
    ]) {
      expect(
        () => QrPairingPayload.parse(qr(changed), clock: () => now),
        throwsFormatException,
      );
    }
  });

  test('rejects unsafe address, fingerprint, code and encoding', () {
    for (final changed in [
      {...valid(), 'api_base_url': 'http://192.168.1.4:3443/api/v1'},
      {...valid(), 'api_base_url': 'https://user@192.168.1.4:3443/api/v1'},
      {...valid(), 'api_base_url': 'https://192.168.1.4:3443/api/v1?x=1'},
      {...valid(), 'certificate_sha256': 'A' * 64},
      {...valid(), 'pairing_code': '12345'},
    ]) {
      expect(
        () => QrPairingPayload.parse(qr(changed), clock: () => now),
        throwsFormatException,
      );
    }
    expect(
      () => QrPairingPayload.parse('${QrPairingPayload.prefix}%%%'),
      throwsFormatException,
    );
  });
}
