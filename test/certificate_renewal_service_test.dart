import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/certificate_fingerprint_store.dart';
import 'package:ansvk_outreach/sync/certificate_renewal_qr.dart';
import 'package:ansvk_outreach/sync/certificate_renewal_service.dart';
import 'package:ansvk_outreach/sync/certificate_renewal_state.dart';
import 'package:ansvk_outreach/sync/configured_manual_sync.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/initial_certificate_trust.dart';
import 'package:ansvk_outreach/sync/lifecycle_gate.dart';
import 'package:ansvk_outreach/sync/manual_sync_runner.dart';
import 'package:ansvk_outreach/sync/pairing_response.dart';
import 'package:ansvk_outreach/sync/peer_certificate_verifier.dart';
import 'package:ansvk_outreach/sync/secure_sync_transport.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:ansvk_outreach/sync/sync_run_control.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'certificate_renewal_qr_test_support.dart';
import 'initial_trust_test_support.dart';
import 'peer_certificate_test_support.dart';

class RenewalPeer implements SyncHttpsConnection {
  RenewalPeer(this.der, this.respond);
  final List<int> der;
  final Future<SyncBatchReply> Function(Uri, String) respond;
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
    expect(method, 'POST');
    expect(credential, 'synthetic-credential');
    return respond(uri, body!);
  }

  @override
  void close() {
    closed = true;
  }
}

class ThrowingCredentialStore extends DeviceCredentialStore {
  ThrowingCredentialStore() : super.memory();
  bool fail = false;
  @override
  Future<String?> read() {
    if (fail) throw StateError('Synthetic secure storage failure');
    return super.read();
  }
}

void main() {
  late AppDatabase db;
  late Directory dir;
  late String databasePath;
  late OutreachRepository repo;
  late InitialCertificateTrust trust;
  late CertificateRenewalService service;
  late CertificateFingerprintStore pins;
  late ThrowingCredentialStore credentials;
  late RenewalTestSigner signer;
  late DateTime now;
  late Map<String, Object?> metadata;
  String? worker;
  var revision = 0;
  late List<int> successorDer;
  late List<String> paths;
  late List<RenewalPeer> peers;
  late Map<String, VerifiedCertificateRenewal> serverGrants;
  late Map<String, Map<String, dynamic>> receipts;
  late Map<String, Object?> originalData;
  late String initialStamp;
  bool lostClaim = false, lostConfirm = false;
  String? forcedRejection;
  int? forcedStatus;
  void Function(Map<String, dynamic>)? corrupt;
  Future<void> Function(String)? afterResponse;
  Future<void> Function()? beforeConnect;

  Future<Map<String, Object?>> nonTrustData() async => {
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
    ])
      table: await db.connection.query(table),
    'credential': await credentials.read(),
  };
  Future<List<Row>> rows() =>
      db.connection.query(certificateRenewalTable, orderBy: 'sequence');
  Future<void> preserved() async {
    expect(await nonTrustData(), originalData);
    expect(
      jsonEncode(await db.connection.query(InitialCertificateTrust.table)),
      initialStamp,
    );
  }

  Future<VerifiedCertificateRenewal> grant() async {
    final context = await trust.renewalContext();
    final issued = now.millisecondsSinceEpoch ~/ 1000;
    final qr = await signer.signed(
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
          successorDer,
        )).toLowerCase(),
        'to_generation': context.generation + 1,
        'iat': issued,
        'exp': issued + 300,
      },
    );
    final verified = await trust.reviewRenewalQr(qr);
    serverGrants[verified.grantId] = verified;
    return verified;
  }

  Map<String, dynamic> rejection(String code) => {
    'ok': false,
    'request_id': 'synthetic-error',
    'error_code': code,
    'message': 'Synthetic rejection',
    'retryable': false,
    'details': [],
  };
  Future<SyncBatchReply> respond(Uri uri, String body) async {
    paths.add(uri.path);
    final request = jsonDecode(body) as Map<String, dynamic>;
    final saved = (await rows()).last;
    Map<String, dynamic> response;
    int status;
    if (uri.path.endsWith('/claim')) {
      expect(request.keys.toList(), [
        'api_version',
        'protocol',
        'protocol_version',
        'grant_id',
        'grant_digest',
      ]);
      expect(saved['state'], 'claim_pending');
      final g = serverGrants[request['grant_id']]!;
      expect(request['grant_digest'], g.grantDigest);
      if (forcedStatus != null || forcedRejection != null) {
        status = forcedStatus ?? 409;
        response = rejection(forcedRejection ?? 'service_unavailable');
      } else if (!receipts.containsKey(g.grantId) &&
          now.millisecondsSinceEpoch ~/ 1000 >= g.expiresAt) {
        status = 409;
        response = rejection('renewal_grant_expired');
      } else {
        status = receipts.containsKey(g.grantId) ? 200 : 201;
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
        response = {
          'ok': true,
          'request_id': 'synthetic-claim',
          'receipt': {...receipt},
        };
      }
    } else {
      expect(uri.path, '/api/v1/certificate-renewals/confirm');
      expect(request.keys.toList(), [
        'api_version',
        'protocol',
        'protocol_version',
        'receipt_id',
        'grant_id',
        'grant_digest',
        'dashboard_id',
        'project_id',
        'device_id',
        'worker_id',
        'api_base_url',
        'certificate_sha256',
        'generation',
      ]);
      expect(saved['state'], 'confirmation_pending');
      final receipt = receipts[request['grant_id']]!;
      for (final key in [
        'receipt_id',
        'grant_id',
        'grant_digest',
        'dashboard_id',
        'project_id',
        'device_id',
        'worker_id',
        'api_base_url',
      ]) {
        expect(request[key], receipt[key]);
      }
      expect(request['certificate_sha256'], receipt['to_certificate_sha256']);
      expect(request['generation'], receipt['to_generation']);
      status = forcedStatus ?? 200;
      response = status == 200
          ? {
              'ok': true,
              'request_id': 'synthetic-confirm',
              'receipt_id': receipt['receipt_id'],
              'grant_digest': receipt['grant_digest'],
              'device_id': receipt['device_id'],
              'certificate_sha256': receipt['to_certificate_sha256'],
              'generation': receipt['to_generation'],
              'state': 'confirmed',
            }
          : rejection('service_unavailable');
    }
    expect(request['api_version'], 1);
    expect(request['protocol'], 'ansvk-outreach-sync');
    expect(request['protocol_version'], 1);
    corrupt?.call(response);
    await afterResponse?.call(uri.path);
    if ((uri.path.endsWith('/claim') && lostClaim) ||
        (uri.path.endsWith('/confirm') && lostConfirm)) {
      throw const SocketException('Synthetic lost reply');
    }
    return SyncBatchReply(status, response);
  }

  void makeTrust() {
    trust = InitialCertificateTrust(
      repository: repo,
      legacyPins: pins,
      credentials: credentials,
      clock: () => now,
      connector: (uri) async {
        await beforeConnect?.call();
        final peer = RenewalPeer([...successorDer], respond);
        peers.add(peer);
        return peer;
      },
    );
    service = CertificateRenewalService(trust: trust);
  }

  setUp(() async {
    sqfliteFfiInit();
    metadata = installPeerCertificateMock();
    signer = await RenewalTestSigner.create();
    now = renewalTime;
    dir = await Directory.systemTemp.createTemp('outreach-renewal-state-');
    final folder = dir.path;
    databasePath = '$folder/phone.db';
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: databasePath,
    );
    repo = OutreachRepository(
      db,
      currentWorkerId: () => worker,
      sessionRevision: () => revision,
    );
    worker = await repo.createWorkerProfile('synthetic-worker');
    revision = 0;
    final hotspot = await repo.createHotspot(name: 'preserved-hotspot');
    await repo.createEncounter({
      'hotspot_id': hotspot,
      'client_code': 'synthetic-client',
      'dist_3cc': 5,
      'hiv': 'Non reactive',
    });
    pins = CertificateFingerprintStore();
    await pins.write(await PeerCertificateVerifier.sha256Hex([1, 2, 3]));
    credentials = ThrowingCredentialStore();
    await credentials.write('synthetic-credential');
    final id = await repo.appIdentity();
    await repo.saveDashboardPairing(
      'https://192.168.1.50:3443/api/v1',
      '123456',
    );
    await repo.applyDashboardPairing(
      PairingSuccess(
        requestId: 'synthetic',
        dashboardId: renewalPayload['dashboard_id'],
        dashboardName: 'Office',
        deviceId: id['device_id'] as String,
        workerId: worker!,
        deviceCredential: 'synthetic-credential',
        pairedAt: DateTime.utc(2026),
        serverTime: DateTime.utc(2026),
      ),
    );
    await seedConfirmedTrust(repo, pins, credentials);
    final proof =
        jsonDecode(
              (await db.connection.query(
                    InitialCertificateTrust.table,
                  )).single['bootstrap_json']
                  as String,
            )
            as Map<String, dynamic>;
    proof['renewal_authority'] = signer.authority;
    await db.connection.update(InitialCertificateTrust.table, {
      'bootstrap_json': jsonEncode(proof),
    });
    successorDer = [4, 5, 6];
    paths = [];
    peers = [];
    serverGrants = {};
    receipts = {};
    lostClaim = false;
    lostConfirm = false;
    forcedRejection = null;
    forcedStatus = null;
    corrupt = null;
    afterResponse = null;
    beforeConnect = null;
    makeTrust();
    originalData = await nonTrustData();
    initialStamp = jsonEncode(
      await db.connection.query(InitialCertificateTrust.table),
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
    clearPeerCertificateMock();
  });

  test(
    'version 8 upgrade preserves pairing, proof and pending records',
    () async {
      await db.connection.execute('DROP TABLE certificate_renewals');
      await db.connection.setVersion(8);
      await db.close();
      db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      repo = OutreachRepository(
        db,
        currentWorkerId: () => worker,
        sessionRevision: () => revision,
      );
      makeTrust();
      expect(await db.connection.getVersion(), 9);
      expect(await rows(), isEmpty);
      expect((await trust.renewalContext()).generation, 1);
      expect(paths, isEmpty);
      await preserved();
    },
  );
  test('intent storage failure prevents TLS and can be retried', () async {
    final g = await grant();
    await db.connection.execute('''CREATE TRIGGER synthetic_insert_failure
      BEFORE INSERT ON certificate_renewals
      BEGIN SELECT RAISE(ABORT, 'Synthetic failure'); END''');
    await expectLater(service.accept(g), throwsA(anything));
    expect(await rows(), isEmpty);
    expect(peers, isEmpty);
    expect(paths, isEmpty);
    await preserved();
    await db.connection.execute('DROP TRIGGER synthetic_insert_failure');
    expect(await service.accept(g), CertificateRenewalOutcome.confirmed);
    await preserved();
  });
  test('stale reviewed session cannot save an intent or open TLS', () async {
    final g = await grant();
    revision++;
    await expectLater(
      service.accept(g),
      throwsA(isA<CertificateRenewalQrException>()),
    );
    expect(await rows(), isEmpty);
    expect(paths, isEmpty);
    expect(peers, isEmpty);
    await preserved();
  });
  test(
    'durable intent, exact receipt, atomic pin and confirmation preserve all records',
    () async {
      final g = await grant();
      expect(await service.accept(g), CertificateRenewalOutcome.confirmed);
      expect(paths, [
        '/api/v1/certificate-renewals/claim',
        '/api/v1/certificate-renewals/confirm',
      ]);
      expect((await rows()).single['state'], 'confirmed');
      expect((await trust.renewalContext()).generation, 2);
      expect(await trust.confirmedPin(), g.toCertificateSha256.toUpperCase());
      expect(peers.every((p) => p.closed), true);
      await trust.ensure();
      expect(paths, hasLength(2)); // Never bootstrap again or use the old pin.
      expect(
        await service.resume(),
        CertificateRenewalOutcome.noPendingRenewal,
      );
      await preserved();
    },
  );
  test(
    'lost claim reply survives process-style reopen and expiry; identical receipt recovered',
    () async {
      final g = await grant();
      lostClaim = true;
      await expectLater(service.accept(g), throwsA(isA<SocketException>()));
      expect((await rows()).single['state'], 'claim_pending');
      await expectLater(trust.confirmedPin(), throwsStateError);
      final receipt = {...receipts[g.grantId]!};
      await db.close();
      db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      repo = OutreachRepository(
        db,
        currentWorkerId: () => worker,
        sessionRevision: () => revision,
      );
      now = now.add(const Duration(minutes: 10));
      lostClaim = false;
      makeTrust();
      expect(await service.resume(), CertificateRenewalOutcome.confirmed);
      expect(
        jsonDecode((await rows()).single['receipt_json'] as String),
        receipt,
      );
      expect(paths.where((p) => p.endsWith('/claim')), hasLength(2));
      await preserved();
    },
  );
  test(
    'newly scanned expired QR cannot use saved-grant retry exception',
    () async {
      final g = await grant();
      now = now.add(const Duration(minutes: 5));
      await expectLater(
        trust.reviewRenewalQr(
          CertificateRenewalQrVerifier.prefix + g.compactJws,
        ),
        throwsA(isA<CertificateRenewalQrException>()),
      );
      await expectLater(
        service.accept(g),
        throwsA(isA<CertificateRenewalQrException>()),
      );
      expect(await rows(), isEmpty);
      expect(paths, isEmpty);
      await preserved();
    },
  );
  test(
    'lost confirmation commits new pin but blocks Sync until exact retry',
    () async {
      final g = await grant();
      lostConfirm = true;
      await expectLater(service.accept(g), throwsA(isA<SocketException>()));
      expect((await rows()).single['state'], 'confirmation_pending');
      expect(
        (await trust.renewalContext()).certificateSha256,
        g.toCertificateSha256,
      );
      await expectLater(trust.confirmedPin(), throwsStateError);
      await db.close();
      db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      repo = OutreachRepository(
        db,
        currentWorkerId: () => worker,
        sessionRevision: () => revision,
      );
      makeTrust();
      now = now.add(const Duration(minutes: 10));
      lostConfirm = false;
      expect(await service.resume(), CertificateRenewalOutcome.confirmed);
      expect(paths.where((p) => p.endsWith('/claim')), hasLength(1));
      expect(paths.where((p) => p.endsWith('/confirm')), hasLength(2));
      await preserved();
    },
  );
  test(
    'confirmed-from fresh grant can reconcile lost older confirmation without deleting proof',
    () async {
      final first = await grant();
      lostConfirm = true;
      await expectLater(service.accept(first), throwsA(isA<SocketException>()));
      final oldReceipt = (await rows()).single['receipt_json'];
      successorDer = [7, 8, 9];
      lostConfirm = false;
      final next = await grant();
      expect(await service.accept(next), CertificateRenewalOutcome.confirmed);
      final history = await rows();
      expect(history[0]['state'], 'confirmed_by_successor');
      expect(history[0]['receipt_json'], oldReceipt);
      expect(history[0]['confirmation_json'], null);
      expect(history[0]['confirmed_by_grant_id'], next.grantId);
      expect(history[1]['state'], 'confirmed');
      expect((await trust.renewalContext()).generation, 3);
      await preserved();
    },
  );
  test(
    'next uncertain claim retains older confirmation proof until new receipt',
    () async {
      lostConfirm = true;
      await expectLater(
        service.accept(await grant()),
        throwsA(isA<SocketException>()),
      );
      final oldReceipt = (await rows()).single['receipt_json'];
      successorDer = [7, 8, 9];
      lostConfirm = false;
      lostClaim = true;
      await expectLater(
        service.accept(await grant()),
        throwsA(isA<SocketException>()),
      );
      final history = await rows();
      expect(history[0]['state'], 'confirmation_pending');
      expect(history[0]['receipt_json'], oldReceipt);
      expect(history[1]['state'], 'claim_pending');
      await expectLater(trust.confirmedPin(), throwsStateError);
      lostClaim = false;
      expect(await service.resume(), CertificateRenewalOutcome.confirmed);
      await preserved();
    },
  );
  test(
    'next receipt transaction failure also retains older pending proof',
    () async {
      lostConfirm = true;
      await expectLater(
        service.accept(await grant()),
        throwsA(isA<SocketException>()),
      );
      final old = (await rows()).single;
      successorDer = [7, 8, 9];
      lostConfirm = false;
      await db.connection.execute('''CREATE TRIGGER synthetic_successor_failure
      BEFORE UPDATE ON certificate_renewals WHEN NEW.state = 'confirmation_pending'
      BEGIN SELECT RAISE(ABORT, 'Synthetic failure'); END''');
      await expectLater(service.accept(await grant()), throwsA(anything));
      final history = await rows();
      expect(history.first, old);
      expect(history.last['state'], 'claim_pending');
      expect((await trust.renewalContext()).generation, 2);
      await preserved();
      await db.connection.execute('DROP TRIGGER synthetic_successor_failure');
      expect(await service.resume(), CertificateRenewalOutcome.confirmed);
      await preserved();
    },
  );
  test(
    'lost initial confirmation can be reconciled by matching next receipt',
    () async {
      await db.connection.update(InitialCertificateTrust.table, {
        'state': 'confirmation_pending',
      });
      initialStamp = jsonEncode(
        await db.connection.query(InitialCertificateTrust.table),
      );
      expect(
        await service.accept(await grant()),
        CertificateRenewalOutcome.confirmed,
      );
      expect(
        (await db.connection.query(
          InitialCertificateTrust.table,
        )).single['state'],
        'confirmation_pending',
      );
      expect(
        await trust.confirmedPin(),
        await PeerCertificateVerifier.sha256Hex(successorDer),
      );
      await preserved();
    },
  );
  for (final rejectionCode in [
    'renewal_grant_expired',
    'renewal_grant_cancelled',
  ]) {
    test(
      'authenticated unused $rejectionCode is terminal without changing pin',
      () async {
        forcedRejection = rejectionCode;
        expect(
          await service.accept(await grant()),
          CertificateRenewalOutcome.rejected,
        );
        expect((await rows()).single['state'], 'rejected');
        expect((await rows()).single['rejection_code'], rejectionCode);
        expect(
          await trust.confirmedPin(),
          await PeerCertificateVerifier.sha256Hex([1, 2, 3]),
        );
        await preserved();
      },
    );
  }
  test(
    'expiry after intent but before server claim requires authenticated rejection',
    () async {
      final g = await grant();
      beforeConnect = () async {
        now = now.add(const Duration(minutes: 6));
      };
      expect(await service.accept(g), CertificateRenewalOutcome.rejected);
      expect(receipts, isEmpty);
      await preserved();
    },
  );
  for (final status in [400, 401, 403, 408, 429, 500, 503]) {
    test(
      'HTTP $status preserves uncertain claim and pending records',
      () async {
        forcedStatus = status;
        await expectLater(
          service.accept(await grant()),
          throwsA(isA<CertificateRenewalQrException>()),
        );
        expect((await rows()).single['state'], 'claim_pending');
        await preserved();
      },
    );
  }
  for (final failure in ['pin', 'expired', 'future', 'san']) {
    test('wrong successor $failure sends no HTTP secrets', () async {
      final g = await grant();
      if (failure == 'pin') successorDer = [9];
      if (failure == 'expired') {
        metadata['notAfter'] = now.millisecondsSinceEpoch;
      }
      if (failure == 'future') {
        metadata['notBefore'] = now
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch;
      }
      if (failure == 'san') metadata['ipSans'] = ['192.168.1.51'];
      await expectLater(service.accept(g), throwsA(isA<SyncRequestFailure>()));
      expect(paths, isEmpty);
      expect((await rows()).single['state'], 'claim_pending');
      expect(peers.single.closed, true);
      await preserved();
    });
  }
  for (final field in [
    'receipt_id',
    'grant_id',
    'grant_digest',
    'device_id',
    'worker_id',
    'dashboard_id',
    'project_id',
    'api_base_url',
    'from_certificate_sha256',
    'from_generation',
    'to_certificate_sha256',
    'to_generation',
    'claimed_at',
    'extra',
  ]) {
    test('invalid claim receipt $field cannot change trust', () async {
      corrupt = (reply) {
        final receipt = reply['receipt'] as Map<String, dynamic>;
        receipt[field] = field.contains('generation') || field == 'claimed_at'
            ? 999999999999
            : 'wrong';
      };
      await expectLater(
        service.accept(await grant()),
        throwsA(isA<CertificateRenewalQrException>()),
      );
      expect((await rows()).single['state'], 'claim_pending');
      expect((await trust.renewalContext()).generation, 1);
      await preserved();
    });
  }
  for (final field in [
    'receipt_id',
    'grant_digest',
    'device_id',
    'certificate_sha256',
    'generation',
    'state',
    'extra',
  ]) {
    test(
      'invalid confirmation $field keeps committed new pin pending',
      () async {
        corrupt = (reply) {
          if (!reply.containsKey('receipt')) {
            reply[field] = field == 'generation' ? 2.0 : 'wrong';
          }
        };
        final g = await grant();
        await expectLater(
          service.accept(g),
          throwsA(isA<CertificateRenewalQrException>()),
        );
        expect((await rows()).single['state'], 'confirmation_pending');
        expect(
          (await trust.renewalContext()).certificateSha256,
          g.toCertificateSha256,
        );
        await expectLater(trust.confirmedPin(), throwsStateError);
        await preserved();
      },
    );
  }
  test('malformed terminal rejection never clears uncertain claim', () async {
    forcedRejection = 'renewal_grant_expired';
    corrupt = (reply) {
      reply['retryable'] = true;
    };
    await expectLater(
      service.accept(await grant()),
      throwsA(isA<CertificateRenewalQrException>()),
    );
    expect((await rows()).single['state'], 'claim_pending');
    await preserved();
  });
  for (final path in ['/claim', '/confirm']) {
    test('lock/session epoch during $path prevents late commit', () async {
      afterResponse = (p) async {
        if (p.endsWith(path)) revision += 2;
      };
      await expectLater(
        service.accept(await grant()),
        throwsA(isA<CertificateRenewalQrException>()),
      );
      expect(
        (await rows()).single['state'],
        path == '/claim' ? 'claim_pending' : 'confirmation_pending',
      );
      await preserved();
    });
    test('Stop during $path preserves proof', () async {
      final control = SyncRunControl();
      afterResponse = (p) async {
        if (p.endsWith(path)) control.stop();
      };
      await expectLater(
        service.accept(await grant(), control: control),
        throwsA(isA<SyncStopped>()),
      );
      expect(
        (await rows()).single['state'],
        path == '/claim' ? 'claim_pending' : 'confirmation_pending',
      );
      await preserved();
    });
  }
  test(
    'Stop during TLS setup sends nothing and retains durable intent',
    () async {
      final control = SyncRunControl();
      beforeConnect = () async {
        control.stop();
      };
      await expectLater(
        service.accept(await grant(), control: control),
        throwsA(isA<SyncStopped>()),
      );
      expect(paths, isEmpty);
      expect((await rows()).single['state'], 'claim_pending');
      await preserved();
    },
  );
  for (final state in ['confirmation_pending', 'confirmed']) {
    test('SQLite failure before $state rolls back and can resume', () async {
      await db.connection.execute('''CREATE TRIGGER synthetic_write_failure
        BEFORE UPDATE ON certificate_renewals WHEN NEW.state = '$state'
        BEGIN SELECT RAISE(ABORT, 'Synthetic failure'); END''');
      await expectLater(service.accept(await grant()), throwsA(anything));
      expect(
        (await rows()).single['state'],
        state == 'confirmation_pending'
            ? 'claim_pending'
            : 'confirmation_pending',
      );
      await db.connection.execute('DROP TRIGGER synthetic_write_failure');
      expect(await service.resume(), CertificateRenewalOutcome.confirmed);
      await preserved();
    });
  }
  test(
    'credential read failure pauses retry without resetting secure storage',
    () async {
      lostClaim = true;
      await expectLater(
        service.accept(await grant()),
        throwsA(isA<SocketException>()),
      );
      credentials.fail = true;
      await expectLater(service.resume(), throwsStateError);
      credentials.fail = false;
      expect((await rows()).single['state'], 'claim_pending');
      expect(paths, hasLength(1));
      await preserved();
    },
  );
  test('changed credential blocks retry before network', () async {
    lostClaim = true;
    await expectLater(
      service.accept(await grant()),
      throwsA(isA<SocketException>()),
    );
    await credentials.write('replacement');
    await expectLater(service.resume(), throwsStateError);
    expect(paths, hasLength(1));
    expect((await rows()).single['state'], 'claim_pending');
    await credentials.write('synthetic-credential');
    await preserved();
  });
  for (final session in ['locked', 'different-worker']) {
    test('$session cannot resume saved renewal or send a credential', () async {
      lostClaim = true;
      await expectLater(
        service.accept(await grant()),
        throwsA(isA<SocketException>()),
      );
      final savedWorker = worker;
      worker = session == 'locked' ? null : const Uuid().v4();
      await expectLater(service.resume(), throwsStateError);
      expect(paths, hasLength(1));
      expect((await rows()).single['state'], 'claim_pending');
      worker = savedWorker;
      await preserved();
    });
  }
  test(
    'expired saved authority blocks recovery without clearing proof',
    () async {
      lostClaim = true;
      await expectLater(
        service.accept(await grant()),
        throwsA(isA<SocketException>()),
      );
      final expiry = signer.authority['expires_at'] as int;
      now = DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true);
      await expectLater(service.resume(), throwsFormatException);
      expect(paths, hasLength(1));
      expect((await rows()).single['state'], 'claim_pending');
      await preserved();
    },
  );
  test(
    'pending transition blocks ordinary Sync before status, batches or cleanup',
    () async {
      lostConfirm = true;
      await expectLater(
        service.accept(await grant()),
        throwsA(isA<SocketException>()),
      );
      final beforePaths = [...paths];
      final result = await ConfiguredManualSync(
        repository: repo,
        fingerprintStore: pins,
        credentialStore: credentials,
        builder: SyncBatchBuilder(appVersion: 'test', clock: () => now),
        connector: trust.connector,
      ).run();
      expect(result.outcome, ManualSyncOutcome.stopped);
      expect(paths, beforePaths);
      await preserved();
    },
  );
  test(
    'gate rejects a concurrent lifecycle operation while renewal drains',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      afterResponse = (_) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final g = await grant();
      final running = service.accept(g);
      await entered.future;
      await expectLater(service.resume(), throwsStateError);
      await expectLater(LifecycleGate.run(() async => 1), throwsStateError);
      release.complete();
      expect(await running, CertificateRenewalOutcome.confirmed);
      await preserved();
    },
  );
  test('history proof cannot be changed or deleted', () async {
    await service.accept(await grant());
    await expectLater(
      db.connection.update(certificateRenewalTable, {'compact_jws': 'changed'}),
      throwsA(anything),
    );
    await expectLater(
      db.connection.update(certificateRenewalTable, {'receipt_json': '{}'}),
      throwsA(anything),
    );
    await expectLater(
      db.connection.delete(certificateRenewalTable),
      throwsA(anything),
    );
    expect((await rows()).single['state'], 'confirmed');
    await preserved();
  });
  test(
    'missing authority or uncommitted bootstrap cannot authorize transition',
    () async {
      await db.connection.update(InitialCertificateTrust.table, {
        'state': 'bootstrap_pending',
        'bootstrap_json': null,
      });
      await expectLater(
        service.resume(),
        throwsA(isA<CertificateRenewalQrException>()),
      );
      expect(await rows(), isEmpty);
      expect(paths, isEmpty);
    },
  );
}
