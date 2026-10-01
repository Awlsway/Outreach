import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'certificate_fingerprint_store.dart';

class CertificateVerificationFailure implements Exception {
  const CertificateVerificationFailure(this.code);
  final String code;
}

class VerifiedCertificateValidity {
  const VerifiedCertificateValidity(this.notBefore, this.notAfter);
  final int notBefore, notAfter;
  void check(DateTime now) {
    final stamp = now.toUtc().millisecondsSinceEpoch;
    if (stamp < notBefore) {
      throw const CertificateVerificationFailure('not_yet_valid');
    }
    if (stamp >= notAfter) {
      throw const CertificateVerificationFailure('expired');
    }
  }
}

/// Pin trust is deliberately separate from X.509 validity and endpoint identity.
class PeerCertificateVerifier {
  PeerCertificateVerifier({DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  static const channel = MethodChannel('org.ansvk.outreach/peer_certificate');

  static bool isIpv4(String host) {
    final parts = host.split('.');
    return parts.length == 4 &&
        parts.every(
          (part) =>
              RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(part) &&
              int.parse(part) <= 255,
        );
  }

  static Future<String> sha256Hex(List<int> der) async {
    final digest = await Sha256().hash(der);
    return digest.bytes
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  Future<VerifiedCertificateValidity> verify({
    required Uri endpoint,
    required List<int> der,
    required String fingerprint,
  }) async {
    if (endpoint.scheme != 'https' || !isIpv4(endpoint.host)) {
      throw const CertificateVerificationFailure('invalid_endpoint');
    }
    if (der.isEmpty ||
        der.length > 65536 ||
        !CertificateFingerprintStore.isValidSha256(fingerprint)) {
      throw const CertificateVerificationFailure('invalid_certificate');
    }
    if (await sha256Hex(der) !=
        CertificateFingerprintStore.normalize(fingerprint)) {
      throw const CertificateVerificationFailure('fingerprint_mismatch');
    }
    Map<String, Object?>? metadata;
    try {
      metadata = await channel.invokeMapMethod<String, Object?>('parse', {
        'der': Uint8List.fromList(der),
      });
    } catch (_) {
      throw const CertificateVerificationFailure('invalid_certificate');
    }
    final before = metadata?['notBefore'];
    final after = metadata?['notAfter'];
    final ips = metadata?['ipSans'];
    if (before is! int ||
        after is! int ||
        before >= after ||
        ips is! List ||
        ips.any((value) => value is! String)) {
      throw const CertificateVerificationFailure('invalid_certificate');
    }
    final validity = VerifiedCertificateValidity(before, after);
    validity.check(clock());
    if (!ips.contains(endpoint.host)) {
      throw const CertificateVerificationFailure('endpoint_mismatch');
    }
    return validity;
  }
}
