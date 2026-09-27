import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ansvk_outreach/sync/manual_sync_runner.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:ansvk_outreach/sync/sync_run_control.dart';

class UnusedTransport implements SyncBatchTransport {
  @override
  Future<SyncBatchReply> send(PreparedSyncBatch batch) =>
      throw UnimplementedError();
}

void main() {
  test(
    '503 and lost connection have only three visible foreground retries',
    () async {
      final messages = <String>[];
      final delays = <Duration>[];
      final control = SyncRunControl(onProgress: messages.add);
      final retry = RetryingSyncTransport(
        transport: UnusedTransport(),
        control: control,
        guard: () async {},
        random: () => .5,
        wait: (d) async {
          delays.add(d);
        },
      );
      var calls = 0;
      await expectLater(
        retry.request(() async {
          calls++;
          if (calls == 2) throw const SocketException('lost receipt');
          return const SyncBatchReply(503, {'ok': false});
        }, 'Sending'),
        throwsA(isA<SyncRequestFailure>()),
      );
      expect(calls, 4);
      expect(delays.map((d) => d.inSeconds), [5, 15, 30]);
      expect(
        messages.where((m) => m.contains('Connection interrupted.')),
        hasLength(3),
      );
    },
  );

  test(
    'permanent responses, invalid receipts and trust failures are not retried',
    () async {
      for (final status in [400, 401, 403, 409, 422]) {
        var calls = 0;
        final retry = RetryingSyncTransport(
          transport: UnusedTransport(),
          control: SyncRunControl(),
          guard: () async {},
          wait: (_) async => fail('Must not retry'),
        );
        final future = retry.request(() async {
          calls++;
          return SyncBatchReply(status, {
            'ok': false,
            'error_code': 'device_revoked',
          });
        }, 'Checking');
        if (status == 401 || status == 403) {
          await expectLater(future, throwsA(isA<SyncRequestFailure>()));
        } else {
          expect((await future).httpStatus, status);
        }
        expect(calls, 1);
      }
      final retry = RetryingSyncTransport(
        transport: UnusedTransport(),
        control: SyncRunControl(),
        guard: () async {},
        wait: (_) async => fail('Must not retry'),
      );
      await expectLater(
        retry.request(
          () async => throw const FormatException('invalid'),
          'Sending',
        ),
        throwsFormatException,
      );
      await expectLater(
        retry.request(() async => throw StateError('pin mismatch'), 'Sending'),
        throwsStateError,
      );
    },
  );

  test('Stop interrupts retry delay without making another request', () async {
    final control = SyncRunControl();
    final enteredWait = Completer<void>();
    var calls = 0;
    final retry = RetryingSyncTransport(
      transport: UnusedTransport(),
      control: control,
      guard: () async {},
      wait: (_) {
        enteredWait.complete();
        return Completer<void>().future;
      },
    );
    final result = retry.request(() async {
      calls++;
      throw const SocketException('offline');
    }, 'Sending');
    final assertion = expectLater(result, throwsA(isA<SyncStopped>()));
    await enteredWait.future;
    control.stop();
    await assertion;
    expect(calls, 1);
  });

  test(
    'Stop ignores a late success and guard prevents a later retry after locking',
    () async {
      final control = SyncRunControl();
      final pending = Completer<SyncBatchReply>();
      final entered = Completer<void>();
      final retry = RetryingSyncTransport(
        transport: UnusedTransport(),
        control: control,
        guard: () async {},
        wait: (_) async {},
      );
      final result = retry.request(() {
        entered.complete();
        return pending.future;
      }, 'Sending');
      final assertion = expectLater(result, throwsA(isA<SyncStopped>()));
      await entered.future;
      control.stop();
      await assertion;
      pending.complete(const SyncBatchReply(200, {'ok': true}));
      var locked = false;
      var calls = 0;
      final guarded = RetryingSyncTransport(
        transport: UnusedTransport(),
        control: SyncRunControl(),
        guard: () async {
          if (locked) throw StateError('locked');
        },
        wait: (_) async {
          locked = true;
        },
      );
      await expectLater(
        guarded.request(() async {
          calls++;
          throw const SocketException('offline');
        }, 'Sending'),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );
}
