import 'dart:convert';
import '../database/outreach_repository.dart';
import 'sync_batch_builder.dart';
import 'sync_review_manifest.dart';

/// Memory-only frozen preparation. Never persist/log these service payloads.
class ReviewedSyncPlan {
  ReviewedSyncPlan._(
    this.workerId,
    this._identity,
    this._pending,
    List<PreparedSyncBatch> batches,
    this.manifest,
  ) : batches = List.unmodifiable(batches);
  final String workerId;
  final String _identity, _pending;
  final List<PreparedSyncBatch> batches;
  final SyncReviewManifest manifest;

  static Future<ReviewedSyncPlan> prepare(
    OutreachRepository repository,
    SyncBatchBuilder builder,
  ) async {
    final worker =
        (await repository.currentWorkerProfile())['worker_id'] as String;
    final identity = await repository.appIdentity();
    final pending = await repository.pendingOperations();
    final batches = builder.build(
      appIdentity: identity,
      workerId: worker,
      pendingOperations: pending,
    );
    if (batches.isEmpty) throw StateError('No batch to review');
    final plan = ReviewedSyncPlan._(
      worker,
      jsonEncode(identity),
      jsonEncode(pending),
      batches,
      await SyncReviewManifest.fromBatch(batches.first),
    );
    await plan.validate(repository);
    return plan;
  }

  Future<void> validate(OutreachRepository repository) async {
    if (repository.currentWorkerId() != workerId ||
        jsonEncode(await repository.appIdentity()) != _identity ||
        jsonEncode(await repository.pendingOperations()) != _pending ||
        repository.currentWorkerId() != workerId) {
      throw StateError('Reviewed data changed; prepare and review again');
    }
  }
}
