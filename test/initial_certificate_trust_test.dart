import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/certificate_fingerprint_store.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/initial_certificate_trust.dart';
import 'package:ansvk_outreach/sync/certificate_renewal_qr.dart';
import 'package:ansvk_outreach/sync/lifecycle_gate.dart';
import 'package:ansvk_outreach/sync/manual_sync_runner.dart';
import 'package:ansvk_outreach/sync/pairing_response.dart';
import 'package:ansvk_outreach/sync/peer_certificate_verifier.dart';
import 'package:ansvk_outreach/sync/secure_sync_transport.dart';
import 'package:ansvk_outreach/sync/configured_manual_sync.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:ansvk_outreach/sync/trust_json.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'peer_certificate_test_support.dart';
import 'initial_trust_test_support.dart';

class TrustConnection implements SyncHttpsConnection {
  TrustConnection(this.respond, {this.der = const [1, 2, 3]});
  final Future<SyncBatchReply> Function(Uri, String?) respond;
  final List<int> der;
  bool closed = false;
  @override
  List<int> get certificateDer => der;
  @override
  Future<SyncBatchReply> request(
    Uri uri,
    String method,
    String credential,
    String? body,
  ) => respond(uri, body);
  @override
  void close() {
    closed = true;
  }
}

void main() {
  late AppDatabase db;
  late Directory directory;
  late OutreachRepository repo;
  late CertificateFingerprintStore pins;
  late DeviceCredentialStore credentials;
  late InitialCertificateTrust trust;
  String? worker;
  var revision = 0;
  late List<String> actions;
  bool loseBootstrap = false, loseConfirm = false, wrongCertificate = false;
  void Function(Map<String, dynamic>)? corrupt;
  Future<void> Function()? duringResponse;
  late List<TrustConnection> peers;
  setUp(() async {
    installPeerCertificateMock();
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('ansvk_initial_trust_');
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/trust.db',
    );
    repo = OutreachRepository(
      db,
      currentWorkerId: () => worker,
      sessionRevision: () => revision,
    );
    worker = await repo.createWorkerProfile('synthetic');
    revision = 0;
    await repo.createHotspot(name: 'kept');
    pins = CertificateFingerprintStore();
    await pins.write(await PeerCertificateVerifier.sha256Hex([1, 2, 3]));
    credentials = DeviceCredentialStore.memory();
    await credentials.write('synthetic-credential');
    final identity = await repo.appIdentity();
    await repo.saveDashboardPairing('https://127.0.0.1:3443/api/v1', '123456');
    await repo.applyDashboardPairing(
      PairingSuccess(
        requestId: 'test',
        dashboardId: 'dashboard',
        dashboardName: 'Office',
        deviceId: identity['device_id'] as String,
        workerId: worker!,
        deviceCredential: 'synthetic-credential',
        pairedAt: DateTime.utc(2026),
        serverTime: DateTime.utc(2026),
      ),
    );
    actions = [];
    peers = [];
    loseBootstrap = false;
    loseConfirm = false;
    wrongCertificate = false;
    corrupt = null;
    duringResponse = null;
    trust = InitialCertificateTrust(
      repository: repo,
      legacyPins: pins,
      credentials: credentials,
      clock: () => DateTime.utc(2026, 9, 29),
      connector: (_) async {
        final peer = TrustConnection((uri, body) async {
          expect(uri.path, '/api/v1/certificate-trust');
          final request = jsonDecode(body!) as Map<String, dynamic>;
          actions.add(request['action']);
          final response = trustResponse(request);
          corrupt?.call(response);
          await duringResponse?.call();
          if ((request['action'] == 'bootstrap' && loseBootstrap) ||
              (request['action'] == 'confirm_bootstrap' && loseConfirm)) {
            throw StateError('Lost reply');
          }
          return SyncBatchReply(200, response);
        }, der: wrongCertificate ? [4] : [1, 2, 3]);
        peers.add(peer);
        return peer;
      },
    );
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
    clearPeerCertificateMock();
  });
  Future<String> state() async =>
      (await db.connection.query('initial_certificate_trust')).single['state']
          as String;
  test(
    'renewal context is read-only and uses the committed authority',
    () async {
      await trust.ensure();
      final stamp = await trust.recordStamp();
      final identity = await repo.appIdentity(),
          pending = await repo.pendingOperations();
      final context = await trust.renewalContext();
      expect(context.deviceId, identity['device_id']);
      expect(context.workerId, worker);
      expect(context.generation, 1);
      expect(
        context.certificateSha256,
        (await PeerCertificateVerifier.sha256Hex([1, 2, 3])).toLowerCase(),
      );
      expect(context.authorityJson, contains('"crv":"Ed25519"'));
      expect(await trust.recordStamp(), stamp);
      expect(await repo.appIdentity(), identity);
      expect(await repo.pendingOperations(), pending);
      expect(await credentials.read(), 'synthetic-credential');
      expect(actions, ['bootstrap', 'confirm_bootstrap']);
      final oldBinding = context.binding;
      revision++;
      expect((await trust.renewalContext()).binding, isNot(oldBinding));
    },
  );
  test(
    'committed proof survives a lost initial confirmation for renewal review',
    () async {
      loseConfirm = true;
      await expectLater(trust.ensure(), throwsStateError);
      final stamp = await trust.recordStamp();
      final context = await trust.renewalContext();
      expect(context.generation, 1);
      expect(await state(), 'confirmation_pending');
      expect(await trust.recordStamp(), stamp);
      expect(actions, ['bootstrap', 'confirm_bootstrap']);
    },
  );
  test(
    'uncommitted trust and locked session cannot supply renewal authority',
    () async {
      await expectLater(
        trust.renewalContext(),
        throwsA(isA<CertificateRenewalQrException>()),
      );
      loseBootstrap = true;
      await expectLater(trust.ensure(), throwsStateError);
      await expectLater(
        trust.renewalContext(),
        throwsA(isA<CertificateRenewalQrException>()),
      );
      loseBootstrap = false;
      await trust.ensure();
      worker = null;
      revision++;
      await expectLater(trust.renewalContext(), throwsStateError);
      expect(await state(), 'confirmed');
    },
  );
  test('corrupted authority is not supplied from legacy fallback', () async {
    await trust.ensure();
    final rows = await db.connection.query('initial_certificate_trust');
    final proof =
        jsonDecode(rows.single['bootstrap_json'] as String)
            as Map<String, dynamic>;
    proof['renewal_authority']['expires_at'] = 1788220801;
    await db.connection.update('initial_certificate_trust', {
      'bootstrap_json': jsonEncode(proof),
    });
    await pins.write('0' * 64);
    await expectLater(trust.renewalContext(), throwsFormatException);
    expect(await state(), 'confirmed');
    expect(actions, ['bootstrap', 'confirm_bootstrap']);
  });
  test(
    'restart resumes durable confirmation without fetching another authority',
    () async {
      loseConfirm = true;
      await expectLater(trust.ensure(), throwsStateError);
      final connector = trust.connector;
      await db.close();
      db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/trust.db',
      );
      repo = OutreachRepository(
        db,
        currentWorkerId: () => worker,
        sessionRevision: () => revision,
      );
      trust = InitialCertificateTrust(
        repository: repo,
        legacyPins: pins,
        credentials: credentials,
        clock: () => DateTime.utc(2026, 9, 29),
        connector: connector,
      );
      loseConfirm = false;
      await trust.ensure();
      expect(actions, ['bootstrap', 'confirm_bootstrap', 'confirm_bootstrap']);
      expect(await state(), 'confirmed');
    },
  );
  test(
    'version7 to current migration preserves identity and pending records',
    () async {
      final identity = await repo.appIdentity(),
          pending = await repo.pendingOperations();
      await db.connection.execute('DROP TABLE initial_certificate_trust');
      await db.connection.execute('DROP TABLE certificate_renewals');
      await db.connection.setVersion(7);
      await db.close();
      db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/trust.db',
      );
      repo = OutreachRepository(
        db,
        currentWorkerId: () => worker,
        sessionRevision: () => revision,
      );
      expect(await db.connection.getVersion(), AppDatabase.schemaVersion);
      expect(await db.connection.query('initial_certificate_trust'), isEmpty);
      expect(await repo.appIdentity(), identity);
      expect(await repo.pendingOperations(), pending);
    },
  );
  test(
    'authenticated bootstrap and exact confirm preserve all nontrust data',
    () async {
      final identity = await repo.appIdentity(),
          pending = await repo.pendingOperations();
      await trust.ensure();
      expect(actions, ['bootstrap', 'confirm_bootstrap']);
      expect(await state(), 'confirmed');
      expect(
        await trust.confirmedPin(),
        await PeerCertificateVerifier.sha256Hex([1, 2, 3]),
      );
      expect(await pins.read(), null);
      expect(await credentials.read(), 'synthetic-credential');
      expect(await repo.appIdentity(), identity);
      expect(await repo.pendingOperations(), pending);
      final saved = jsonEncode(
        await db.connection.query('initial_certificate_trust'),
      );
      expect(saved, isNot(contains('synthetic-credential')));
      expect((await repo.syncStatus())['retention_cleanup_at'], null);
      expect(peers.every((p) => p.closed), true);
      await trust.ensure();
      expect(actions, hasLength(2));
    },
  );
  test(
    'lost bootstrap reply resumes durable snapshot, not mutated legacy pin',
    () async {
      loseBootstrap = true;
      await expectLater(trust.ensure(), throwsStateError);
      expect(await state(), 'bootstrap_pending');
      await pins.write('0' * 64);
      loseBootstrap = false;
      await trust.ensure();
      expect(actions, ['bootstrap', 'bootstrap', 'confirm_bootstrap']);
      expect(await state(), 'confirmed');
    },
  );
  test(
    'lost confirmation resumes proof without bootstrap or legacy fallback',
    () async {
      loseConfirm = true;
      await expectLater(trust.ensure(), throwsStateError);
      expect(await state(), 'confirmation_pending');
      expect(await pins.read(), null);
      await expectLater(trust.confirmedPin(), throwsStateError);
      await pins.write('0' * 64);
      loseConfirm = false;
      await trust.ensure();
      expect(actions, ['bootstrap', 'confirm_bootstrap', 'confirm_bootstrap']);
      expect(
        await trust.confirmedPin(),
        await PeerCertificateVerifier.sha256Hex([1, 2, 3]),
      );
    },
  );
  for (final failure in [
    'identity',
    'pin',
    'key',
    'unknown',
    'authority-expiry',
    'confirmation',
  ]) {
    test(
      'reject $failure without inventing confirmation or acknowledgements',
      () async {
        corrupt = (r) {
          if (r['action'] == 'bootstrap') {
            switch (failure) {
              case 'identity':
                r['device_id'] = 'other';
              case 'pin':
                r['certificate_sha256'] = '0' * 64;
              case 'key':
                r['renewal_authority']['public_jwk']['kid'] = '0' * 64;
              case 'unknown':
                r['extra'] = 1;
              case 'authority-expiry':
                r['renewal_authority']['expires_at'] = 1788220801;
            }
          } else if (failure == 'confirmation') {
            r['generation'] = 2;
          }
        };
        await expectLater(trust.ensure(), throwsFormatException);
        expect(
          await state(),
          failure == 'confirmation'
              ? 'confirmation_pending'
              : 'bootstrap_pending',
        );
        expect(await repo.pendingOperations(), hasLength(2));
        expect(await credentials.read(), 'synthetic-credential');
      },
    );
  }
  test('same worker lock/unlock epoch invalidates late response', () async {
    duringResponse = () async {
      revision += 2;
    };
    await expectLater(trust.ensure(), throwsStateError);
    expect(await state(), 'bootstrap_pending');
  });
  test('credential/config mutation prevents a stale save', () async {
    duringResponse = () async {
      await credentials.write('replacement-credential');
    };
    await expectLater(trust.ensure(), throwsStateError);
    expect(await state(), 'bootstrap_pending');
  });
  test('wrong live certificate sends zero HTTP and preserves outbox', () async {
    wrongCertificate = true;
    await expectLater(trust.ensure(), throwsA(anything));
    expect(actions, isEmpty);
    expect(await repo.pendingOperations(), hasLength(2));
    expect(peers.single.closed, true);
  });
  test(
    'missing legacy pin or corrupt committed state never bootstraps by fallback',
    () async {
      await pins.clear();
      await expectLater(trust.ensure(), throwsStateError);
      await pins.write(await PeerCertificateVerifier.sha256Hex([1, 2, 3]));
      await trust.ensure();
      await db.connection.update('initial_certificate_trust', {
        'bootstrap_json': '{}',
      });
      await pins.write(await PeerCertificateVerifier.sha256Hex([1, 2, 3]));
      await expectLater(trust.ensure(), throwsFormatException);
      expect(actions, hasLength(2));
    },
  );
  test(
    'failed initial setup stops ordinary sync before any status/upload/cleanup',
    () async {
      final service = ConfiguredManualSync(
        repository: repo,
        fingerprintStore: pins,
        credentialStore: credentials,
        builder: SyncBatchBuilder(appVersion: 'test', clock: DateTime.now),
        connector: (_) async => TrustConnection(
          (uri, body) async => SyncBatchReply(503, {'ok': false}),
        ),
      );
      expect((await service.run()).outcome, ManualSyncOutcome.stopped);
      expect(await repo.pendingOperations(), hasLength(2));
      expect((await repo.syncStatus())['retention_cleanup_at'], null);
    },
  );
  test(
    'gate rejects concurrent lifecycle operations while first request drains',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      duringResponse = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final first = trust.ensure();
      await entered.future;
      await expectLater(LifecycleGate.run(() async => 1), throwsStateError);
      release.complete();
      await first;
      expect(await state(), 'confirmed');
    },
  );
  test(
    'strict raw trust JSON rejects duplicates, exponent, fraction and oversized/deep bodies',
    () {
      expect(
        decodeTrustJson(
          '{"ok":true,"generation":1,"nested":{"kid":"x"}}',
        )['generation'],
        1,
      );
      for (final text in [
        '{"generation":1,"\\u0067eneration":2}',
        '{"generation":1e0}',
        '{"generation":1.0}',
        '{"generation":01}',
        '{"x":1,}',
        '{"x":"${'x' * 32769}"}',
      ]) {
        expect(() => decodeTrustJson(text), throwsFormatException);
      }
    },
  );
}
