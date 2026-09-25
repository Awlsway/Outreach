import 'dart:async';
import 'dart:convert';

import 'package:ansvk_outreach/database/app_database.dart';
import 'package:ansvk_outreach/database/outreach_repository.dart';
import 'package:ansvk_outreach/sync/manual_sync_runner.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeTransport implements SyncBatchTransport {
  final sent = <PreparedSyncBatch>[];
  bool partial = false;
  int? failAt;
  Completer<void>? pause;
  @override
  Future<SyncBatchReply> send(PreparedSyncBatch batch) async {
    sent.add(batch);
    if (pause != null) await pause!.future;
    if (sent.length == failAt) throw StateError('Synthetic connection failure');
    final request = jsonDecode(batch.jsonBody);
    final ops = request['operations'] as List;
    return SyncBatchReply(200, {
      'ok': true,
      'batch_id': request['batch_id'],
      'request_id': 'synthetic',
      'dashboard_received_at': '2026-09-17T00:00:00Z',
      'accepted': [
        for (final op in partial ? ops.take(1) : ops)
          {
            for (final key in [
              'operation_id',
              'entity_type',
              'entity_id',
              'revision',
              'sequence',
            ])
              key: op[key],
            'accepted_at': '2026-09-17T00:00:00Z',
            'duplicate': false,
          },
      ],
      'rejected': [],
      'warnings': [],
      'retry_after_seconds': null,
    });
  }
}

void main() {
  late AppDatabase db;
  late OutreachRepository repo;
  late FakeTransport transport;
  late ManualSyncRunner runner;
  String? worker;
  setUp(() async {
    sqfliteFfiInit();
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = OutreachRepository(db, currentWorkerId: () => worker);
    worker = await repo.createWorkerProfile('synthetic');
    for (var i = 0; i < 100; i++) {
      await repo.createHotspot(name: 'Synthetic $i');
    }
    transport = FakeTransport();
    runner = ManualSyncRunner(
      repository: repo,
      builder: SyncBatchBuilder(
        appVersion: 'test',
        clock: () => DateTime.utc(2026),
      ),
      transport: transport,
    );
  });
  tearDown(() async {
    await db.close();
    worker = null;
  });
  test('uploads ordered batches and marks exact acknowledgements', () async {
    final result = await runner.run();
    expect(result.outcome, ManualSyncOutcome.uploaded);
    expect(result.markedOperations, 101);
    expect(transport.sent, hasLength(2));
    expect(await repo.pendingOperations(), isEmpty);
    expect((await runner.run()).outcome, ManualSyncOutcome.emptyQueue);
    expect(transport.sent, hasLength(2));
  });
  test('partial reply stops before dependent later batch', () async {
    transport.partial = true;
    final result = await runner.run();
    expect(result.outcome, ManualSyncOutcome.partial);
    expect(result.markedOperations, 1);
    expect(transport.sent, hasLength(1));
    expect(await repo.pendingOperations(), hasLength(100));
  });
  test(
    'one-batch bound preserves later operations until another explicit run',
    () async {
      runner = ManualSyncRunner(
        repository: repo,
        builder: runner.builder,
        transport: transport,
        maxBatchesPerRun: 1,
      );
      final result = await runner.run();
      expect(result.outcome, ManualSyncOutcome.batchLimitReached);
      expect(result.markedOperations, 100);
      expect(transport.sent, hasLength(1));
      expect(await repo.pendingOperations(), hasLength(1));
      final next = await runner.run();
      expect(next.outcome, ManualSyncOutcome.uploaded);
      expect(next.markedOperations, 1);
      expect(transport.sent, hasLength(2));
    },
  );
  test('invalid batch bound fails before sending', () {
    expect(
      () => ManualSyncRunner(
        repository: repo,
        builder: runner.builder,
        transport: transport,
        maxBatchesPerRun: 0,
      ),
      throwsArgumentError,
    );
    expect(transport.sent, isEmpty);
  });
  test(
    'connection failure retains unconfirmed batch and earlier acceptance',
    () async {
      transport.failAt = 2;
      final result = await runner.run();
      expect(result.outcome, ManualSyncOutcome.stopped);
      expect(result.markedOperations, 100);
      expect(await repo.pendingOperations(), hasLength(1));
      transport.failAt = null;
      expect((await runner.run()).markedOperations, 1);
    },
  );
  test(
    'blocks concurrent runs and cannot apply receipt after session locks',
    () async {
      transport.pause = Completer<void>();
      final first = runner.run();
      while (transport.sent.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await expectLater(runner.run(), throwsStateError);
      worker = null;
      transport.pause!.complete();
      expect((await first).outcome, ManualSyncOutcome.stopped);
      expect(
        (await db.connection.query(
          'sync_outbox',
        )).every((r) => r['acknowledged_at'] == null),
        isTrue,
      );
    },
  );
}
