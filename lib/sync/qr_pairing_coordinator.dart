import '../database/outreach_repository.dart';
import 'certificate_fingerprint_store.dart';
import 'dashboard_pairing_service.dart';
import 'device_credential_store.dart';
import 'pairing_request_builder.dart';
import 'qr_pairing_payload.dart';

/// Connects a validated QR envelope to the existing pinned pairing request.
///
/// The QR contains only short-lived enrollment information. The permanent
/// credential is still issued by the dashboard and stored only after the
/// existing pairing service validates its response.
class QrPairingCoordinator {
  QrPairingCoordinator({
    required this.repository,
    required this.certificateFingerprintStore,
    required this.deviceCredentialStore,
    required this.appVersion,
    this.transport,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final OutreachRepository repository;
  final CertificateFingerprintStore certificateFingerprintStore;
  final DeviceCredentialStore deviceCredentialStore;
  final String appVersion;
  final PairingTransport? transport;
  final DateTime Function() _clock;

  Future<DashboardPairingAttemptResult> pairFromQr(String scanned) async {
    final payload = QrPairingPayload.parse(scanned, clock: _clock);
    await repository.saveDashboardPairing(
      payload.apiBaseUrl.toString(),
      payload.pairingCode,
    );
    await certificateFingerprintStore.write(payload.certificateSha256);
    return DashboardPairingService(
      repository: repository,
      credentialStore: deviceCredentialStore,
      requestBuilder: PairingRequestBuilder(
        appVersion: appVersion,
        clock: _clock,
      ),
      transport: transport,
    ).pair(expectedCertificateFingerprint: payload.certificateSha256);
  }
}
