import '../database/outreach_repository.dart';
import 'certificate_renewal_qr.dart';
import 'trust_json.dart';

const certificateRenewalTable = 'certificate_renewals';

Never _invalid() =>
    throw const CertificateRenewalQrException('receipt_mismatch');
void _fields(Map<String, dynamic> value, List<String> names) {
  if (value.length != names.length || names.any((n) => !value.containsKey(n))) {
    _invalid();
  }
}

String _text(Object? value) {
  if (value is! String || value.isEmpty || value.trim() != value) _invalid();
  return value;
}

int _integer(Object? value, int max) {
  if (value is! int || value <= 0 || value > max) _invalid();
  return value;
}

void _uuid(Object? value) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  ).hasMatch(_text(value))) {
    _invalid();
  }
}

Map<String, dynamic> _saved(Object? text) => decodeTrustJson(_text(text));

Map<String, dynamic> renewalReceipt(
  Map<String, dynamic> value,
  VerifiedCertificateRenewal grant,
) {
  _fields(value, [
    'receipt_id',
    'grant_id',
    'grant_digest',
    'dashboard_id',
    'project_id',
    'device_id',
    'worker_id',
    'api_base_url',
    'from_certificate_sha256',
    'from_generation',
    'to_certificate_sha256',
    'to_generation',
    'claimed_at',
  ]);
  _uuid(value['receipt_id']);
  final expected = {
    'grant_id': grant.grantId,
    'grant_digest': grant.grantDigest,
    'dashboard_id': grant.context.dashboardId,
    'project_id': grant.context.projectId,
    'device_id': grant.context.deviceId,
    'worker_id': grant.context.workerId,
    'api_base_url': grant.context.apiBaseUrl,
    'from_certificate_sha256': grant.context.certificateSha256,
    'to_certificate_sha256': grant.toCertificateSha256,
  };
  for (final entry in expected.entries) {
    if (_text(value[entry.key]) != entry.value) _invalid();
  }
  if (_integer(value['from_generation'], 2147483647) !=
          grant.context.generation ||
      _integer(value['to_generation'], 2147483647) != grant.toGeneration) {
    _invalid();
  }
  final claimedAt = _integer(value['claimed_at'], 253402300799);
  if (claimedAt < grant.issuedAt || claimedAt >= grant.expiresAt) _invalid();
  return Map.unmodifiable(value);
}

Map<String, dynamic> renewalClaimReply(
  Map<String, dynamic> reply,
  int status,
  VerifiedCertificateRenewal grant,
) {
  if (status != 200 && status != 201) _invalid();
  _fields(reply, ['ok', 'request_id', 'receipt']);
  if (reply['ok'] != true || reply['receipt'] is! Map<String, dynamic>) {
    _invalid();
  }
  _text(reply['request_id']);
  return renewalReceipt(reply['receipt'], grant);
}

Map<String, dynamic> renewalConfirmation(
  Map<String, dynamic> reply,
  int status,
  Map<String, dynamic> receipt,
) {
  if (status != 200) _invalid();
  _fields(reply, [
    'ok',
    'request_id',
    'receipt_id',
    'grant_digest',
    'device_id',
    'certificate_sha256',
    'generation',
    'state',
  ]);
  if (reply['ok'] != true || reply['state'] != 'confirmed') _invalid();
  _text(reply['request_id']);
  for (final key in ['receipt_id', 'grant_digest', 'device_id']) {
    if (_text(reply[key]) != receipt[key]) _invalid();
  }
  if (_text(reply['certificate_sha256']) != receipt['to_certificate_sha256'] ||
      _integer(reply['generation'], 2147483647) != receipt['to_generation']) {
    _invalid();
  }
  return Map.unmodifiable(reply);
}

String? authenticatedUnusedRejection(Map<String, dynamic> reply, int status) {
  if (status != 409 ||
      reply['ok'] != false ||
      ![
        'renewal_grant_expired',
        'renewal_grant_cancelled',
      ].contains(reply['error_code'])) {
    return null;
  }
  _fields(reply, [
    'ok',
    'request_id',
    'error_code',
    'message',
    'retryable',
    'details',
  ]);
  _text(reply['request_id']);
  _text(reply['message']);
  if (reply['retryable'] != false ||
      reply['details'] is! List ||
      (reply['details'] as List).isNotEmpty) {
    _invalid();
  }
  return reply['error_code'] as String;
}

class CertificateRenewalRecord {
  CertificateRenewalRecord(this.row, this.grant, this.receipt);
  final Row row;
  final VerifiedCertificateRenewal grant;
  final Map<String, dynamic>? receipt;
  String get state => row['state'] as String;
}

class CertificateRenewalState {
  CertificateRenewalState(this.context, this.records, this.bootstrapConfirmed);
  final CertificateRenewalContext context;
  final List<CertificateRenewalRecord> records;
  final bool bootstrapConfirmed;
  List<Row> get rows => records.map((r) => r.row).toList();
  CertificateRenewalRecord? get pendingClaim =>
      records.where((r) => r.state == 'claim_pending').firstOrNull;
  CertificateRenewalRecord? get pendingConfirmation =>
      records.where((r) => r.state == 'confirmation_pending').firstOrNull;
  bool get canSync =>
      (bootstrapConfirmed || records.any((r) => r.receipt != null)) &&
      pendingClaim == null &&
      pendingConfirmation == null;

  /// Only durable history uses its saved verification time. Fresh scans always
  /// use the current clock. InitialCertificateTrust checks authority validity NOW.
  static Future<CertificateRenewalState> restore(
    CertificateRenewalContext base,
    List<Row> rows,
    bool bootstrapConfirmed,
  ) async {
    var current = base;
    final records = <CertificateRenewalRecord>[];
    var sequence = 0;
    for (final row in rows) {
      if (records.any((r) => r.state == 'claim_pending')) _invalid();
      final nextSequence = _integer(row['sequence'], 9223372036854775807);
      if (nextSequence <= sequence) _invalid();
      sequence = nextSequence;
      final stamp = _integer(row['verified_at'], 253402300799);
      final grant =
          await CertificateRenewalQrVerifier(
            clock: () =>
                DateTime.fromMillisecondsSinceEpoch(stamp * 1000, isUtc: true),
          ).verify(
            CertificateRenewalQrVerifier.prefix + _text(row['compact_jws']),
            context: current,
          );
      if (grant.grantId != row['grant_id']) _invalid();
      Map<String, dynamic>? receipt;
      final state = row['state'];
      if ([
        'confirmation_pending',
        'confirmed',
        'confirmed_by_successor',
      ].contains(state)) {
        receipt = renewalReceipt(_saved(row['receipt_json']), grant);
        if (state == 'confirmed') {
          renewalConfirmation(_saved(row['confirmation_json']), 200, receipt);
        } else if (row['confirmation_json'] != null) {
          _invalid();
        }
        current = current.atCertificate(
          grant.toCertificateSha256,
          grant.toGeneration,
        );
      } else if (state == 'claim_pending' || state == 'rejected') {
        if (row['receipt_json'] != null || row['confirmation_json'] != null) {
          _invalid();
        }
        if (state == 'rejected' &&
            ![
              'renewal_grant_expired',
              'renewal_grant_cancelled',
            ].contains(row['rejection_code'])) {
          _invalid();
        }
      } else {
        _invalid();
      }
      if ((state == 'confirmed_by_successor') !=
          (row['confirmed_by_grant_id'] != null)) {
        _invalid();
      }
      if (state != 'rejected' && row['rejection_code'] != null) _invalid();
      records.add(
        CertificateRenewalRecord(Map.unmodifiable(row), grant, receipt),
      );
    }
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      final next = records
          .skip(i + 1)
          .where((r) => r.receipt != null)
          .firstOrNull;
      if (record.state == 'confirmation_pending' && next != null) _invalid();
      if (record.state == 'confirmed_by_successor' &&
          (next == null ||
              next.grant.grantId != record.row['confirmed_by_grant_id'] ||
              next.grant.context.certificateSha256 !=
                  record.grant.toCertificateSha256 ||
              next.grant.context.generation != record.grant.toGeneration)) {
        _invalid();
      }
    }
    if (records.where((r) => r.state == 'confirmation_pending').length > 1) {
      _invalid();
    }
    return CertificateRenewalState(
      current,
      List.unmodifiable(records),
      bootstrapConfirmed,
    );
  }
}
