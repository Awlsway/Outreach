import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'renewal_fixture_support.dart';

const root = 'docs/fixtures/outreach/certificate-renewal-v1';
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('$root/$name').readAsStringSync()) as Map<String, dynamic>;
const deferred = {
  'wrong-device-replay',
  'expired-unused-grant',
  'cancel-claim-race',
  'claimed-receipt-retry',
  'wrong-receipt-replay',
  'cancel-after-claim',
};

void main() {
  final valid = fixture('valid-renewal.json');
  final parts = (valid['jws_compact'] as String).split('.');
  final payload =
      jsonDecode(utf8.decode(decode64(parts[1]))) as Map<String, dynamic>;
  final jwk = valid['public_jwk'] as Map<String, dynamic>;
  final matrix = (fixture('invalid-cases.json')['cases'] as List)
      .cast<Map<String, dynamic>>();
  final covered = <String>{};
  late SimpleKeyPair disposable;
  late Map<String, dynamic> disposableJwk;
  setUpAll(() async {
    disposable = await Ed25519().newKeyPair();
    final key = await disposable.extractPublicKey();
    disposableJwk = {
      'kty': 'OKP',
      'crv': 'Ed25519',
      'x': encode64(key.bytes),
      'kid': await digest(key.bytes),
    };
  });
  Future<String> signed({
    Map<String, dynamic>? changes,
    String? rawPayload,
    String? rawHeader,
    Map<String, dynamic>? headerChanges,
  }) async {
    final h = {
      'alg': 'Ed25519',
      'typ': 'ansvk-outreach-certificate-renewal+jws',
      'kid': disposableJwk['kid'],
      ...?headerChanges,
    };
    final p = {...payload, ...?changes};
    final input =
        '${encode64(utf8.encode(rawHeader ?? jsonEncode(h)))}.${encode64(utf8.encode(rawPayload ?? jsonEncode(p)))}';
    final sig = await Ed25519().sign(ascii.encode(input), keyPair: disposable);
    return '$renewalPrefix$input.${encode64(sig.bytes)}';
  }

  Future<void> rejects(
    String qr,
    String code, {
    Map<String, dynamic>? key,
    int? now,
  }) async {
    await expectLater(
      RenewalFixtureOracle(
        key ?? disposableJwk,
        payload,
        now ?? payload['iat'] as int,
      ).verify(qr),
      throwsA(isA<FormatException>().having((e) => e.message, 'code', code)),
    );
  }

  void scenario(String id, Future<void> Function(String) body) {
    covered.add(id);
    final entry = matrix.singleWhere((e) => e['id'] == id);
    test(id, () => body(entry['expected'] as String));
  }

  test(
    'all six files copied byte-for-byte; JSON checksum coverage and manifest',
    () async {
      final jsonFiles = [
        'device-messages.json',
        'invalid-cases.json',
        'manifest.json',
        'valid-renewal.json',
      ];
      final sums = File(
        '$root/SHA256SUMS.txt',
      ).readAsLinesSync().where((l) => l.isNotEmpty).toList();
      expect(sums.length, jsonFiles.length);
      final names = <String>[];
      for (final line in sums) {
        final match = RegExp(
          r'^([0-9a-f]{64})  ([A-Za-z0-9._-]+)$',
        ).firstMatch(line)!;
        names.add(match[2]!);
        expect(
          await digest(File('$root/${match[2]}').readAsBytesSync()),
          match[1],
        );
      }
      expect(names..sort(), jsonFiles);
      final manifest = fixture('manifest.json');
      expect(manifest, {
        'fixture_version': 1,
        'contract': 'ansvk-outreach-certificate-renewal',
        'contract_version': 1,
        'api_version': 1,
        'sync_schema_version': 6,
        'synthetic_only': true,
        'files': [
          'device-messages.json',
          'invalid-cases.json',
          'valid-renewal.json',
        ],
      });
      // Source directory comparison is preparation evidence, not a test dependency.
      expect(
        Directory(root).listSync().map((e) => e.uri.pathSegments.last).toSet(),
        {...jsonFiles, 'README.md', 'SHA256SUMS.txt'},
      );
    },
  );
  test(
    'published Node signature, original bytes, JWK kid and compact digest',
    () async {
      expect(valid['qr_uri'], '$renewalPrefix${valid['jws_compact']}');
      expect(
        await digest(ascii.encode(valid['jws_compact'])),
        valid['grant_digest'],
      );
      expect(
        await RenewalFixtureOracle(
          jwk,
          payload,
          payload['iat'],
        ).verify(valid['qr_uri']),
        payload,
      );
      expect(payload.keys.toList(), payloadFields);
      expect(
        (jsonDecode(utf8.decode(decode64(parts[0]))) as Map).keys.toList(),
        ['alg', 'typ', 'kid'],
      );
      expect(
        await RenewalFixtureOracle(
          jwk,
          payload,
          payload['exp'] - 1,
        ).verify(valid['qr_uri']),
        payload,
      );
    },
  );
  test(
    'disposable Dart to Node and Node to Dart signatures round-trip',
    () async {
      final qr = await signed();
      final compact = qr.substring(renewalPrefix.length);
      final script = r'''
const c=require('node:crypto');
const input=JSON.parse(process.argv[1]);
const p=input.jws.split('.');
const key=c.createPublicKey({key:input.jwk,format:'jwk'});
const verified=c.verify(null,Buffer.from(p[0]+'.'+p[1],'ascii'),key,Buffer.from(p[2],'base64url'));
const pair=c.generateKeyPairSync('ed25519');
const jwk=pair.publicKey.export({format:'jwk'});
jwk.kid=c.createHash('sha256').update(Buffer.from(jwk.x,'base64url')).digest('hex');
const header=Buffer.from(JSON.stringify({alg:'Ed25519',typ:'ansvk-outreach-certificate-renewal+jws',kid:jwk.kid})).toString('base64url');
const bytes=header+'.'+p[1];
const signature=c.sign(null,Buffer.from(bytes,'ascii'),pair.privateKey).toString('base64url');
process.stdout.write(JSON.stringify({verified,jwk,jws:bytes+'.'+signature}));
''';
      final result = await Process.run('node', [
        '-e',
        script,
        jsonEncode({'jws': compact, 'jwk': disposableJwk}),
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final response =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(response['verified'], true);
      expect(
        await RenewalFixtureOracle(
          response['jwk'],
          payload,
          payload['iat'],
        ).verify('$renewalPrefix${response['jws']}'),
        payload,
      );
    },
  );
  test('all device-message field orders, types and complete binding shapes', () {
    final m = fixture('device-messages.json');
    final shapes = <String, String>{
      'bootstrap_request':
          'api_version protocol protocol_version action project_id dashboard_id device_id worker_id api_base_url certificate_sha256',
      'bootstrap_response':
          'ok request_id action bootstrap_id dashboard_id project_id device_id worker_id api_base_url certificate_sha256 generation renewal_authority',
      'bootstrap_confirmation_request':
          'api_version protocol protocol_version action bootstrap_id authority_kid certificate_sha256 generation',
      'bootstrap_confirmation_response':
          'ok request_id action bootstrap_id authority_kid certificate_sha256 generation state',
      'claim_request':
          'api_version protocol protocol_version grant_id grant_digest',
      'claim_response': 'ok request_id receipt',
      'confirmation_request':
          'api_version protocol protocol_version receipt_id grant_id grant_digest dashboard_id project_id device_id worker_id api_base_url certificate_sha256 generation',
      'confirmation_response':
          'ok request_id receipt_id grant_digest device_id certificate_sha256 generation state',
    };
    expect(m.keys.toList(), [
      'fixture_version',
      'synthetic_only',
      ...shapes.keys,
    ]);
    expect(m['fixture_version'], 1);
    expect(m['synthetic_only'], true);
    for (final entry in shapes.entries) {
      final body = m[entry.key] as Map<String, dynamic>;
      expect(body.keys.toList(), entry.value.split(' '), reason: entry.key);
      for (final field in body.keys) {
        final value = body[field];
        if (['api_version', 'protocol_version', 'generation'].contains(field)) {
          expect(value, isA<int>());
          expect(value, greaterThan(0));
        } else if (field == 'ok') {
          expect(value, true);
        } else if (['receipt', 'renewal_authority'].contains(field)) {
          expect(value, isA<Map>());
        } else {
          expect(value, isA<String>());
          expect(value, isNotEmpty);
        }
        if (field == 'protocol') expect(value, 'ansvk-outreach-sync');
        if (['api_version', 'protocol_version'].contains(field)) {
          expect(value, 1);
        }
      }
    }
    final b = m['bootstrap_response'] as Map;
    final a = b['renewal_authority'] as Map;
    expect(a.keys.toList(), [
      'authority_id',
      'kid',
      'public_jwk',
      'not_before',
      'expires_at',
    ]);
    expect(a['public_jwk'], jwk);
    expect(a['kid'], jwk['kid']);
    expect((a['public_jwk'] as Map).keys.toList(), ['kty', 'crv', 'x', 'kid']);
    expect(a['not_before'], isA<int>());
    expect(a['expires_at'], greaterThan(a['not_before']));
    final r = m['claim_response']['receipt'] as Map;
    expect(
      r.keys.toList(),
      'receipt_id grant_id grant_digest dashboard_id project_id device_id worker_id api_base_url from_certificate_sha256 from_generation to_certificate_sha256 to_generation claimed_at'
          .split(' '),
    );
    expect(
      r['claimed_at'],
      inInclusiveRange(payload['iat'], payload['exp'] - 1),
    );
    for (final f in payloadFields.where((f) => r.containsKey(f))) {
      expect(r[f], payload[f]);
    }
    expect(r['grant_digest'], valid['grant_digest']);
    for (final f in [
      'project_id',
      'dashboard_id',
      'device_id',
      'worker_id',
      'api_base_url',
    ]) {
      expect(m['bootstrap_request'][f], payload[f]);
      expect(b[f], payload[f]);
      expect(m['confirmation_request'][f], payload[f]);
    }
    expect(b['certificate_sha256'], payload['from_certificate_sha256']);
    expect(b['generation'], payload['from_generation']);
    for (final label in [
      'bootstrap_confirmation_request',
      'bootstrap_confirmation_response',
    ]) {
      for (final f in ['bootstrap_id', 'certificate_sha256', 'generation']) {
        expect(m[label][f], b[f]);
      }
      expect(m[label]['authority_kid'], a['kid']);
      expect(m[label]['action'], 'confirm_bootstrap');
    }
    expect(m['bootstrap_request']['action'], 'bootstrap');
    expect(b['action'], 'bootstrap');
    expect(m['bootstrap_confirmation_response']['state'], 'confirmed');
    expect(m['claim_request']['grant_id'], r['grant_id']);
    expect(m['claim_request']['grant_digest'], r['grant_digest']);
    for (final label in ['confirmation_request', 'confirmation_response']) {
      for (final f in ['receipt_id', 'grant_digest', 'device_id']) {
        expect(m[label][f], r[f]);
      }
      expect(m[label]['certificate_sha256'], r['to_certificate_sha256']);
      expect(m[label]['generation'], r['to_generation']);
    }
    expect(m['confirmation_request']['grant_id'], r['grant_id']);
    expect(m['confirmation_response']['state'], 'confirmed');
    expect(
      jsonEncode(m),
      isNot(
        matches(
          RegExp(
            'credential|authorization|password|private_key|client_data',
            caseSensitive: false,
          ),
        ),
      ),
    );
  });

  scenario(
    'wrong-purpose-prefix',
    (code) async => rejects(
      (valid['qr_uri'] as String).replaceFirst(
        renewalPrefix,
        'ansvk-outreach://pair/v1#',
      ),
      code,
      key: jwk,
    ),
  );
  scenario('malformed-compact-segments', (code) async {
    for (final p in [parts.take(2).join('.'), '${valid['jws_compact']}.A']) {
      await rejects('$renewalPrefix$p', code, key: jwk);
    }
  });
  scenario(
    'base64url-padding',
    (code) async => rejects(
      '$renewalPrefix${parts[0]}=.${parts[1]}.${parts[2]}',
      code,
      key: jwk,
    ),
  );
  scenario('base64url-alias', (code) async {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final last = alphabet.indexOf(parts[2].substring(parts[2].length - 1));
    final alias =
        parts[2].substring(0, parts[2].length - 1) + alphabet[last + 1];
    await rejects(
      '$renewalPrefix${parts[0]}.${parts[1]}.$alias',
      code,
      key: jwk,
    );
  });
  for (final id in [
    'tampered-protected-header',
    'tampered-payload',
    'tampered-signature',
  ]) {
    scenario(id, (code) async {
      final p = [...parts];
      final index = id == 'tampered-protected-header'
          ? 0
          : id == 'tampered-payload'
          ? 1
          : 2;
      final bytes = decode64(p[index]).toList();
      if (index == 2) {
        bytes[0] ^= 1;
      } else {
        bytes.add(32);
      } // whitespace preserves JSON but changes signed bytes
      p[index] = encode64(bytes);
      await rejects('$renewalPrefix${p.join('.')}', code, key: jwk);
    });
  }
  scenario(
    'duplicate-header-key',
    (code) async => rejects(
      await signed(
        rawHeader:
            '{"alg":"Ed25519","\\u0061lg":"Ed25519","typ":"ansvk-outreach-certificate-renewal+jws","kid":"${disposableJwk['kid']}"}',
      ),
      code,
    ),
  );
  scenario(
    'unknown-header-key',
    (code) async => rejects(
      await signed(headerChanges: {'jku': 'https://example.invalid'}),
      code,
    ),
  );
  scenario('unsupported-algorithm', (code) async {
    for (final alg in ['EdDSA', 'none']) {
      await rejects(await signed(headerChanges: {'alg': alg}), code);
    }
  });
  scenario(
    'wrong-key-or-kid',
    (code) async =>
        rejects(await signed(headerChanges: {'kid': '0' * 64}), code),
  );
  scenario(
    'duplicate-payload-key',
    (code) async => rejects(
      await signed(
        rawPayload: jsonEncode(
          payload,
        ).replaceFirst('{', '{"device_id":"duplicate",'),
      ),
      code,
    ),
  );
  scenario(
    'unknown-payload-key',
    (code) async => rejects(await signed(changes: {'extra': 1}), code),
  );
  scenario(
    'wrong-purpose',
    (code) async => rejects(await signed(changes: {'purpose': 'pair'}), code),
  );
  scenario('wrong-project-dashboard-device-worker', (code) async {
    for (final f in ['project_id', 'dashboard_id', 'device_id', 'worker_id']) {
      await rejects(await signed(changes: {f: 'other'}), code);
    }
  });
  scenario('unsafe-or-changed-endpoint', (code) async {
    for (final url in [
      'http://192.168.1.50:3443/api/v1',
      'https://office:3443/api/v1',
      'https://192.168.1.51:3443/api/v1',
      'https://192.168.1.50/api/v1',
      'https://192.168.1.50:3444/api/v1',
      'https://192.168.1.50:3443/api/v2',
      'https://u@192.168.1.50:3443/api/v1',
      'https://192.168.1.50:3443/api/v1?q=1',
      'https://192.168.1.50:3443/api/v1#x',
    ]) {
      await rejects(await signed(changes: {'api_base_url': url}), code);
    }
  });
  scenario('wrong-from-state', (code) async {
    for (final changes in [
      {'from_generation': 2},
      {'from_certificate_sha256': '3' * 64},
    ]) {
      await rejects(await signed(changes: changes), code);
    }
  });
  scenario('wrong-to-state', (code) async {
    for (final changes in [
      {'to_generation': 1},
      {'to_certificate_sha256': '3' * 64},
    ]) {
      await rejects(await signed(changes: changes), code);
    }
  });
  scenario('noninteger-json-token', (code) async {
    for (final f in [
      'version',
      'from_generation',
      'to_generation',
      'iat',
      'exp',
    ]) {
      for (final token in ['true', '"1"', '1.0', '1e0']) {
        await rejects(
          await signed(
            rawPayload: jsonEncode(
              payload,
            ).replaceFirst('"$f":${payload[f]}', '"$f":$token'),
          ),
          code,
        );
      }
    }
  });
  scenario('integer-overflow', (code) async {
    for (final changes in [
      {'from_generation': 2147483648},
      {'to_generation': -1},
      {'iat': 253402300800},
      {'exp': 253402300800},
    ]) {
      await rejects(await signed(changes: changes), code);
    }
  });
  scenario('invalid-time-window', (code) async {
    final qr = await signed();
    await rejects(qr, code, now: payload['iat'] - 1);
    await rejects(qr, code, now: payload['exp']);
    await rejects(await signed(changes: {'exp': payload['iat'] + 301}), code);
  });
  scenario('invalid-key-shape', (code) async {
    final qr = await signed();
    for (final key in [
      {...disposableJwk, 'crv': 'Ed448'},
      {...disposableJwk, 'x': encode64(List.filled(31, 0))},
      {...disposableJwk, 'extra': 1},
      {...disposableJwk, 'kid': '0' * 64},
    ]) {
      await rejects(qr, code, key: key);
    }
  });
  scenario(
    'oversized-input',
    (code) async => rejects('$renewalPrefix${'A' * 2049}', code),
  );
  test(
    'named matrix coverage explicitly separates contract and server-state work',
    () {
      expect(matrix.map((e) => e['id']).toSet(), {...covered, ...deferred});
      expect(matrix.length, covered.length + deferred.length);
      expect(covered.length, 23);
      expect(deferred.length, 6);
    },
  );
  test('missing fields, malformed UTF8 and invalid signature length', () async {
    final p = {...payload}..remove('worker_id');
    await rejects(await signed(rawPayload: jsonEncode(p)), 'invalid_payload');
    await rejects(
      '$renewalPrefix${parts[0]}.${encode64([0xff])}.${parts[2]}',
      'invalid_encoding',
      key: jwk,
    );
    await rejects(
      '$renewalPrefix${parts[0]}.${parts[1]}.${encode64(List.filled(63, 0))}',
      'invalid_signature',
      key: jwk,
    );
  });
}
