import 'dart:convert';

import '../database/outreach_repository.dart';
import 'certificate_fingerprint_store.dart';
import 'device_credential_store.dart';
import 'manual_sync_runner.dart';
import 'secure_sync_transport.dart';
import 'sync_batch_builder.dart';
import 'sync_status_response.dart';
import 'reviewed_sync_plan.dart';

/// Secure integration seam, not yet connected to worker UI.
class ConfiguredManualSync {
  ConfiguredManualSync({
    required this.repository,
    required this.fingerprintStore,
    required this.credentialStore,
    required this.builder,
    this.connector,
    this.maxBatchesPerRun,
  });
  final OutreachRepository repository;
  final CertificateFingerprintStore fingerprintStore;
  final DeviceCredentialStore credentialStore;
  final SyncBatchBuilder builder;
  final SyncHttpsConnector? connector;
  final int? maxBatchesPerRun;
  bool _running = false;

  Future<ManualSyncResult> run({ReviewedSyncPlan? reviewedPlan}) async {
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
      );
      return await ManualSyncRunner(
        repository: repository,
        builder: builder,
        transport: transport,
        maxBatchesPerRun: reviewedPlan == null ? maxBatchesPerRun : 1,
        preparedBatches: reviewedPlan?.batches,
        validateContext: guard,
        checkDashboardStatus: () async {
          final reply = await transport.checkStatus();
          await guard();
          SyncStatusResponse.parse(
            reply.response,
            httpStatus: reply.httpStatus,
            expectedDeviceId: identity['device_id'] as String,
            expectedWorkerId: worker,
          );
        },
      ).run();
    } catch (_) {
      return const ManualSyncResult(ManualSyncOutcome.stopped, 0);
    } finally {
      _running = false;
    }
  }
}
