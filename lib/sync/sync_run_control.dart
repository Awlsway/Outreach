import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'manual_sync_runner.dart';
import 'sync_batch_builder.dart';

class SyncStopped implements Exception {}

class SyncRequestFailure implements Exception {
  SyncRequestFailure(this.message);
  final String message;
}

/// One foreground run. Cancellation also interrupts waits and in-flight replies.
class SyncRunControl {
  SyncRunControl({this.onProgress});
  final void Function(String message)? onProgress;
  final _stopped = Completer<void>();
  String? batchLabel;
  bool get stopped => _stopped.isCompleted;
  void stop() {
    if (!stopped) _stopped.complete();
  }

  void check() {
    if (stopped) throw SyncStopped();
  }

  void report(String message) {
    check();
    onProgress?.call(batchLabel == null ? message : '$batchLabel: $message');
  }

  Future<T> interruptible<T>(Future<T> action) async {
    // The action has already started; observe late errors even after Stop.
    try {
      final result = await Future.any<T>([
        action,
        _stopped.future.then<T>((_) => throw SyncStopped()),
      ]);
      check();
      return result;
    } catch (_) {
      check();
      rethrow;
    }
  }
}

/// Retries only transient failures, retaining the same batch and JSON bytes.
class RetryingSyncTransport implements SyncBatchTransport {
  RetryingSyncTransport({
    required this.transport,
    required this.control,
    required this.guard,
    Future<void> Function(Duration)? wait,
    double Function()? random,
  }) : wait = wait ?? Future<void>.delayed,
       random = random ?? Random().nextDouble;
  final SyncBatchTransport transport;
  final SyncRunControl control;
  final Future<void> Function() guard;
  final Future<void> Function(Duration) wait;
  final double Function() random;

  @override
  Future<SyncBatchReply> send(PreparedSyncBatch batch) =>
      request(() => transport.send(batch), 'Sending changes');

  Future<SyncBatchReply> request(
    Future<SyncBatchReply> Function() action,
    String label,
  ) async {
    const delays = [5, 15, 30];
    for (var attempt = 0; ; attempt++) {
      control.check();
      await guard();
      control.report(
        '$label${attempt == 0 ? '' : ' (retry $attempt of 3)'}...',
      );
      try {
        final reply = await control.interruptible(action());
        control.check();
        await guard();
        if (![408, 429, 500, 502, 503, 504].contains(reply.httpStatus)) {
          if (reply.httpStatus == 401 || reply.httpStatus == 403) {
            final code = reply.response['error_code'];
            throw SyncRequestFailure(
              code == 'device_revoked'
                  ? 'This phone was revoked. Ask the data assistant for help.'
                  : code == 'device_retired'
                  ? 'This phone was retired. Ask the data assistant for help.'
                  : 'Dashboard access was denied. Ask the data assistant to check this phone.',
            );
          }
          return reply;
        }
      } on SocketException {
        // Connection failures can be retried; trust/context errors cannot.
      } on TimeoutException {
        // A lost receipt leaves changes pending until an exact retry confirms it.
      }
      if (attempt == delays.length) {
        throw SyncRequestFailure(
          'Could not complete sync after 3 retries. Check Wi-Fi and the dashboard, then tap Sync again.',
        );
      }
      final seconds = (delays[attempt] * (0.9 + random() * 0.2)).round();
      control.report(
        'Connection interrupted. Retry ${attempt + 1} of 3 in $seconds seconds.',
      );
      await control.interruptible(wait(Duration(seconds: seconds)));
    }
  }
}
