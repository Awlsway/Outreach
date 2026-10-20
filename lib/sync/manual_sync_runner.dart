import '../database/outreach_repository.dart';
import '../database/retention_cleanup.dart';
import 'sync_acknowledgement.dart';
import 'sync_batch_builder.dart';
import 'sync_run_control.dart';

/// Sequential, testable upload orchestration with exact receipt application.
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
  const ManualSyncResult(
    this.outcome,
    this.markedOperations, {
    this.message,
    this.cleanup,
    this.cleanupFailed = false,
  });
  final ManualSyncOutcome outcome;
  final int markedOperations;
  final String? message;
  final RetentionCleanupResult? cleanup;
  final bool cleanupFailed;
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
    this.control,
    this.dashboardId,
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
  final SyncRunControl? control;
  final String? dashboardId;
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
        // The authenticated status check does not invent an upload success time.
        return const ManualSyncResult(ManualSyncOutcome.emptyQueue, 0);
      }
      var sentCount = 0;
      for (final batch in batches) {
        if (control != null) {
          control!.batchLabel = 'Batch ${sentCount + 1} of ${batches.length}';
          control!.report('Sending...');
        }
        if (maxBatchesPerRun != null && sentCount >= maxBatchesPerRun!) {
          return ManualSyncResult(ManualSyncOutcome.batchLimitReached, marked);
        }
        await validateContext?.call();
        if ((await repository.currentWorkerProfile())['worker_id'] != worker) {
          throw StateError('Worker session changed');
        }
        final reply = await transport.send(batch);
        control?.check();
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
          expectedDashboardId: dashboardId,
          httpStatus: reply.httpStatus,
        );
        if (!receipt.allAccepted) {
          // Stop before later batches whose operations may depend on this one.
          return ManualSyncResult(ManualSyncOutcome.partial, marked);
        }
      }
      return ManualSyncResult(ManualSyncOutcome.uploaded, marked);
    } catch (error) {
      // No raw transport errors or payloads are returned to worker UI.
      return ManualSyncResult(
        ManualSyncOutcome.stopped,
        marked,
        message: error is SyncStopped
            ? 'Sync stopped.'
            : error is SyncRequestFailure
            ? error.message
            : 'Sync could not be confirmed. Check dashboard access and try again.',
      );
    } finally {
      _running = false;
    }
  }
}
