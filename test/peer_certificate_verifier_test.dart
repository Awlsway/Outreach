import 'package:ansvk_outreach/sync/peer_certificate_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'peer_certificate_test_support.dart';

void main() {
  late Map<String, Object?> metadata;
  late String pin;
  final now = DateTime.utc(2026, 9, 28);
  Future<void> check({String host = '192.168.1.50', String? fingerprint}) =>
      PeerCertificateVerifier(clock: () => now).verify(
        endpoint: Uri.parse('https://$host:3443/api/v1'),
        der: [1, 2, 3],
        fingerprint: fingerprint ?? pin,
      );
  Matcher fails(String code) => throwsA(
    isA<CertificateVerificationFailure>().having((e) => e.code, 'code', code),
  );
  setUp(() async {
    metadata = installPeerCertificateMock();
    pin = await PeerCertificateVerifier.sha256Hex([1, 2, 3]);
  });
  tearDown(clearPeerCertificateMock);
  test('NotBefore inclusive and NotAfter exclusive UTC boundaries', () async {
    metadata['notBefore'] = now.millisecondsSinceEpoch;
    metadata['notAfter'] = now
        .add(const Duration(seconds: 1))
        .millisecondsSinceEpoch;
    await check();
    metadata['notBefore'] = now
        .subtract(const Duration(seconds: 1))
        .millisecondsSinceEpoch;
    metadata['notAfter'] = now.millisecondsSinceEpoch;
    await expectLater(check(), fails('expired'));
    metadata['notBefore'] = now
        .add(const Duration(milliseconds: 1))
        .millisecondsSinceEpoch;
    metadata['notAfter'] = now
        .add(const Duration(seconds: 1))
        .millisecondsSinceEpoch;
    await expectLater(check(), fails('not_yet_valid'));
  });
  test(
    'exact IP SAN required; DNS/CN/missing/other address cannot substitute',
    () async {
      for (final ips in [
        <String>[],
        ['192.168.1.5'],
        ['192.168.1.050'],
      ]) {
        metadata['ipSans'] = ips;
        await expectLater(check(), fails('endpoint_mismatch'));
      }
      await expectLater(
        check(host: 'dashboard.local'),
        fails('invalid_endpoint'),
      );
    },
  );
  test('wrong pin and unavailable or malformed metadata fail closed', () async {
    await expectLater(
      check(fingerprint: '0' * 64),
      fails('fingerprint_mismatch'),
    );
    metadata['notAfter'] = 'invalid';
    await expectLater(check(), fails('invalid_certificate'));
    clearPeerCertificateMock();
    await expectLater(check(), fails('invalid_certificate'));
  });
}
