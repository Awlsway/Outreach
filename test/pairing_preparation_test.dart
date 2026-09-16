import 'dart:convert';
import 'dart:io';

import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/pairing_request_builder.dart';
import 'package:ansvk_outreach/sync/pairing_response.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
