import 'dart:convert';
import 'dart:io';
import 'package:ansvk_outreach/sync/sync_status_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> row;
  setUp(() async {
    row = jsonDecode(
      await File(
        'docs/fixtures/outreach/v1/sync-status.response.json',
      ).readAsString(),
    );
  });
  SyncStatusResponse parse({int status = 200}) => SyncStatusResponse.parse(
    row,
    httpStatus: status,
    expectedDeviceId: '11111111-1111-4111-8111-111111111111',
    expectedWorkerId: '22222222-2222-4222-8222-222222222222',
  );
  test('accepts agreed status and nullable first-sync watermark', () {
    expect(parse().lastAcceptedSequence, 5);
    row['last_accepted_sequence'] = null;
    row['last_accepted_operation_id'] = null;
    row['last_successful_sync_at'] = null;
    expect(parse().lastSuccessfulSyncAt, isNull);
  });
  test('rejects foreign identity and inactive device', () {
    for (final field in ['device_id', 'worker_id', 'device_status']) {
      final original = row[field];
      row[field] = 'foreign';
      expect(() => parse(), throwsFormatException);
      row[field] = original;
    }
    expect(() => parse(status: 401), throwsFormatException);
    row['ok'] = false;
    expect(() => parse(), throwsFormatException);
  });
  test('rejects malformed metadata and unpaired watermark', () {
    for (final field in [
      'request_id',
      'server_time',
      'cleanup_keep_days',
      'last_accepted_sequence',
      'warnings',
    ]) {
      final original = row[field];
      row[field] = field == 'request_id' ? '' : 'invalid';
      expect(() => parse(), throwsFormatException);
      row[field] = original;
    }
    row['last_accepted_operation_id'] = null;
    expect(() => parse(), throwsFormatException);
  });
}
