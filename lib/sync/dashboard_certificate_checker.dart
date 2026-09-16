import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'certificate_fingerprint_store.dart';

typedef CertificateDerProbe = Future<List<int>> Function(
  Uri uri,
  Duration timeout,
);

class DashboardCertificateChecker {
  DashboardCertificateChecker({
    CertificateDerProbe? probe,
    this.timeout = const Duration(seconds: 10),
  }) : _probe = probe ?? _secureSocketProbe;

  final CertificateDerProbe _probe;
  final Duration timeout;

  Future<DashboardCertificateCheckResult> check({
    required String dashboardUrl,
    required String expectedFingerprint,
  }) async {
    final uri = Uri.tryParse(dashboardUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return const DashboardCertificateCheckResult.invalidAddress();
    }

    final expected = CertificateFingerprintStore.normalize(expectedFingerprint);
    if (!CertificateFingerprintStore.isValidSha256(expected)) {
      return const DashboardCertificateCheckResult.invalidFingerprint();
    }

    try {
      final certificateDer = await _probe(uri, timeout);
      final actual = await sha256Hex(certificateDer);
      if (actual == expected) {
        return DashboardCertificateCheckResult.match(
          fingerprintHint: CertificateFingerprintStore.hint(actual),
        );
      }
      return DashboardCertificateCheckResult.mismatch(
        expectedHint: CertificateFingerprintStore.hint(expected),
        actualHint: CertificateFingerprintStore.hint(actual),
      );
    } catch (_) {
      return const DashboardCertificateCheckResult.unavailable();
    }
  }

  static Future<String> sha256Hex(List<int> bytes) async {
    final digest = await Sha256().hash(bytes);
    final buffer = StringBuffer();
    for (final byte in digest.bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString().toUpperCase();
  }

  static Future<List<int>> _secureSocketProbe(
    Uri uri,
    Duration timeout,
  ) async {
    final socket = await SecureSocket.connect(
      uri.host,
      uri.hasPort ? uri.port : 443,
      timeout: timeout,
      onBadCertificate: (_) => true,
    );
    try {
      final certificate = socket.peerCertificate;
      if (certificate == null) {
        throw const TlsException('No dashboard certificate was presented.');
      }
      return certificate.der;
    } finally {
      socket.destroy();
    }
  }
}

enum DashboardCertificateCheckStatus {
  match,
  mismatch,
  unavailable,
  invalidAddress,
  invalidFingerprint,
}

class DashboardCertificateCheckResult {
  const DashboardCertificateCheckResult._({
    required this.status,
    required this.message,
    this.fingerprintHint,
    this.expectedHint,
    this.actualHint,
  });

  const DashboardCertificateCheckResult.match({required String fingerprintHint})
    : this._(
        status: DashboardCertificateCheckStatus.match,
        message: 'Certificate matches saved fingerprint.',
        fingerprintHint: fingerprintHint,
      );

  const DashboardCertificateCheckResult.mismatch({
    required String expectedHint,
    required String actualHint,
  }) : this._(
         status: DashboardCertificateCheckStatus.mismatch,
         message:
             'Certificate does not match. Do not sync until the data assistant confirms the dashboard fingerprint.',
         expectedHint: expectedHint,
         actualHint: actualHint,
       );

  const DashboardCertificateCheckResult.unavailable()
    : this._(
        status: DashboardCertificateCheckStatus.unavailable,
        message:
            'Could not reach the dashboard certificate. Check Wi-Fi, address, and dashboard status.',
      );

  const DashboardCertificateCheckResult.invalidAddress()
    : this._(
        status: DashboardCertificateCheckStatus.invalidAddress,
        message: 'Enter a valid HTTPS dashboard address first.',
      );

  const DashboardCertificateCheckResult.invalidFingerprint()
    : this._(
        status: DashboardCertificateCheckStatus.invalidFingerprint,
        message: 'Enter the full SHA-256 certificate fingerprint first.',
      );

  final DashboardCertificateCheckStatus status;
  final String message;
  final String? fingerprintHint;
  final String? expectedHint;
  final String? actualHint;

  bool get matched => status == DashboardCertificateCheckStatus.match;
}
