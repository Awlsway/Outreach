import 'dart:convert';
import 'dart:io';

import 'package:ansvk_outreach/sync/qr_pairing_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fixtureRoot = 'docs/fixtures/outreach/qr-v1';
  final now = DateTime.utc(2026, 9, 23, 8, 2);

  test('accepts the exact LAN QR v1 fixture', () {
    final rawPayload = File('$fixtureRoot/valid-payload.json').readAsStringSync();
    final qr = File('$fixtureRoot/valid-qr.txt').readAsStringSync().trim();
    final encoded = qr.substring(QrPairingPayload.prefix.length);
    final padding = '=' * ((4 - encoded.length % 4) % 4);

    expect(utf8.decode(base64Url.decode('$encoded$padding')), rawPayload.trim());
    final parsed = QrPairingPayload.parse(qr, clock: () => now);
    expect(parsed.apiBaseUrl.toString(), 'https://192.168.1.4:3443/api/v1');
    expect(parsed.pairingCode, '012345');
    expect(parsed.certificateSha256, List.filled(64, 'a').join());
  });
}
