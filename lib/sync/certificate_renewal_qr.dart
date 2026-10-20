import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'peer_certificate_verifier.dart';
import 'trust_json.dart';

class CertificateRenewalQrException implements Exception {
  const CertificateRenewalQrException(this.code);
  final String code;

  String get message => switch (code) {
    'authority_unavailable' =>
      'The saved office approval key is unavailable or expired. Contact the data assistant.',
    'expired' => 'This renewal QR has expired. Ask for a new QR.',
    'not_yet_valid' =>
      'This renewal QR is not valid yet. Check the phone time with the data assistant.',
    'renewal_pending' =>
      'A certificate renewal is still pending. Resume it before starting another.',
    'renewal_unavailable' =>
      'Certificate renewal could not finish. Records and renewal proof remain saved. Contact the data assistant.',
    'receipt_mismatch' =>
      'The dashboard renewal reply could not be verified. Renewal proof remains saved.',
    'identity_mismatch' =>
      'This renewal QR is not for this paired phone and worker.',
    'from_state_mismatch' || 'trust_changed' =>
      'The phone or sign-in state changed. Scan a new renewal QR.',
    _ => 'This is not a valid office certificate renewal QR.',
  };

  @override
  String toString() => 'CertificateRenewalQrException($code)';
}

/// A snapshot read from authenticated, committed local trust, never from a QR.
class CertificateRenewalContext {
  const CertificateRenewalContext({
    required this.dashboardId,
    required this.projectId,
    required this.deviceId,
    required this.workerId,
    required this.apiBaseUrl,
    required this.certificateSha256,
    required this.generation,
    required this.authorityJson,
    required this.binding,
  });

  final String dashboardId, projectId, deviceId, workerId, apiBaseUrl;
  final String certificateSha256, authorityJson, binding;
  final int generation;

  CertificateRenewalContext atCertificate(String pin, int generation) =>
      CertificateRenewalContext(
        dashboardId: dashboardId,
        projectId: projectId,
        deviceId: deviceId,
        workerId: workerId,
        apiBaseUrl: apiBaseUrl,
        certificateSha256: pin,
        generation: generation,
        authorityJson: authorityJson,
        binding: binding,
      );
}

class VerifiedCertificateRenewal {
  const VerifiedCertificateRenewal._({
    required this.compactJws,
    required this.grantDigest,
    required this.context,
    required this.grantId,
    required this.toCertificateSha256,
    required this.toGeneration,
    required this.issuedAt,
    required this.expiresAt,
  });

  // Preserve the original signed bytes for revalidation and the later claim.
  // Never log, display, or include these bytes in exception messages.
  final String compactJws, grantDigest, grantId, toCertificateSha256;
  final CertificateRenewalContext context;
  final int toGeneration, issuedAt, expiresAt;

  @override
  String toString() => 'VerifiedCertificateRenewal';
}

class CertificateRenewalQrVerifier {
  CertificateRenewalQrVerifier({DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  final DateTime Function() clock;
  static const prefix = 'ansvk-outreach://renew-certificate/v1#';
  static const maxQrBytes = 2048;
  static const _maxGeneration = 2147483647;
  static const _maxTime = 253402300799;
  static final _hex = RegExp(r'^[0-9a-f]{64}$');
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static const _payloadFields = [
    'version',
    'purpose',
    'dashboard_id',
    'project_id',
    'device_id',
    'worker_id',
    'api_base_url',
    'grant_id',
    'from_certificate_sha256',
    'from_generation',
    'to_certificate_sha256',
    'to_generation',
    'iat',
    'exp',
  ];

  static Never _bad([String code = 'invalid_qr']) =>
      throw CertificateRenewalQrException(code);

  static void _fields(Map<String, dynamic> value, List<String> names) {
    if (value.length != names.length ||
        names.any((name) => !value.containsKey(name))) {
      _bad();
    }
  }

  static String _text(Object? value) {
    if (value is! String || value.isEmpty || value.trim() != value) _bad();
    return value;
  }

  static int _integer(Object? value, int max) {
    if (value is! int || value <= 0 || value > max) _bad();
    return value;
  }

  static List<int> _decode64(String text) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text)) _bad();
    final bytes = base64Url.decode(base64Url.normalize(text));
    if (base64Url.encode(bytes).replaceAll('=', '') != text) _bad();
    return bytes;
  }

  static Future<String> _digest(List<int> bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static void _endpoint(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !PeerCertificateVerifier.isIpv4(uri.host)) _bad();
    final host = uri.host;
    if (value != 'https://$host:3443/api/v1') _bad();
  }

  int _now() => clock().toUtc().millisecondsSinceEpoch ~/ 1000;

  static void _authorityCurrent(Map<String, dynamic> authority, int now) {
    final before = _integer(authority['not_before'], _maxTime);
    final after = _integer(authority['expires_at'], _maxTime);
    if (before >= after || now < before || now >= after) {
      _bad('authority_unavailable');
    }
  }

  Future<SimplePublicKey> _authority(Map<String, dynamic> authority) async {
    try {
      _fields(authority, [
        'authority_id',
        'kid',
        'public_jwk',
        'not_before',
        'expires_at',
      ]);
      _text(authority['authority_id']);
      _authorityCurrent(authority, _now());
      final kid = _text(authority['kid']);
      if (!_hex.hasMatch(kid)) _bad();
      final jwk = authority['public_jwk'];
      if (jwk is! Map<String, dynamic>) _bad();
      _fields(jwk, ['kty', 'crv', 'x', 'kid']);
      if (jwk['kty'] != 'OKP' || jwk['crv'] != 'Ed25519' || jwk['kid'] != kid) {
        _bad();
      }
      final bytes = _decode64(_text(jwk['x']));
      if (bytes.length != 32 || await _digest(bytes) != kid) _bad();
      return SimplePublicKey(bytes, type: KeyPairType.ed25519);
    } catch (_) {
      _bad('authority_unavailable');
    }
  }

  /// Verification is read-only: it never opens TLS, sends a credential, or saves
  /// a new pin. The later claim flow must prove the exact successor live leaf.
  Future<VerifiedCertificateRenewal> verify(
    String scanned, {
    required CertificateRenewalContext context,
  }) async {
    try {
      if (scanned.length > maxQrBytes ||
          utf8.encode(scanned).length > maxQrBytes ||
          !scanned.startsWith(prefix)) {
        _bad();
      }
      final compact = scanned.substring(prefix.length);
      final parts = compact.split('.');
      if (parts.length != 3) _bad();
      final header = decodeTrustJson(utf8.decode(_decode64(parts[0])));
      final payload = decodeTrustJson(utf8.decode(_decode64(parts[1])));
      final signature = _decode64(parts[2]);
      _fields(header, ['alg', 'typ', 'kid']);
      _fields(payload, _payloadFields);

      late Map<String, dynamic> authority;
      try {
        authority = decodeTrustJson(context.authorityJson);
      } catch (_) {
        _bad('authority_unavailable');
      }
      final key = await _authority(authority);
      if (header['alg'] != 'Ed25519' ||
          header['typ'] != 'ansvk-outreach-certificate-renewal+jws' ||
          header['kid'] != authority['kid'] ||
          signature.length != 64) {
        _bad();
      }
      final protected64 = parts[0], payload64 = parts[1];
      final signingInput = '$protected64.$payload64';
      if (!await Ed25519().verify(
        ascii.encode(signingInput),
        signature: Signature(signature, publicKey: key),
      )) {
        _bad();
      }

      _endpoint(context.apiBaseUrl);
      _integer(context.generation, _maxGeneration);
      if (!_hex.hasMatch(context.certificateSha256) ||
          context.projectId != 'ansvk_outreach' ||
          context.binding.isEmpty) {
        _bad('from_state_mismatch');
      }
      if (_integer(payload['version'], 1) != 1 ||
          payload['purpose'] != 'ansvk-outreach-certificate-renewal') {
        _bad();
      }
      final identity = {
        'dashboard_id': context.dashboardId,
        'project_id': context.projectId,
        'device_id': context.deviceId,
        'worker_id': context.workerId,
        'api_base_url': context.apiBaseUrl,
      };
      for (final entry in identity.entries) {
        if (_text(payload[entry.key]) != _text(entry.value)) {
          _bad('identity_mismatch');
        }
      }
      if (!_uuid.hasMatch(_text(payload['grant_id']))) _bad();
      if (_text(payload['from_certificate_sha256']) !=
              context.certificateSha256 ||
          _integer(payload['from_generation'], _maxGeneration) !=
              context.generation) {
        _bad('from_state_mismatch');
      }
      final nextPin = _text(payload['to_certificate_sha256']);
      final nextGeneration = _integer(payload['to_generation'], _maxGeneration);
      if (!_hex.hasMatch(nextPin) ||
          nextPin == context.certificateSha256 ||
          nextGeneration <= context.generation) {
        _bad('from_state_mismatch');
      }
      final issuedAt = _integer(payload['iat'], _maxTime);
      final expiresAt = _integer(payload['exp'], _maxTime);
      if (expiresAt - issuedAt != 300) _bad();
      final digest = await _digest(ascii.encode(compact));
      // Recheck after asynchronous crypto, not only at the start of the scan.
      final now = _now();
      _authorityCurrent(authority, now);
      if (now < issuedAt) _bad('not_yet_valid');
      if (now >= expiresAt) _bad('expired');
      return VerifiedCertificateRenewal._(
        compactJws: compact,
        grantDigest: digest,
        context: context,
        grantId: payload['grant_id'],
        toCertificateSha256: nextPin,
        toGeneration: nextGeneration,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
      );
    } on CertificateRenewalQrException {
      rethrow;
    } catch (_) {
      _bad();
    }
  }
}
