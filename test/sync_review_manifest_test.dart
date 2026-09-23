import 'dart:convert';
import 'dart:io';
import 'package:ansvk_outreach/sync/dashboard_certificate_checker.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:ansvk_outreach/sync/sync_review_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'manifest preserves exact identities and hashes without changing batch',
    () async {
      final json = await File(
        'docs/fixtures/outreach/v1/sync-create.request.json',
      ).readAsString();
      final batch = PreparedSyncBatch(json);
      final manifest = await SyncReviewManifest.fromBatch(batch);
      final request = jsonDecode(json);
      expect(manifest.batchId, request['batch_id']);
      expect(manifest.operations, hasLength(3));
      expect(
        manifest.bodyHash,
        await DashboardCertificateChecker.sha256Hex(utf8.encode(json)),
      );
      for (var i = 0; i < manifest.operations.length; i++) {
        final entry = manifest.operations[i];
        expect(entry.operationId, request['operations'][i]['operation_id']);
        expect(entry.sequence, request['operations'][i]['sequence']);
        expect(entry.dependencies, isEmpty);
        expect(
          entry.payloadHash,
          await DashboardCertificateChecker.sha256Hex(
            utf8.encode(jsonEncode(request['operations'][i]['payload'])),
          ),
        );
      }
      expect(() => manifest.operations.clear(), throwsUnsupportedError);
      expect(batch.jsonBody, json);
    },
  );
  test('missing in-batch parents require dashboard confirmation', () async {
    final request = jsonDecode(
      await File(
        'docs/fixtures/outreach/v1/sync-create.request.json',
      ).readAsString(),
    );
    request['operations'] = [request['operations'].last];
    final manifest = await SyncReviewManifest.fromBatch(
      PreparedSyncBatch(jsonEncode(request)),
    );
    expect(manifest.operations.single.dependencies, hasLength(2));
    expect(
      () => manifest.operations.single.dependencies.clear(),
      throwsUnsupportedError,
    );
  });
  test(
    'revision preview uses after snapshot and flags absent prior revision',
    () async {
      final request = jsonDecode(
        await File(
          'docs/fixtures/outreach/v1/sync-revisions.request.json',
        ).readAsString(),
      );
      final manifest = await SyncReviewManifest.fromBatch(
        PreparedSyncBatch(jsonEncode(request)),
      );
      expect(
        manifest.operations.first.dependencies,
        contains('Previous revision needs dashboard confirmation'),
      );
      expect(
        manifest.operations.last.dependencies,
        isNot(contains('Previous revision needs dashboard confirmation')),
      );
      expect(
        manifest.operations.first.label,
        request['operations'].first['payload']['after']['client_code'],
      );
    },
  );
}
