import 'dart:convert';

/// Strict parser for the short-lived LAN-generated QR pairing envelope.
///
/// The QR is only a convenient transfer of the existing address, certificate
/// pin and one-use pairing code. It is never a device credential.
class QrPairingPayload {
  const QrPairingPayload({
    required this.projectId,
    required this.dashboardId,
    required this.apiBaseUrl,
    required this.certificateSha256,
    required this.pairingCode,
    required this.issuedAt,
    required this.expiresAt,
  });

  static const prefix = 'ansvk-outreach://pair/v1#';
  static const maxQrBytes = 2048;
  static const validity = Duration(minutes: 5);
  static const clockSkew = Duration(minutes: 1);
  static final _encoded = RegExp(r'^[A-Za-z0-9_-]+$');
  static final _fingerprint = RegExp(r'^[0-9a-f]{64}$');
  static final _utcTimestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
  );
  static const _keys = <String>{
    'type',
    'version',
    'protocol',
    'protocol_version',
    'project_id',
    'dashboard_id',
    'api_base_url',
    'certificate_sha256',
    'pairing_code',
    'issued_at',
    'expires_at',
  };

  final String projectId;
  final String dashboardId;
  final Uri apiBaseUrl;
  final String certificateSha256;
  final String pairingCode;
  final DateTime issuedAt;
  final DateTime expiresAt;

  static QrPairingPayload parse(String scanned, {DateTime Function()? clock}) {
    try {
      if (utf8.encode(scanned).length > maxQrBytes ||
          !scanned.startsWith(prefix)) {
        throw const FormatException('Unsupported QR pairing code');
      }
      final encoded = scanned.substring(prefix.length);
      if (!_encoded.hasMatch(encoded) || encoded.length % 4 == 1) {
        throw const FormatException('Invalid QR pairing encoding');
      }
      final padding = '=' * ((4 - encoded.length % 4) % 4);
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode('$encoded$padding')),
      );
      if (decoded is! Map<String, dynamic> ||
          decoded.keys.toSet().difference(_keys).isNotEmpty ||
          _keys.difference(decoded.keys.toSet()).isNotEmpty) {
        throw const FormatException('Invalid QR pairing fields');
      }
      if (decoded['type'] != 'ansvk-outreach-pairing' ||
          decoded['version'] != 1 ||
          decoded['protocol'] != 'ansvk-outreach-sync' ||
          decoded['protocol_version'] != 1 ||
          decoded['project_id'] != 'ansvk_outreach') {
        throw const FormatException('Unsupported QR pairing contract');
      }
      String requiredString(String key, {int max = 200}) {
        final value = decoded[key];
        if (value is! String ||
            value.isEmpty ||
            value != value.trim() ||
            value.length > max) {
          throw FormatException('Invalid QR pairing $key');
        }
        return value;
      }

      final dashboardId = requiredString('dashboard_id');
      final apiBaseUrl = Uri.tryParse(requiredString('api_base_url'));
      if (apiBaseUrl == null ||
          apiBaseUrl.scheme != 'https' ||
          apiBaseUrl.host.isEmpty ||
          apiBaseUrl.port != 3443 ||
          apiBaseUrl.path != '/api/v1' ||
          apiBaseUrl.userInfo.isNotEmpty ||
          apiBaseUrl.hasQuery ||
          apiBaseUrl.hasFragment) {
        throw const FormatException('Invalid QR dashboard address');
      }
      final certificate = requiredString('certificate_sha256', max: 64);
      final pairingCode = requiredString('pairing_code', max: 6);
      if (!_fingerprint.hasMatch(certificate) ||
          !RegExp(r'^\d{6}$').hasMatch(pairingCode)) {
        throw const FormatException('Invalid QR pairing trust data');
      }
      DateTime timestamp(String key) {
        final value = requiredString(key, max: 32);
        if (!_utcTimestamp.hasMatch(value)) {
          throw FormatException('Invalid QR pairing $key');
        }
        return DateTime.parse(value).toUtc();
      }

      final issuedAt = timestamp('issued_at');
      final expiresAt = timestamp('expires_at');
      final now = (clock ?? DateTime.now)().toUtc();
      if (!expiresAt.isAfter(issuedAt) ||
          expiresAt.difference(issuedAt) > validity ||
          issuedAt.isAfter(now.add(clockSkew)) ||
          !expiresAt.isAfter(now)) {
        throw const FormatException('QR pairing code expired or invalid');
      }
      return QrPairingPayload(
        projectId: decoded['project_id'] as String,
        dashboardId: dashboardId,
        apiBaseUrl: apiBaseUrl,
        certificateSha256: certificate,
        pairingCode: pairingCode,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid QR pairing code');
    }
  }
}
