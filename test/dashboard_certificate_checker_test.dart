import 'package:ansvk_outreach/sync/certificate_fingerprint_store.dart';
import 'package:ansvk_outreach/sync/dashboard_certificate_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches a dashboard certificate fingerprint', () async {
    final expected = await DashboardCertificateChecker.sha256Hex([1, 2, 3]);
    final checker = DashboardCertificateChecker(
      probe: (uri, timeout) async {
        expect(uri.host, '192.168.1.50');
        expect(uri.port, 3443);
        return [1, 2, 3];
      },
    );

    final result = await checker.check(
      dashboardUrl: 'https://192.168.1.50:3443/api/v1',
      expectedFingerprint: expected.toLowerCase(),
    );

    expect(result.status, DashboardCertificateCheckStatus.match);
    expect(
      result.fingerprintHint,
      CertificateFingerprintStore.hint(expected),
    );
  });

  test('reports mismatch without accepting the dashboard', () async {
    final expected = await DashboardCertificateChecker.sha256Hex([1, 2, 3]);
    final actual = await DashboardCertificateChecker.sha256Hex([9, 9, 9]);
    final checker = DashboardCertificateChecker(probe: (_, _) async => [9, 9, 9]);

    final result = await checker.check(
      dashboardUrl: 'https://dashboard.local/api/v1',
      expectedFingerprint: expected,
    );

    expect(result.status, DashboardCertificateCheckStatus.mismatch);
    expect(result.expectedHint, CertificateFingerprintStore.hint(expected));
    expect(result.actualHint, CertificateFingerprintStore.hint(actual));
  });

  test('rejects non-HTTPS dashboard address before probing', () async {
    var probed = false;
    final checker = DashboardCertificateChecker(
      probe: (_, _) async {
        probed = true;
        return [1];
      },
    );

    final result = await checker.check(
      dashboardUrl: 'http://192.168.1.50:3443/api/v1',
      expectedFingerprint: List.filled(64, '0').join(),
    );

    expect(result.status, DashboardCertificateCheckStatus.invalidAddress);
    expect(probed, isFalse);
  });

  test('rejects invalid fingerprint before probing', () async {
    var probed = false;
    final checker = DashboardCertificateChecker(
      probe: (_, _) async {
        probed = true;
        return [1];
      },
    );

    final result = await checker.check(
      dashboardUrl: 'https://192.168.1.50:3443/api/v1',
      expectedFingerprint: 'not-a-fingerprint',
    );

    expect(result.status, DashboardCertificateCheckStatus.invalidFingerprint);
    expect(probed, isFalse);
  });

  test('reports unavailable when certificate cannot be reached', () async {
    final checker = DashboardCertificateChecker(
      probe: (_, _) async => throw Exception('offline'),
    );

    final result = await checker.check(
      dashboardUrl: 'https://192.168.1.50:3443/api/v1',
      expectedFingerprint: List.filled(64, '0').join(),
    );

    expect(result.status, DashboardCertificateCheckStatus.unavailable);
  });
}

