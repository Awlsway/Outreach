// Test-only contract oracle. This is NOT an APK renewal parser or trust store.
import 'dart:convert';
import 'package:cryptography/cryptography.dart';

const renewalPrefix = 'ansvk-outreach://renew-certificate/v1#';
const payloadFields = [
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
String encode64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
Future<String> digest(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Never reject(String code) => throw FormatException(code);
List<int> decode64(String text) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text)) reject('invalid_encoding');
  List<int> bytes;
  try {
    bytes = base64Url.decode(base64Url.normalize(text));
  } catch (_) {
    reject('invalid_encoding');
  }
  if (encode64(bytes) != text) reject('invalid_encoding');
  return bytes;
}

// Header/payload are flat objects. Scan original member tokens, including
// escaped keys, so jsonDecode cannot silently erase duplicates or exponent form.
Map<String, dynamic> flatObject(String text, String failure) {
  final token = RegExp(
    r'\s*"((?:[^"\\]|\\.)*)"\s*:\s*("(?:[^"\\]|\\.)*"|true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\s*',
  );
  final result = <String, dynamic>{};
  var cursor = 0;
  final source = text.trim();
  if (!source.startsWith('{') || !source.endsWith('}')) reject(failure);
  cursor++;
  while (cursor < source.length - 1) {
    final match = token.matchAsPrefix(source, cursor);
    if (match == null) reject(failure);
    final key = jsonDecode('"${match[1]}"') as String;
    if (result.containsKey(key)) reject(failure);
    final value = match[2]!;
    if (!value.startsWith('"') &&
        !['true', 'false', 'null'].contains(value) &&
        !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(value)) {
      reject(failure);
    }
    result[key] = jsonDecode(value);
    cursor = match.end;
    if (cursor == source.length - 1) break;
    if (source[cursor] != ',') reject(failure);
    cursor++;
    if (cursor == source.length - 1) reject(failure);
  }
  if (cursor != source.length - 1) reject(failure);
  return result;
}

void fields(Map<String, dynamic> object, List<String> names, String failure) {
  if (object.length != names.length ||
      names.any((n) => !object.containsKey(n))) {
    reject(failure);
  }
}

class RenewalFixtureOracle {
  RenewalFixtureOracle(this.jwk, this.context, this.now);
  final Map<String, dynamic> jwk, context;
  final int now;
  Future<Map<String, dynamic>> verify(String qr) async {
    if (utf8.encode(qr).length > 2048) reject('input_too_large');
    if (!qr.startsWith(renewalPrefix)) reject('reject before decoding');
    final parts = qr.substring(renewalPrefix.length).split('.');
    if (parts.length != 3 || parts.any((s) => s.isEmpty)) {
      reject('invalid_encoding');
    }
    final bytes = parts.map(decode64).toList();
    String headerText, payloadText;
    try {
      headerText = utf8.decode(bytes[0]);
      payloadText = utf8.decode(bytes[1]);
    } catch (_) {
      reject('invalid_encoding');
    }
    final header = flatObject(headerText, 'invalid_header');
    fields(header, ['alg', 'typ', 'kid'], 'invalid_header');
    if (header['alg'] != 'Ed25519') reject('unsupported_algorithm');
    if (header['typ'] != 'ansvk-outreach-certificate-renewal+jws') {
      reject('invalid_header');
    }
    fields(jwk, ['kty', 'crv', 'x', 'kid'], 'untrusted_authority');
    List<int> key;
    try {
      key = decode64(jwk['x'] as String);
    } catch (_) {
      reject('untrusted_authority');
    }
    if (jwk['kty'] != 'OKP' ||
        jwk['crv'] != 'Ed25519' ||
        key.length != 32 ||
        await digest(key) != jwk['kid'] ||
        header['kid'] != jwk['kid']) {
      reject('untrusted_authority');
    }
    if (bytes[2].length != 64 ||
        !await Ed25519().verify(
          ascii.encode('${parts[0]}.${parts[1]}'),
          signature: Signature(
            bytes[2],
            publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
          ),
        )) {
      reject('invalid_signature');
    }
    final payload = flatObject(payloadText, 'invalid_payload');
    fields(payload, payloadFields, 'invalid_payload');
    for (final field in [
      'version',
      'from_generation',
      'to_generation',
      'iat',
      'exp',
    ]) {
      final v = payload[field];
      final max = ['iat', 'exp'].contains(field) ? 253402300799 : 2147483647;
      if (v is! int || v <= 0 || v > max) reject('invalid_payload');
    }
    if (payload['version'] != 1) reject('invalid_payload');
    for (final field in payloadFields.where(
      (f) => ![
        'version',
        'from_generation',
        'to_generation',
        'iat',
        'exp',
      ].contains(f),
    )) {
      if (payload[field] is! String || (payload[field] as String).isEmpty) {
        reject('invalid_payload');
      }
    }
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(payload['grant_id'])) {
      reject('invalid_payload');
    }
    for (final f in ['from_certificate_sha256', 'to_certificate_sha256']) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(payload[f])) {
        reject('invalid_payload');
      }
    }
    if (payload['purpose'] != 'ansvk-outreach-certificate-renewal') {
      reject('wrong_purpose');
    }
    for (final f in [
      'project_id',
      'dashboard_id',
      'device_id',
      'worker_id',
      'api_base_url',
    ]) {
      if (payload[f] != context[f]) reject('context_mismatch');
    }
    for (final f in ['from_certificate_sha256', 'from_generation']) {
      if (payload[f] != context[f]) reject('from_state_mismatch');
    }
    if (payload['to_certificate_sha256'] != context['to_certificate_sha256'] ||
        payload['to_generation'] != context['to_generation'] ||
        payload['to_generation'] <= payload['from_generation'] ||
        payload['to_certificate_sha256'] ==
            payload['from_certificate_sha256']) {
      reject('successor_mismatch');
    }
    if (payload['exp'] != payload['iat'] + 300 ||
        now < payload['iat'] ||
        now >= payload['exp']) {
      reject('expired_or_invalid_time');
    }
    return payload;
  }
}
