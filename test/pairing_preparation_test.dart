import 'dart:convert';
import 'dart:io';

import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/dashboard_pairing_service.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/pairing_request_builder.dart';
import 'package:ansvk_outreach/sync/pairing_response.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('builds the accepted v1 pairing request shape', () async {
    final fixture = jsonDecode(
      await File(
        'docs/fixtures/outreach/v1/pairing-success.request.json',
      ).readAsString(),
    ) as Map<String, Object?>;
    final builder = PairingRequestBuilder(
      appVersion: fixture['app_version']! as String,
      clock: () => DateTime.parse(fixture['requested_at']! as String),
    );

    final request = builder.build(
      appIdentity: {
        'project_id': fixture['project_id'],
        'project_name': fixture['project_name'],
        'device_id': fixture['device_id'],
        'created_at': fixture['device_created_at'],
      },
      worker: {
        'worker_id': fixture['worker_id'],
        'username': fixture['username'],
      },
      pairingCode: ' ${fixture['pairing_code']} ',
    );

    expect(request, fixture);
  });

  test('rejects an invalid pairing code before a network request exists', () {
    final builder = PairingRequestBuilder(
      appVersion: '0.9.2+17',
      clock: () => DateTime.utc(2026, 9, 15, 8, 1),
    );

    expect(
      () => builder.build(
        appIdentity: const {
          'project_id': 'ansvk_outreach',
          'project_name': 'ANSVK Outreach',
          'device_id': 'device-1',
          'created_at': '2026-09-15T07:00:00Z',
        },
        worker: const {'worker_id': 'worker-1', 'username': 'worker'},
        pairingCode: '12345',
      ),
      throwsArgumentError,
    );
  });

  test('stores the future device credential separately from SQLite', () async {
    final store = DeviceCredentialStore();

    expect(await store.read(), isNull);
    await store.write(' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA ');
    expect(await store.read(), 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('rejects an empty device credential', () async {
    final store = DeviceCredentialStore();

    await expectLater(store.write('   '), throwsArgumentError);
  });

  test('parses the accepted v1 pairing success without applying it', () async {
    final fixture = jsonDecode(
      await File(
        'docs/fixtures/outreach/v1/pairing-success.response.json',
      ).readAsString(),
    ) as Map<String, Object?>;

    final result = PairingResponseResult.parse(
      fixture,
      expectedDeviceId: fixture['device_id']! as String,
      expectedWorkerId: fixture['worker_id']! as String,
    );

    expect(result, isA<PairingSuccess>());
    final success = result as PairingSuccess;
    expect(success.dashboardId, fixture['dashboard_id']);
    expect(success.dashboardName, fixture['dashboard_name']);
    expect(success.deviceCredential, fixture['device_credential']);
    expect(success.pairedAt, DateTime.parse(fixture['paired_at']! as String));
    expect(success.serverTime, DateTime.parse(fixture['server_time']! as String));
  });

  test('rejects a pairing success for another device before storing anything', () async {
    final fixture = jsonDecode(
      await File(
        'docs/fixtures/outreach/v1/pairing-success.response.json',
      ).readAsString(),
    ) as Map<String, Object?>;

    expect(
      () => PairingResponseResult.parse(
        fixture,
        expectedDeviceId: 'different-device',
        expectedWorkerId: fixture['worker_id']! as String,
      ),
      throwsFormatException,
    );
  });

  test('parses all accepted v1 pairing error cases', () async {
    final fixture = jsonDecode(
      await File(
        'docs/fixtures/outreach/v1/pairing-errors.json',
      ).readAsString(),
    ) as Map<String, Object?>;
    final cases = fixture['cases']! as List<Object?>;

    for (final item in cases) {
      final testCase = item! as Map<String, Object?>;
      final response = testCase['response']! as Map<String, Object?>;
      final result = PairingResponseResult.parse(
        response,
        expectedDeviceId: 'unused-for-errors',
        expectedWorkerId: 'unused-for-errors',
      );

      expect(result, isA<PairingFailure>(), reason: testCase['id'] as String);
      final failure = result as PairingFailure;
      expect(failure.errorCode, response['error_code']);
      expect(failure.message, response['message']);
      expect(failure.retryable, response['retryable']);
      expect(failure.workerMessage, isNotEmpty);
    }
  });
  group('dashboard pairing service', () {
    sqfliteFfiInit();
    late Directory directory;
    late AppDatabase database;
    late OutreachRepository repo;
    late DeviceCredentialStore credentialStore;
    late String workerId;
    String? session;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ansvk_pairing_test_');
      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/test.db',
      );
      session = null;
      repo = OutreachRepository(
        database,
        currentWorkerId: () => session,
        clock: () => DateTime.utc(2026, 9, 16, 12),
      );
      workerId = await repo.createWorkerProfile('worker1');
      session = workerId;
      credentialStore = DeviceCredentialStore();
      await credentialStore.clear();
      await repo.saveDashboardPairing(
        'https://192.168.1.50:3443/api/v1',
        '123456',
      );
    });

    tearDown(() async {
      await credentialStore.clear();
      await database.close();
      await directory.delete(recursive: true);
    });

    DashboardPairingService service(_FakePairingTransport transport) =>
        DashboardPairingService(
          repository: repo,
          credentialStore: credentialStore,
          requestBuilder: PairingRequestBuilder(
            appVersion: '0.9.4+19',
            clock: () => DateTime.utc(2026, 9, 16, 12, 1),
          ),
          transport: transport,
        );

    test('stores credential and paired state after a verified success', () async {
      final transport = _FakePairingTransport.success();
      final beforePending = await repo.pendingOperations();

      final result = await service(transport).pair(
        expectedCertificateFingerprint: List.filled(64, 'a').join(),
      );

      expect(result.status, DashboardPairingAttemptStatus.paired);
      expect(
        transport.uri.toString(),
        'https://192.168.1.50:3443/api/v1/pairing/requests',
      );
      expect(transport.expectedFingerprint, List.filled(64, 'A').join());
      expect(transport.request['pairing_code'], '123456');
      expect(transport.request['app_version'], '0.9.4+19');
      expect(await credentialStore.read(), transport.credential);
      final status = await repo.syncStatus();
      expect(status['dashboard_status'], 'Paired');
      expect(status['dashboard_id'], 'dashboard-1');
      expect(status['dashboard_name'], 'Synthetic Dashboard');
      expect(status['paired_at'], '2026-09-16T05:31:00.000Z');
      expect(status['pairing_code_saved'], 0);
      expect(status['pairing_prepared_at'], isNull);
      expect(await repo.pendingOperations(), hasLength(beforePending.length));
    });

    test('keeps pairing code and credential empty when dashboard rejects code', () async {
      final transport = _FakePairingTransport.rejected();

      final result = await service(transport).pair(
        expectedCertificateFingerprint: List.filled(64, 'b').join(),
      );

      expect(result.status, DashboardPairingAttemptStatus.rejected);
      expect(result.errorCode, 'invalid_pairing_code');
      expect(await credentialStore.read(), isNull);
      final status = await repo.syncStatus();
      expect(status['dashboard_status'], 'Not configured');
      expect(status['pairing_code_saved'], 1);
    });

    test('does not store pairing when certificate-pinned transport blocks', () async {
      final transport = _FakePairingTransport.blocked();

      final result = await service(transport).pair(
        expectedCertificateFingerprint: List.filled(64, 'c').join(),
      );

      expect(result.status, DashboardPairingAttemptStatus.transportBlocked);
      expect(result.errorCode, 'dashboard_certificate_changed');
      expect(await credentialStore.read(), isNull);
      final status = await repo.syncStatus();
      expect(status['dashboard_status'], 'Not configured');
      expect(status['pairing_code_saved'], 1);
    });

    test('does not store pairing for mismatched device response', () async {
      final transport = _FakePairingTransport.success(deviceId: 'other-device');

      final result = await service(transport).pair(
        expectedCertificateFingerprint: List.filled(64, 'd').join(),
      );

      expect(result.status, DashboardPairingAttemptStatus.invalidResponse);
      expect(await credentialStore.read(), isNull);
      final status = await repo.syncStatus();
      expect(status['dashboard_status'], 'Not configured');
      expect(status['pairing_code_saved'], 1);
    });
  });
}

class _FakePairingTransport implements PairingTransport {
  _FakePairingTransport._(this.mode, {this.overrideDeviceId});

  factory _FakePairingTransport.success({String? deviceId}) =>
      _FakePairingTransport._('success', overrideDeviceId: deviceId);

  factory _FakePairingTransport.rejected() =>
      _FakePairingTransport._('rejected');

  factory _FakePairingTransport.blocked() => _FakePairingTransport._('blocked');

  final String mode;
  final String? overrideDeviceId;
  final credential = 'credential-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
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
    if (mode == 'blocked') {
      throw const PairingTransportException(
        'dashboard_certificate_changed',
        'Dashboard certificate does not match the approved fingerprint.',
      );
    }
    if (mode == 'rejected') {
      return const PairingTransportResponse(
        statusCode: 400,
        body: '{"ok":false,"request_id":"request-1","error_code":"invalid_pairing_code","message":"Pairing code was not accepted.","retryable":false}',
      );
    }
    return PairingTransportResponse(
      statusCode: 200,
      body: jsonEncode({
        'ok': true,
        'request_id': 'request-1',
        'dashboard_id': 'dashboard-1',
        'dashboard_name': 'Synthetic Dashboard',
        'device_id': overrideDeviceId ?? request['device_id'],
        'worker_id': request['worker_id'],
        'device_credential': credential,
        'paired_at': '2026-09-16T05:31:00Z',
        'server_time': '2026-09-16T05:31:01Z',
      }),
    );
  }
}
