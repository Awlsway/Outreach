import 'dart:async';

import 'package:ansvk_outreach/sync/dashboard_certificate_checker.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/manual_sync_runner.dart';
import 'package:ansvk_outreach/sync/secure_sync_transport.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeConnection implements SyncHttpsConnection {
  @override
  List<int> certificateDer = [1, 2, 3];
  int requests = 0;
  bool closed = false;
  String? method;
  String? body;
  Uri? uri;
  SyncBatchReply reply = const SyncBatchReply(200, {'ok': true});
  Completer<SyncBatchReply>? pending;
  @override
  Future<SyncBatchReply> request(
    Uri target,
    String verb,
    String credential,
    String? data,
  ) async {
    expect(credential, 'synthetic-credential');
    requests++;
    uri = target;
    method = verb;
    body = data;
    return pending == null ? reply : await pending!.future;
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  late DeviceCredentialStore store;
  late FakeConnection peer;
  late String pin;
  late int connections;
  setUp(() async {
    store = DeviceCredentialStore.memory();
    await store.write('synthetic-credential');
    peer = FakeConnection();
    pin = await DashboardCertificateChecker.sha256Hex(peer.certificateDer);
    connections = 0;
  });
  SecureSyncTransport transport({String? address, Duration? timeout}) =>
      SecureSyncTransport(
        baseUri: Uri.parse(address ?? 'https://192.168.1.50:3443/api/v1'),
        fingerprint: pin,
        credentialStore: store,
        timeout: timeout ?? const Duration(seconds: 30),
        connector: (_) async {
          connections++;
          return peer;
        },
      );
  test(
    'pinned upload sends exact JSON; status uses GET without body',
    () async {
      final batch = PreparedSyncBatch('{"synthetic":true}');
      await transport().send(batch);
      expect(peer.method, 'POST');
      expect(peer.uri!.path, '/api/v1/sync/batches');
      expect(peer.body, batch.jsonBody);
      expect(peer.closed, isTrue);
      peer = FakeConnection();
      await transport().checkStatus();
      expect(peer.method, 'GET');
      expect(peer.uri!.path, '/api/v1/sync/status');
      expect(peer.body, isNull);
      expect(peer.closed, isTrue);
    },
  );
  test('wrong certificate sends no credential or payload', () async {
    peer.certificateDer = [9];
    await expectLater(
      transport().send(PreparedSyncBatch('{}')),
      throwsStateError,
    );
    expect(peer.requests, 0);
    expect(peer.closed, isTrue);
  });
  test('invalid URL or pin fails before opening connection', () async {
    for (final address in [
      'http://host/api/v1',
      'https://user:pass@host/api/v1',
      'https://host/other',
      'https://host/api/v1?x=1',
    ]) {
      await expectLater(
        transport(address: address).checkStatus(),
        throwsFormatException,
      );
    }
    pin = 'invalid';
    await expectLater(transport().checkStatus(), throwsFormatException);
    expect(connections, 0);
  });
  test(
    'missing or header-injection credential fails before connection',
    () async {
      await store.clear();
      await expectLater(transport().checkStatus(), throwsStateError);
      await store.write('bad\r\nInjected: secret');
      await expectLater(transport().checkStatus(), throwsStateError);
      expect(connections, 0);
    },
  );
  test(
    'timeout closes connection; HTTP credential errors retain status',
    () async {
      peer.pending = Completer<SyncBatchReply>();
      await expectLater(
        transport(timeout: const Duration(milliseconds: 20)).checkStatus(),
        throwsA(isA<TimeoutException>()),
      );
      expect(peer.closed, isTrue);
      peer.pending!.complete(peer.reply);
      peer = FakeConnection()
        ..reply = const SyncBatchReply(401, {
          'ok': false,
          'error_code': 'device_revoked',
        });
      final reply = await transport().checkStatus();
      expect(reply.httpStatus, 401);
      expect(reply.response['ok'], isFalse);
    },
  );
  test('oversized upload cannot open connection', () async {
    expect(
      () => transport().send(PreparedSyncBatch('x' * (1024 * 1024 + 1))),
      throwsFormatException,
    );
    expect(connections, 0);
  });
}
