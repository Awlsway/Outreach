import 'dart:convert';
import 'dart:io';
import 'package:ansvk_outreach/sync/certificate_renewal_qr.dart';
import 'package:cryptography/cryptography.dart';

Map<String, dynamic> renewalFixture(String file) =>
    jsonDecode(
          File(
            'docs/fixtures/outreach/certificate-renewal-v1/$file',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

String renewalEncode64(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
List<int> renewalDecode64(String value) =>
    base64Url.decode(base64Url.normalize(value));
Future<String> renewalDigest(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

final renewalVector = renewalFixture('valid-renewal.json');
final renewalPayload =
    jsonDecode(
          utf8.decode(
            renewalDecode64(
              (renewalVector['jws_compact'] as String).split('.')[1],
            ),
          ),
        )
        as Map<String, dynamic>;
final renewalAuthority =
    renewalFixture(
          'device-messages.json',
        )['bootstrap_response']['renewal_authority']
        as Map<String, dynamic>;
final renewalTime = DateTime.fromMillisecondsSinceEpoch(
  (renewalPayload['iat'] as int) * 1000,
  isUtc: true,
);

CertificateRenewalContext renewalContext({
  Map<String, dynamic>? authority,
  Map<String, dynamic>? changes,
  String binding = 'saved-session-and-committed-row',
}) {
  final p = {...renewalPayload, ...?changes};
  return CertificateRenewalContext(
    dashboardId: p['dashboard_id'],
    projectId: p['project_id'],
    deviceId: p['device_id'],
    workerId: p['worker_id'],
    apiBaseUrl: p['api_base_url'],
    certificateSha256: p['from_certificate_sha256'],
    generation: p['from_generation'],
    authorityJson: jsonEncode(authority ?? renewalAuthority),
    binding: binding,
  );
}

/// Disposable signing key for malformed-but-authentic test messages only.
class RenewalTestSigner {
  RenewalTestSigner._(this.keyPair, this.authority);
  final SimpleKeyPair keyPair;
  final Map<String, dynamic> authority;
  static Future<RenewalTestSigner> create() async {
    final pair = await Ed25519().newKeyPair();
    final public = await pair.extractPublicKey();
    final kid = await renewalDigest(public.bytes);
    return RenewalTestSigner._(pair, {
      ...renewalAuthority,
      'kid': kid,
      'public_jwk': {
        'kty': 'OKP',
        'crv': 'Ed25519',
        'x': renewalEncode64(public.bytes),
        'kid': kid,
      },
    });
  }

  Future<String> signed({
    Map<String, dynamic>? changes,
    Map<String, dynamic>? headerChanges,
    String? rawPayload,
    String? rawHeader,
    List<int>? payloadBytes,
  }) async {
    final header = {
      'alg': 'Ed25519',
      'typ': 'ansvk-outreach-certificate-renewal+jws',
      'kid': authority['kid'],
      ...?headerChanges,
    };
    final h = renewalEncode64(utf8.encode(rawHeader ?? jsonEncode(header)));
    final p = renewalEncode64(
      payloadBytes ??
          utf8.encode(
            rawPayload ?? jsonEncode({...renewalPayload, ...?changes}),
          ),
    );
    final input = '$h.$p';
    final signature = await Ed25519().sign(
      ascii.encode(input),
      keyPair: keyPair,
    );
    final prefix = CertificateRenewalQrVerifier.prefix;
    final encodedSignature = renewalEncode64(signature.bytes);
    return '$prefix$input.$encodedSignature';
  }
}
