import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ansvk_outreach/app.dart';
import 'package:ansvk_outreach/auth/auth_service.dart';
import 'package:ansvk_outreach/auth/session_controller.dart';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart' as data;
import 'package:ansvk_outreach/hotspots/location_service.dart';
import 'package:ansvk_outreach/sync/certificate_fingerprint_store.dart';
import 'package:ansvk_outreach/sync/certificate_renewal_qr.dart';
import 'package:ansvk_outreach/sync/certificate_renewal_service.dart';
import 'package:ansvk_outreach/sync/initial_certificate_trust.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/manual_sync_runner.dart';
import 'package:ansvk_outreach/sync/pairing_response.dart';
import 'package:ansvk_outreach/sync/peer_certificate_verifier.dart';
import 'package:ansvk_outreach/sync/secure_sync_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'auth_test_support.dart';
import 'certificate_renewal_qr_test_support.dart';
import 'hotspot_test_support.dart';
import 'initial_trust_test_support.dart';
import 'peer_certificate_test_support.dart';

class RenewalUiPeer implements SyncHttpsConnection {
  RenewalUiPeer(this.der, this.respond);
  final List<int> der;
  final Future<SyncBatchReply> Function(Uri, String, String?) respond;
  bool closed = false;
  @override
  List<int> get certificateDer => der;
  @override
  Future<SyncBatchReply> request(
    Uri uri,
    String method,
    String credential,
    String? body,
  ) {
    expect(credential, 'synthetic-credential');
    return respond(uri, method, body);
  }

  @override
  void close() => closed = true;
}

class RenewalUiHarness {
  late AppDatabase db;
  late SessionController session;
  late data.OutreachRepository repo;
  late RenewalTestSigner signer;
  final pins = CertificateFingerprintStore();
  final credentials = DeviceCredentialStore.memory();
  late Map<String, Object?> identity;
  late Map<String, Object?> original;
  String qr = '';
  DateTime now = DateTime.now().toUtc();
  List<int> liveDer = [4, 5, 6];
  final paths = <String>[];
  final peers = <RenewalUiPeer>[];
  final receipts = <String, Map<String, dynamic>>{};
  final grants = <String, VerifiedCertificateRenewal>{};
  Completer<void>? holdClaim, holdConfirm;
  bool loseClaim = false, loseConfirm = false, corruptReceipt = false;
  int uploads = 0;
  ValueChanged<String>? lastScanned;

  InitialCertificateTrust get trust => InitialCertificateTrust(
    repository: repo,
    legacyPins: pins,
    credentials: credentials,
    connector: connect,
    clock: () => now,
  );

  Future<void> init({bool paired = true}) async {
    sqfliteFfiInit();
    installPeerCertificateMock();
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    session = SessionController(AuthService(db, hasher: TestHasher()));
    await session.signIn('synthetic-worker', 'password1', register: true);
    repo = data.OutreachRepository(
      db,
      currentWorkerId: () => session.currentWorkerId,
      sessionRevision: () => session.revision,
    );
    final hotspot = await repo.createHotspot(name: 'preserved-hotspot');
    await repo.createEncounter({
      'hotspot_id': hotspot,
      'client_code': 'synthetic-client',
      'dist_3cc': 5,
      'hiv': 'Non reactive',
    });
    identity = await repo.appIdentity();
    signer = await RenewalTestSigner.create();
    if (paired) {
      await pins.write(await PeerCertificateVerifier.sha256Hex([1, 2, 3]));
      await credentials.write('synthetic-credential');
      await repo.saveDashboardPairing(
        'https://192.168.1.50:3443/api/v1',
        '123456',
      );
      await repo.applyDashboardPairing(
        PairingSuccess(
          requestId: 'synthetic',
          dashboardId: 'synthetic-office',
          dashboardName: 'Synthetic office',
          deviceId: identity['device_id'] as String,
          workerId: session.currentWorkerId!,
          deviceCredential: 'synthetic-credential',
          pairedAt: now,
          serverTime: now,
        ),
      );
      await seedConfirmedTrust(repo, pins, credentials);
      final saved = (await db.connection.query(
        InitialCertificateTrust.table,
      )).single;
      final proof = jsonDecode(saved['bootstrap_json'] as String);
      proof['renewal_authority'] = signer.authority;
      await db.connection.update(InitialCertificateTrust.table, {
        'bootstrap_json': jsonEncode(proof),
      });
      qr = await makeQr();
    }
    original = await snapshot();
  }

  Future<Map<String, Object?>> snapshot() async => {
    for (final table in [
      'workers',
      'app_identity',
      'dashboard_connection',
      'hotspots',
      'encounters',
      'audit_operations',
      'sync_outbox',
      'sync_confirmations',
      'sync_state',
      InitialCertificateTrust.table,
    ])
      table: await db.connection.query(table),
    'credential': await credentials.read(),
  };
  Future<List<data.Row>> history() =>
      db.connection.query('certificate_renewals', orderBy: 'sequence');
  Future<void> preserved() async => expect(await snapshot(), original);

  Future<String> makeQr() async {
    final context = await trust.renewalContext();
    final iat = now.millisecondsSinceEpoch ~/ 1000;
    final value = await signer.signed(
      changes: {
        'dashboard_id': context.dashboardId,
        'project_id': context.projectId,
        'device_id': context.deviceId,
        'worker_id': context.workerId,
        'api_base_url': context.apiBaseUrl,
        'grant_id': const Uuid().v4(),
        'from_certificate_sha256': context.certificateSha256,
        'from_generation': context.generation,
        'to_certificate_sha256': (await PeerCertificateVerifier.sha256Hex(
          liveDer,
        )).toLowerCase(),
        'to_generation': context.generation + 1,
        'iat': iat,
        'exp': iat + 300,
      },
    );
    final g = await trust.reviewRenewalQr(value);
    grants[g.grantId] = g;
    return value;
  }

  Future<void> pending({bool confirmation = false}) async {
    final g = await trust.reviewRenewalQr(qr);
    loseClaim = !confirmation;
    loseConfirm = confirmation;
    await expectLater(
      CertificateRenewalService(trust: trust).accept(g),
      throwsA(isA<SocketException>()),
    );
    loseClaim = false;
    loseConfirm = false;
  }

  Future<SyncHttpsConnection> connect(Uri _) async {
    final peer = RenewalUiPeer([...liveDer], respond);
    peers.add(peer);
    return peer;
  }

  Future<SyncBatchReply> respond(Uri uri, String method, String? body) async {
    paths.add(uri.path);
    if (uri.path == '/api/v1/sync/status') {
      expect(method, 'GET');
      expect(body, null);
      return SyncBatchReply(200, {
        'ok': true,
        'request_id': 'synthetic',
        'device_id': identity['device_id'],
        'worker_id': session.currentWorkerId,
        'device_status': 'active',
        'cleanup_keep_days': 7,
        'server_time': now.toIso8601String(),
        'warnings': [],
        'last_successful_sync_at': null,
        'last_accepted_sequence': null,
        'last_accepted_operation_id': null,
      });
    }
    expect(method, 'POST');
    final request = jsonDecode(body!) as Map<String, dynamic>;
    if (uri.path == '/api/v1/sync/batches') {
      uploads++;
      expect(request['schema_version'], 6);
      return SyncBatchReply(200, {
        'ok': true,
        'request_id': 'synthetic',
        'batch_id': request['batch_id'],
        'dashboard_received_at': now.toIso8601String(),
        'warnings': [],
        'retry_after_seconds': null,
        'rejected': [],
        'accepted': [
          for (final op in request['operations'])
            {
              for (final field in [
                'operation_id',
                'entity_type',
                'entity_id',
                'revision',
                'sequence',
              ])
                field: op[field],
              'duplicate': false,
              'accepted_at': now.toIso8601String(),
            },
        ],
      });
    }
    if (uri.path.endsWith('/claim')) {
      final g = grants[request['grant_id']]!;
      expect(request['grant_digest'], g.grantDigest);
      final replay = receipts.containsKey(g.grantId);
      final receipt = receipts.putIfAbsent(
        g.grantId,
        () => {
          'receipt_id': const Uuid().v4(),
          'grant_id': g.grantId,
          'grant_digest': g.grantDigest,
          'dashboard_id': g.context.dashboardId,
          'project_id': g.context.projectId,
          'device_id': g.context.deviceId,
          'worker_id': g.context.workerId,
          'api_base_url': g.context.apiBaseUrl,
          'from_certificate_sha256': g.context.certificateSha256,
          'from_generation': g.context.generation,
          'to_certificate_sha256': g.toCertificateSha256,
          'to_generation': g.toGeneration,
          'claimed_at': now.millisecondsSinceEpoch ~/ 1000,
        },
      );
      await holdClaim?.future;
      if (loseClaim) throw const SocketException('Synthetic lost claim');
      return SyncBatchReply(replay ? 200 : 201, {
        'ok': true,
        'request_id': 'synthetic-claim',
        'receipt': {
          ...receipt,
          if (corruptReceipt) 'device_id': 'wrong-device',
        },
      });
    }
    expect(uri.path, '/api/v1/certificate-renewals/confirm');
    final receipt = receipts[request['grant_id']]!;
    expect(request['receipt_id'], receipt['receipt_id']);
    await holdConfirm?.future;
    if (loseConfirm) throw const SocketException('Synthetic lost confirmation');
    return SyncBatchReply(200, {
      'ok': true,
      'request_id': 'synthetic-confirm',
      'receipt_id': receipt['receipt_id'],
      'grant_digest': receipt['grant_digest'],
      'device_id': receipt['device_id'],
      'certificate_sha256': receipt['to_certificate_sha256'],
      'generation': receipt['to_generation'],
      'state': 'confirmed',
    });
  }

  Widget scanner(ValueChanged<String> onScanned, VoidCallback onCancel) {
    lastScanned = onScanned;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synthetic scanner'),
        leading: BackButton(onPressed: onCancel),
      ),
      body: Center(
        child: FilledButton(
          key: const ValueKey('emit-synthetic-qr'),
          onPressed: () => onScanned(qr),
          child: const Text('Synthetic scan'),
        ),
      ),
    );
  }

  Widget app() => OutreachApp(
    session: session,
    hasAccounts: true,
    location: HotspotLocationService(gateway: TestLocationGateway()),
    certificateFingerprintStore: pins,
    deviceCredentialStore: credentials,
    syncConnector: connect,
    renewalScannerBuilder: scanner,
  );
  Future<void> dispose() async {
    if (holdClaim != null && !holdClaim!.isCompleted) holdClaim!.complete();
    if (holdConfirm != null && !holdConfirm!.isCompleted) {
      holdConfirm!.complete();
    }
    await db.close();
    clearPeerCertificateMock();
  }
}

Future<void> flushRenewalUi(WidgetTester tester, RenewalUiHarness h) async {
  await tester.runAsync(() async {
    // Do not queue a real query behind a transaction awaiting a fake-zone pump.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> waitRenewalUi(
  WidgetTester tester,
  RenewalUiHarness h,
  bool Function() ready, {
  int maxPumps = 80,
}) async {
  for (var i = 0; i < maxPumps && !ready(); i++) {
    await flushRenewalUi(tester, h);
  }
  final visibleText = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .where((text) => !text.contains('ansvk-outreach://'))
      .join(' | ');
  expect(
    ready(),
    true,
    reason: 'Renewal UI did not reach the expected state: $visibleText',
  );
  expect(tester.takeException(), isNull);
}

Future<void> tapRenewalUi(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> openRenewalUi(WidgetTester tester, RenewalUiHarness h) async {
  await tester.pumpWidget(h.app());
  await flushRenewalUi(tester, h);
  await tapRenewalUi(tester, 'open-sync-status');
  await waitRenewalUi(
    tester,
    h,
    () => find
        .byKey(const ValueKey('open-certificate-renewal'))
        .evaluate()
        .isNotEmpty,
  );
  await tapRenewalUi(tester, 'open-certificate-renewal');
  await waitRenewalUi(
    tester,
    h,
    () => find.byKey(const ValueKey('renewal-state')).evaluate().isNotEmpty,
  );
}

Future<void> reviewRenewalUi(WidgetTester tester, RenewalUiHarness h) async {
  await tapRenewalUi(tester, 'scan-renewal-qr');
  await tapRenewalUi(tester, 'emit-synthetic-qr');
  await waitRenewalUi(
    tester,
    h,
    () => find.text('Continue renewal').evaluate().isNotEmpty,
  );
}
