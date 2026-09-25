import 'package:flutter/foundation.dart';

import '../database/outreach_repository.dart';
import 'certificate_fingerprint_store.dart';
import 'device_credential_store.dart';
import 'secure_sync_transport.dart';

/// A read-only credential check used only by the debug/UAT APK.
///
/// It calls GET /api/v1/sync/status and never constructs or sends a sync
/// batch. The device credential stays inside [SecureSyncTransport].
class DebugDashboardAccessCheck {
  DebugDashboardAccessCheck({
    required this.repository,
    required this.fingerprintStore,
    required this.credentialStore,
    this.connector,
  });

  final OutreachRepository repository;
  final CertificateFingerprintStore fingerprintStore;
  final DeviceCredentialStore credentialStore;
  final SyncHttpsConnector? connector;

  Future<String> run() async {
    assert(kDebugMode, 'Dashboard access check is debug-only');
    final config = await repository.dashboardPairingPreparation();
    final fingerprint = await fingerprintStore.read();
    if (config['status'] != 'Paired' ||
        config['dashboard_url'] is! String ||
        fingerprint == null) {
      return 'Dashboard access is not configured for this phone.';
    }
    try {
      final reply = await SecureSyncTransport(
        baseUri: Uri.parse(config['dashboard_url'] as String),
        fingerprint: fingerprint,
        credentialStore: credentialStore,
        connector: connector,
      ).checkStatus();
      if (reply.httpStatus == 200 && reply.response['ok'] == true) {
        return 'Dashboard access is active. No records were sent.';
      }
      final code = reply.response['error_code'];
      if (code == 'device_revoked') {
        return 'Dashboard access was revoked. No records were sent.';
      }
      if (code == 'device_retired') {
        return 'This phone was retired. Scan a new dashboard QR to enroll again. No records were sent.';
      }
      return 'Dashboard rejected this phone. No records were sent.';
    } catch (_) {
      return 'Could not check dashboard access. No records were sent.';
    }
  }
}
