import 'dart:convert';

import '../database/outreach_repository.dart';
import 'certificate_fingerprint_store.dart';
import 'device_credential_store.dart';
import 'manual_sync_runner.dart';
import 'secure_sync_transport.dart';
import 'sync_batch_builder.dart';
import 'sync_status_response.dart';
import 'reviewed_sync_plan.dart';
import 'sync_run_control.dart';

/// Secure foreground sync shared by the ordinary UI and reviewed test path.
class ConfiguredManualSync {
  ConfiguredManualSync({
    required this.repository,
    required this.fingerprintStore,
    required this.credentialStore,
    required this.builder,
    this.connector,
    this.maxBatchesPerRun,
    this.retryWait,
    this.retryRandom,
  });
  final OutreachRepository repository;
  final CertificateFingerprintStore fingerprintStore;
  final DeviceCredentialStore credentialStore;
  final SyncBatchBuilder builder;
  final SyncHttpsConnector? connector;
  final int? maxBatchesPerRun;
  final Future<void> Function(Duration)? retryWait;
  final double Function()? retryRandom;
  bool _running = false;

  Future<ManualSyncResult> run({
    ReviewedSyncPlan? reviewedPlan,
    SyncRunControl? control,
  }) async {
    if (_running) throw StateError('Sync already running');
    _running = true;
    try {
      final worker =
          (await repository.currentWorkerProfile())['worker_id'] as String;
      final identity = await repository.appIdentity();
      final config = await repository.dashboardPairingPreparation();
      final pin = await fingerprintStore.read();
      final credential = await credentialStore.read();
      if (config['status'] != 'Paired' ||
          pin == null ||
          credential == null ||
          config['dashboard_id'] is! String ||
          config['paired_at'] is! String) {
        throw StateError('Dashboard pairing is unavailable');
      }
      final configSnapshot = jsonEncode(config);
      Future<void> guard() async {
        control?.check();
        await reviewedPlan?.validate(repository);
        if ((await repository.currentWorkerProfile())['worker_id'] != worker ||
            jsonEncode(await repository.appIdentity()) !=
                jsonEncode(identity) ||
            jsonEncode(await repository.dashboardPairingPreparation()) !=
                configSnapshot ||
            await fingerprintStore.read() != pin ||
            await credentialStore.read() != credential) {
          throw StateError('Sync context changed');
        }
        if (repository.currentWorkerId() != worker) {
          throw StateError('Worker session changed');
        }
      }

      final transport = SecureSyncTransport(
        baseUri: Uri.parse(config['dashboard_url'] as String),
        fingerprint: pin,
        credentialStore: credentialStore,
        connector: connector,
        beforeSend: guard,
        control: control,
      );
      final retrying = control == null
          ? null
          : RetryingSyncTransport(
              transport: transport,
              control: control,
              guard: guard,
              wait: retryWait,
              random: retryRandom,
            );
      final result = await ManualSyncRunner(
        repository: repository,
        builder: builder,
        transport: retrying ?? transport,
        control: control,
        dashboardId: config['dashboard_id'] as String,
        maxBatchesPerRun: reviewedPlan == null ? maxBatchesPerRun : 1,
        preparedBatches: reviewedPlan?.batches,
        validateContext: guard,
        checkDashboardStatus: () async {
          final reply = retrying == null
              ? await transport.checkStatus()
              : await retrying.request(
                  transport.checkStatus,
                  'Checking dashboard access',
                );
          await guard();
          SyncStatusResponse.parse(
            reply.response,
            httpStatus: reply.httpStatus,
            expectedDeviceId: identity['device_id'] as String,
            expectedWorkerId: worker,
          );
        },
      ).run();
      if (reviewedPlan == null &&
          (result.outcome == ManualSyncOutcome.uploaded ||
              result.outcome == ManualSyncOutcome.emptyQueue)) {
        try {
          await guard();
          final cleanup = await repository.cleanupAcknowledgedEncounters(
            expectedDashboardId: config['dashboard_id'] as String,
            expectedProjectId: identity['project_id'] as String,
            expectedDeviceId: identity['device_id'] as String,
            mayContinue: () =>
                control?.stopped != true &&
                repository.currentWorkerId() == worker,
          );
          return ManualSyncResult(
            result.outcome,
            result.markedOperations,
            cleanup: cleanup,
          );
        } catch (_) {
          // Cleanup failure must never turn accepted uploads into a failed send.
          return ManualSyncResult(
            result.outcome,
            result.markedOperations,
            cleanupFailed: true,
          );
        }
      }
      return result;
    } catch (error) {
      return ManualSyncResult(
        ManualSyncOutcome.stopped,
        0,
        message: error is SyncStopped
            ? 'Sync stopped.'
            : error is SyncRequestFailure
            ? error.message
            : 'Dashboard pairing or access could not be verified. Ask the data assistant to check this phone.',
      );
    } finally {
      _running = false;
    }
  }
}
