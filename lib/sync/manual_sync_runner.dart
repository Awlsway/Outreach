import '../database/outreach_repository.dart';
import 'sync_acknowledgement.dart';
import 'sync_batch_builder.dart';

/// Testable orchestration only. No production transport or UI is wired here.
abstract interface class SyncBatchTransport {
  Future<SyncBatchReply> send(PreparedSyncBatch batch);
}

class SyncBatchReply {
  const SyncBatchReply(this.httpStatus, this.response);
  final int httpStatus;
  final Map<String, Object?> response;
}

enum ManualSyncOutcome {
  uploaded,
  emptyQueue,
  partial,
  stopped,
  batchLimitReached,
}

class ManualSyncResult {
  const ManualSyncResult(this.outcome, this.markedOperations);
  final ManualSyncOutcome outcome;
  final int markedOperations;
}

class ManualSyncRunner {
  ManualSyncRunner({
    required this.repository,
    required this.builder,
    required this.transport,
    this.validateContext,
    this.checkDashboardStatus,
    this.maxBatchesPerRun,
    this.preparedBatches,
  }) {
    if (maxBatchesPerRun != null && maxBatchesPerRun! < 1) {
      throw ArgumentError.value(maxBatchesPerRun, 'maxBatchesPerRun');
    }
  }
  final OutreachRepository repository;
  final SyncBatchBuilder builder;
  final SyncBatchTransport transport;
  final Future<void> Function()? validateContext;
  final Future<void> Function()? checkDashboardStatus;

  /// Controlled-test bound. It does not classify payloads as synthetic.
  final int? maxBatchesPerRun;
  final List<PreparedSyncBatch>? preparedBatches;
  bool _running = false;

  Future<ManualSyncResult> run() async {
    if (_running) throw StateError('Sync already running');
    _running = true;
    var marked = 0;
    try {
      await validateContext?.call();
      final worker =
          (await repository.currentWorkerProfile())['worker_id'] as String;
      final batches =
          preparedBatches ??
          builder.build(
            appIdentity: await repository.appIdentity(),
            workerId: worker,
            pendingOperations: await repository.pendingOperations(),
          );
      await validateContext?.call();
      await checkDashboardStatus?.call();
      await validateContext?.call();
      if (batches.isEmpty) {
        // A future authenticated status request is required, not a sync success.
        return const ManualSyncResult(ManualSyncOutcome.emptyQueue, 0);
      }
      var sentCount = 0;
      for (final batch in batches) {
        if (maxBatchesPerRun != null && sentCount >= maxBatchesPerRun!) {
          return ManualSyncResult(ManualSyncOutcome.batchLimitReached, marked);
        }
        await validateContext?.call();
        if ((await repository.currentWorkerProfile())['worker_id'] != worker) {
          throw StateError('Worker session changed');
        }
        final reply = await transport.send(batch);
        sentCount++;
        await validateContext?.call();
        final receipt = SyncAcknowledgement.parse(
          reply.response,
          sentBatch: batch,
          httpStatus: reply.httpStatus,
        );
        marked += await repository.applySyncAcknowledgement(
          sentBatch: batch,
          response: reply.response,
          httpStatus: reply.httpStatus,
        );
        if (!receipt.allAccepted) {
          // Stop before later batches whose operations may depend on this one.
          return ManualSyncResult(ManualSyncOutcome.partial, marked);
        }
      }
      return ManualSyncResult(ManualSyncOutcome.uploaded, marked);
    } catch (_) {
      // No raw transport errors or payloads are returned to worker UI.
      return ManualSyncResult(ManualSyncOutcome.stopped, marked);
    } finally {
      _running = false;
    }
  }
}
