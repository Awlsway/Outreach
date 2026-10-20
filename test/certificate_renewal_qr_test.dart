import 'dart:convert';
import 'package:ansvk_outreach/sync/certificate_renewal_qr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'certificate_renewal_qr_test_support.dart';

void main() {
  late RenewalTestSigner signer;
  setUpAll(() async {
    signer = await RenewalTestSigner.create();
  });

  Future<VerifiedCertificateRenewal> verify(
    String qr, {
    CertificateRenewalContext? context,
    DateTime Function()? clock,
  }) => CertificateRenewalQrVerifier(
    clock: clock ?? () => renewalTime,
  ).verify(qr, context: context ?? renewalContext(authority: signer.authority));
  Future<void> rejects(
    String qr, {
    CertificateRenewalContext? context,
    DateTime Function()? clock,
    String? code,
  }) async => expectLater(
    verify(qr, context: context, clock: clock),
    throwsA(
      isA<CertificateRenewalQrException>().having(
        (e) => e.code,
        'safe error code',
        code ?? isNotEmpty,
      ),
    ),
  );

  test(
    'production reader accepts shared Node QR and exact compact digest',
    () async {
      final grant = await verify(
        renewalVector['qr_uri'],
        context: renewalContext(),
      );
      expect(grant.compactJws, renewalVector['jws_compact']);
      expect(grant.grantDigest, renewalVector['grant_digest']);
      expect(grant.grantId, renewalPayload['grant_id']);
      expect(
        grant.toCertificateSha256,
        renewalPayload['to_certificate_sha256'],
      );
      expect(grant.toGeneration, 2);
      expect(grant.expiresAt - grant.issuedAt, 300);
      expect(grant.toString(), isNot(contains(grant.compactJws)));
      await verify(
        renewalVector['qr_uri'],
        context: renewalContext(),
        clock: () => renewalTime.add(const Duration(seconds: 299)),
      );
    },
  );

  test('original signed JSON spacing/order is not reserialized', () async {
    final entries = renewalPayload.entries.toList().reversed;
    final fields = entries
        .map((e) {
          final key = jsonEncode(e.key), value = jsonEncode(e.value);
          return '$key : $value';
        })
        .join(', ');
    final text = '{ $fields }';
    final qr = await signer.signed(rawPayload: text);
    final grant = await verify(qr);
    expect(
      grant.grantDigest,
      await renewalDigest(
        ascii.encode(qr.substring(CertificateRenewalQrVerifier.prefix.length)),
      ),
    );
  });

  test(
    'signed newer generation may leap; no pre-known successor pin is required',
    () async {
      final grant = await verify(
        await signer.signed(
          changes: {'to_generation': 9, 'to_certificate_sha256': '3' * 64},
        ),
      );
      expect(grant.toGeneration, 9);
      expect(grant.toCertificateSha256, '3' * 64);
    },
  );

  test('existing non-ASCII paired IDs are not narrowed to ASCII', () async {
    final changes = {'worker_id': '\u1019\u103c\u1014\u103a\u1019\u102c'};
    await verify(
      await signer.signed(changes: changes),
      context: renewalContext(authority: signer.authority, changes: changes),
    );
  });

  for (final field in [
    'dashboard_id',
    'project_id',
    'device_id',
    'worker_id',
    'api_base_url',
  ]) {
    test('reject mismatched $field', () async {
      await rejects(
        await signer.signed(
          changes: {
            field: field == 'api_base_url'
                ? 'https://192.168.1.51:3443/api/v1'
                : 'other',
          },
        ),
        code: 'identity_mismatch',
      );
    });
  }
  for (final entry in <String, Object?>{
    'from_certificate_sha256': '4' * 64,
    'from_generation': 2,
    'to_certificate_sha256': renewalPayload['from_certificate_sha256'],
    'to_generation': 1,
    'grant_id': 'NOT-A-UUID',
    'version': 2,
    'purpose': 'ansvk-outreach-pairing',
  }.entries) {
    test('reject invalid signed $entry', () async {
      await rejects(await signer.signed(changes: {entry.key: entry.value}));
    });
  }
  test('reject uppercase target pin and rollback', () async {
    await rejects(
      await signer.signed(changes: {'to_certificate_sha256': 'A' * 64}),
    );
    await rejects(await signer.signed(changes: {'to_generation': 0}));
  });
  for (final endpoint in [
    'http://192.168.1.50:3443/api/v1',
    'https://office:3443/api/v1',
    'https://192.168.01.50:3443/api/v1',
    'https://192.168.1.50:3000/api/v1',
    'https://192.168.1.50:3443/api/v1/',
    'https://192.168.1.50:3443/api/v1?x=1',
    'https://name:password@192.168.1.50:3443/api/v1',
  ]) {
    test(
      'reject unsafe endpoint $endpoint even when signed and context matches',
      () async {
        final changes = {'api_base_url': endpoint};
        await rejects(
          await signer.signed(changes: changes),
          context: renewalContext(
            authority: signer.authority,
            changes: changes,
          ),
        );
      },
    );
  }

  for (final header in [
    {'alg': 'EdDSA'},
    {'alg': 'none'},
    {'typ': 'other'},
    {'kid': '0' * 64},
    {'jwk': {}},
    {'jku': 'https://example.com/key'},
    {'x5c': {}},
    {'x5u': 'https://example.com/key'},
    {'crit': true},
    {'b64': false},
  ]) {
    test('reject algorithm/key/header override $header', () async {
      await rejects(await signer.signed(headerChanges: header));
    });
  }
  test(
    'reject signed duplicate escaped keys and unknown/missing fields',
    () async {
      final validText = jsonEncode(renewalPayload);
      for (final suffix in [
        ', "extra":1}',
        ', "\\u0076ersion":1}',
        ', "worker_id":"other"}',
      ]) {
        await rejects(
          await signer.signed(
            rawPayload: validText.substring(0, validText.length - 1) + suffix,
          ),
        );
      }
      final missing = {...renewalPayload}..remove('exp');
      await rejects(await signer.signed(rawPayload: jsonEncode(missing)));
      final kid = signer.authority['kid'];
      await rejects(
        await signer.signed(
          rawHeader:
              '{"alg":"Ed25519","alg":"Ed25519","typ":"ansvk-outreach-certificate-renewal+jws","kid":"$kid"}',
        ),
      );
    },
  );

  for (final number in [
    'true',
    '"1"',
    '1.0',
    '1e0',
    '01',
    '-1',
    '0',
    '2147483648',
    'null',
  ]) {
    test('reject lexical generation $number', () async {
      final raw = jsonEncode(
        renewalPayload,
      ).replaceFirst('"from_generation":1', '"from_generation":$number');
      await rejects(await signer.signed(rawPayload: raw));
    });
  }
  test('bound time integers and exact five-minute lifetime', () async {
    for (final changes in [
      {'exp': renewalPayload['exp'] - 1},
      {'iat': true},
      {'iat': '1790668800'},
      {'iat': 0},
      {'iat': 253402300800},
      {'exp': 253402300800},
    ]) {
      await rejects(await signer.signed(changes: changes));
    }
    await rejects(
      await signer.signed(),
      code: 'not_yet_valid',
      clock: () => renewalTime.subtract(const Duration(seconds: 1)),
    );
    await rejects(
      await signer.signed(),
      code: 'expired',
      clock: () => renewalTime.add(const Duration(seconds: 300)),
    );
  });
  test('expiry is rechecked after asynchronous verification', () async {
    var clockReads = 0;
    await rejects(
      await signer.signed(),
      code: 'expired',
      clock: () {
        clockReads++;
        return clockReads == 1
            ? renewalTime
            : renewalTime.add(const Duration(seconds: 300));
      },
    );
    expect(clockReads, 2);
  });

  test(
    'reject malformed UTF-8, prefix, segments, padding and oversized QR',
    () async {
      await rejects(await signer.signed(payloadBytes: [0xff]));
      final qr = await signer.signed();
      final compact = qr.substring(CertificateRenewalQrVerifier.prefix.length);
      final parts = compact.split('.');
      final prefix = CertificateRenewalQrVerifier.prefix;
      final h = parts[0], p = parts[1], s = parts[2];
      for (final bad in [
        'ansvk-outreach://pair/v1#$compact',
        '$qr ',
        '$qr.',
        '$prefix..',
        '$prefix$h=.$p.$s',
        '$qr=',
        'x' * 2049,
      ]) {
        await rejects(bad);
      }
      final alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
      final sig = parts[2];
      final head = sig.substring(0, sig.length - 1);
      final tail = alphabet[alphabet.indexOf(sig[sig.length - 1]) ^ 1];
      final noncanonical = '$head$tail';
      await rejects('$prefix$h.$p.$noncanonical');
      final tampered = renewalDecode64(parts[2])..[0] ^= 1;
      final badSignature = renewalEncode64(tampered);
      await rejects('$prefix$h.$p.$badSignature');
      await rejects(await signer.signed(changes: {'worker_id': 'x' * 2048}));
    },
  );

  test(
    'reject absent, expired, malformed or untrusted saved authority',
    () async {
      final qr = await signer.signed();
      final key = signer.authority['public_jwk'] as Map<String, dynamic>;
      for (final authority in <Map<String, dynamic>>[
        {},
        {...signer.authority, 'expires_at': renewalPayload['iat']},
        {...signer.authority, 'not_before': renewalPayload['iat'] + 1},
        {...signer.authority, 'expires_at': true},
        {...signer.authority, 'kid': '0' * 64},
        {
          ...signer.authority,
          'public_jwk': {
            ...key,
            'x': renewalEncode64([1, 2]),
          },
        },
        {
          ...signer.authority,
          'public_jwk': {...key, 'crv': 'other'},
        },
        {
          ...signer.authority,
          'public_jwk': {...key, 'd': 'private-key-forbidden'},
        },
      ]) {
        await rejects(
          qr,
          code: 'authority_unavailable',
          context: renewalContext(authority: authority),
        );
      }
      await rejects(qr, context: renewalContext());
    },
  );
  test('authority expiry is rechecked after cryptographic awaits', () async {
    final authority = {
      ...signer.authority,
      'expires_at': renewalPayload['iat'] + 1,
    };
    var reads = 0;
    await rejects(
      await signer.signed(),
      code: 'authority_unavailable',
      context: renewalContext(authority: authority),
      clock: () => reads++ == 0
          ? renewalTime
          : renewalTime.add(const Duration(seconds: 1)),
    );
  });
}
