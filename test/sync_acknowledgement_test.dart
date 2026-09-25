import 'dart:convert';
import 'dart:io';

import 'package:ansvk_outreach/sync/sync_acknowledgement.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Map<String, dynamic>> fixture(String name, String kind) async =>
      jsonDecode(
            await File(
              'docs/fixtures/outreach/v1/$name.$kind.json',
            ).readAsString(),
          )
          as Map<String, dynamic>;
  late Map<String, dynamic> response;
  late PreparedSyncBatch sent;
  setUp(() async {
    sent = PreparedSyncBatch(
      jsonEncode(await fixture('sync-create', 'request')),
    );
    response = await fixture('sync-create', 'response');
  });
  SyncAcknowledgement parse(Map<String, Object?> row, {int status = 200}) =>
      SyncAcknowledgement.parse(row, sentBatch: sent, httpStatus: status);

  for (final name in [
    'sync-create',
    'sync-duplicate',
    'sync-revisions',
    'sync-partial',
    'sync-hotspot-no-gps',
  ]) {
    test(
      'validates accepted $name fixture against its exact request',
      () async {
        final request = await fixture(
          name == 'sync-duplicate' ? 'sync-create' : name,
          'request',
        );
        final receipt = SyncAcknowledgement.parse(
          await fixture(name, 'response'),
          sentBatch: PreparedSyncBatch(jsonEncode(request)),
          httpStatus: 200,
        );
        expect(receipt.batchId, request['batch_id']);
        expect(receipt.missingOperationIds, isEmpty);
        expect(receipt.allAccepted, name != 'sync-partial');
        if (name == 'sync-duplicate') {
          expect(receipt.accepted.every((op) => op.duplicate), isTrue);
        }
        if (name == 'sync-partial') {
          expect(receipt.accepted, hasLength(1));
          expect(receipt.rejected.single.errorCode, 'missing_parent_operation');
          expect(receipt.rejected.single.retryable, isTrue);
        }
      },
    );
  }
  test('rejects wrong batch and non-success HTTP or envelope status', () {
    expect(
      () => parse({...response, 'batch_id': 'another-batch'}),
      throwsFormatException,
    );
    expect(() => parse({...response, 'ok': false}), throwsFormatException);
    expect(() => parse(response, status: 503), throwsFormatException);
  });
  for (final field in [
    'operation_id',
    'entity_type',
    'entity_id',
    'revision',
    'sequence',
  ]) {
    test('rejects mismatched accepted $field', () {
      (response['accepted'] as List).first[field] =
          ['revision', 'sequence'].contains(field) ? 999 : 'another';
      expect(() => parse(response), throwsFormatException);
    });
  }
  test('rejects duplicates and accepted/rejected overlaps', () {
    final item = (response['accepted'] as List).first as Map<String, dynamic>;
    (response['accepted'] as List).add({...item});
    expect(() => parse(response), throwsFormatException);
    (response['accepted'] as List).removeLast();
    response['rejected'] = [
      {
        ...item,
        'error_code': 'missing_parent_operation',
        'retryable': true,
        'message': 'Rejected',
      },
    ];
    expect(() => parse(response), throwsFormatException);
  });
  test(
    'missing operations prevent full acceptance without inventing receipts',
    () {
      final removed = (response['accepted'] as List).removeLast();
      final result = parse(response);
      expect(result.allAccepted, isFalse);
      expect(result.accepted, hasLength(2));
      expect(result.missingOperationIds, [removed['operation_id']]);
      expect(() => result.accepted.clear(), throwsUnsupportedError);
    },
  );
  test('rejects malformed receipt fields and missing metadata', () {
    for (final field in [
      'accepted',
      'rejected',
      'warnings',
      'request_id',
      'dashboard_received_at',
      'retry_after_seconds',
    ]) {
      final bad = {...response}..remove(field);
      expect(() => parse(bad), throwsFormatException);
    }
    expect(
      () => parse({...response, 'dashboard_received_at': 'not-a-time'}),
      throwsFormatException,
    );
    expect(
      () => parse({...response, 'retry_after_seconds': -1}),
      throwsFormatException,
    );
    (response['accepted'] as List).first['duplicate'] = 'true';
    expect(() => parse(response), throwsFormatException);
  });
  test(
    'checks rejected identities and retry flags as strictly as accepted entries',
    () async {
      sent = PreparedSyncBatch(
        jsonEncode(await fixture('sync-partial', 'request')),
      );
      response = await fixture('sync-partial', 'response');
      final rejected = (response['rejected'] as List).first;
      rejected['revision'] = 999;
      expect(() => parse(response), throwsFormatException);
      rejected['revision'] = 1;
      rejected['retryable'] = 'true';
      expect(() => parse(response), throwsFormatException);
    },
  );
  test(
    'preserves warnings and retry delay without interpreting them as acceptance',
    () {
      response['accepted'] = [];
      response['warnings'] = [
        {'code': 'clock_skew', 'message': 'Phone time differs.'},
      ];
      response['retry_after_seconds'] = 15;
      final result = parse(response);
      expect(result.allAccepted, isFalse);
      expect(result.missingOperationIds, hasLength(3));
      expect(result.warnings.single.code, 'clock_skew');
      expect(result.retryAfterSeconds, 15);
    },
  );
}
