import 'dart:convert';
import 'dart:io';

import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/certificate_fingerprint_store.dart';
import 'package:ansvk_outreach/sync/dashboard_pairing_service.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/qr_pairing_coordinator.dart';
import 'package:ansvk_outreach/sync/qr_pairing_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('validated QR supplies the pinned pairing request', () async {
    final directory = await Directory.systemTemp.createTemp('ansvk_qr_test_');
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/test.db',
    );
    final now = DateTime.utc(2026, 9, 23, 8, 2);
    String? workerId;
    final repository = OutreachRepository(
      database,
      currentWorkerId: () => workerId,
      clock: () => now,
    );
    workerId = await repository.createWorkerProfile('worker1');
    final certificateStore = CertificateFingerprintStore();
    final credentialStore = DeviceCredentialStore.memory();
    final transport = _SuccessfulTransport();

    final result = await QrPairingCoordinator(
      repository: repository,
      certificateFingerprintStore: certificateStore,
      deviceCredentialStore: credentialStore,
      appVersion: 'test',
      transport: transport,
      clock: () => now,
    ).pairFromQr(_validQr());

    expect(result.status, DashboardPairingAttemptStatus.paired);
    expect(
      transport.uri.toString(),
      'https://192.168.1.4:3443/api/v1/pairing/requests',
    );
    expect(transport.request['pairing_code'], '012345');
    expect(transport.expectedFingerprint, List.filled(64, 'A').join());
    expect((await repository.syncStatus())['dashboard_status'], 'Paired');
    expect(await credentialStore.read(), transport.credential);

    await database.close();
    await directory.delete(recursive: true);
  });
}

String _validQr() {
  const payload = {
    'type': 'ansvk-outreach-pairing',
    'version': 1,
    'protocol': 'ansvk-outreach-sync',
    'protocol_version': 1,
    'project_id': 'ansvk_outreach',
    'dashboard_id': 'office-dashboard-001',
    'api_base_url': 'https://192.168.1.4:3443/api/v1',
    'certificate_sha256':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'pairing_code': '012345',
    'issued_at': '2026-09-23T08:00:00Z',
    'expires_at': '2026-09-23T08:05:00Z',
  };
  return '${QrPairingPayload.prefix}${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';
}

class _SuccessfulTransport implements PairingTransport {
  final credential =
      'credential-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
  late Uri uri;
  late String expectedFingerprint;
  late Map<String, Object?> request;

  @override
  Future<PairingTransportResponse> postJson(
    Uri uri,
    String jsonBody, {
    required String expectedCertificateFingerprint,
  }) async {
    this.uri = uri;
    expectedFingerprint = expectedCertificateFingerprint;
    request = jsonDecode(jsonBody) as Map<String, Object?>;
    return PairingTransportResponse(
      statusCode: 200,
      body: jsonEncode({
        'ok': true,
        'request_id': 'request-1',
        'dashboard_id': 'office-dashboard-001',
        'dashboard_name': 'Office Dashboard',
        'device_id': request['device_id'],
        'worker_id': request['worker_id'],
        'device_credential': credential,
        'paired_at': '2026-09-23T08:02:00Z',
        'server_time': '2026-09-23T08:02:00Z',
      }),
    );
  }
}
