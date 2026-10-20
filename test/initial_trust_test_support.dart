import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/certificate_fingerprint_store.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';

Map<String, dynamic> trustResponse(Map<String, dynamic> request) {
  final messages = jsonDecode(
    File(
      'docs/fixtures/outreach/certificate-renewal-v1/device-messages.json',
    ).readAsStringSync(),
  );
  if (request['action'] == 'confirm_bootstrap') {
    return {
      'ok': true,
      'request_id': 'confirm',
      for (final f in [
        'action',
        'bootstrap_id',
        'authority_kid',
        'certificate_sha256',
        'generation',
      ])
        f: request[f],
      'state': 'confirmed',
    };
  }
  return {
    'ok': true,
    'request_id': 'bootstrap',
    'action': 'bootstrap',
    'bootstrap_id': 'b9f03378-6a1b-4ec1-956d-2b3024f82a2f',
    for (final f in [
      'dashboard_id',
      'project_id',
      'device_id',
      'worker_id',
      'api_base_url',
      'certificate_sha256',
    ])
      f: request[f],
    'generation': 1,
    'renewal_authority': messages['bootstrap_response']['renewal_authority'],
  };
}

/// Preconfirmed state isolates existing sync regressions from bootstrap tests.
/// Never used by application code or evidence of an authenticated bootstrap.
Future<void> seedConfirmedTrust(
  OutreachRepository repo,
  CertificateFingerprintStore pins,
  DeviceCredentialStore credentials,
) async {
  final identity = await repo.appIdentity();
  final config = await repo.dashboardPairingPreparation();
  final bytes = (await Sha256().hash(
    utf8.encode((await credentials.read())!),
  )).bytes;
  final snapshot = <String, dynamic>{
    'project_id': identity['project_id'],
    'dashboard_id': config['dashboard_id'],
    'device_id': identity['device_id'],
    'worker_id': repo.currentWorkerId(),
    'api_base_url': config['dashboard_url'],
    'paired_at': config['paired_at'],
    'credential_sha256': bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(),
    'certificate_sha256': (await pins.read())!.toLowerCase(),
  };
  await repo.database.connection.insert('initial_certificate_trust', {
    'singleton_id': 1,
    'state': 'confirmed',
    'snapshot_json': jsonEncode(snapshot),
    'bootstrap_json': jsonEncode(trustResponse(snapshot)),
  });
}
