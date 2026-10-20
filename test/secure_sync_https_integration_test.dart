import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:ansvk_outreach/sync/dashboard_certificate_checker.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/secure_sync_transport.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:ansvk_outreach/sync/sync_run_control.dart';
import 'package:flutter_test/flutter_test.dart';
import 'jvm_certificate_test_support.dart';
import 'package:ansvk_outreach/sync/peer_certificate_verifier.dart';
import 'package:ansvk_outreach/sync/dashboard_pairing_service.dart';

void main() {
  late JvmCertificateReader metadataReader;
  late Directory temp;
  late SecurityContext context;
  late String pin;
  late DeviceCredentialStore credentials;
  setUpAll(() async {
    metadataReader = await JvmCertificateReader.create();
    metadataReader.install();
    temp = await Directory.systemTemp.createTemp('outreach-local-tls-');
    final executable = Platform.isWindows
        ? r'C:\Program Files\Git\usr\bin\openssl.exe'
        : 'openssl';
    final result = await Process.run(executable, [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      '${temp.path}/key.pem',
      '-out',
      '${temp.path}/cert.pem',
      '-days',
      '1',
      '-subj',
      '/CN=outreach-local-test',
      '-addext',
      'subjectAltName=IP:127.0.0.1',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Local test certificate generation failed');
    }
    context = SecurityContext()
      ..useCertificateChain('${temp.path}/cert.pem')
      ..usePrivateKey('${temp.path}/key.pem');
    final der = await Process.run(executable, [
      'x509',
      '-in',
      '${temp.path}/cert.pem',
      '-outform',
      'DER',
      '-out',
      '${temp.path}/cert.der',
    ]);
    if (der.exitCode != 0) {
      throw StateError('Local test certificate conversion failed');
    }
    pin = await DashboardCertificateChecker.sha256Hex(
      await File('${temp.path}/cert.der').readAsBytes(),
    );
    credentials = DeviceCredentialStore.memory();
    await credentials.write('synthetic-local-credential');
  });
  tearDownAll(() async {
    await metadataReader.close();
    await temp.delete(recursive: true);
  });

  Future<HttpServer> server() =>
      HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  SecureSyncTransport transport(
    HttpServer server, {
    String? fingerprint,
    DateTime Function()? clock,
  }) => SecureSyncTransport(
    baseUri: Uri.parse('https://127.0.0.1:${server.port}/api/v1'),
    fingerprint: fingerprint ?? pin,
    credentialStore: credentials,
    certificateVerifier: PeerCertificateVerifier(clock: clock),
  );

  test(
    'real TLS pinned POST preserves UTF-8 and parses chunked JSON; GET status',
    () async {
      final host = await server();
      addTearDown(() => host.close(force: true));
      var requests = 0;
      final body = jsonEncode({'synthetic': 'မြန်မာ'});
      host.listen((request) async {
        requests++;
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer synthetic-local-credential',
        );
        if (request.method == 'POST') {
          expect(request.uri.path, '/api/v1/sync/batches');
          expect(await utf8.decoder.bind(request).join(), body);
        } else {
          expect(request.method, 'GET');
          expect(request.uri.path, '/api/v1/sync/status');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":');
        await request.response.flush();
        request.response.write('true}');
        await request.response.close();
      });
      expect(
        (await transport(host).send(PreparedSyncBatch(body))).response['ok'],
        isTrue,
      );
      expect((await transport(host).checkStatus()).httpStatus, 200);
      expect(requests, 2);
    },
  );
  test(
    'real TLS trust route uses original POST bytes and strict raw JSON',
    () async {
      final host = await server();
      addTearDown(() => host.close(force: true));
      final bodies = <String>[];
      var duplicate = false;
      host.listen((request) async {
        expect(request.uri.path, '/api/v1/certificate-trust');
        expect(request.method, 'POST');
        expect(
          request.headers.value('authorization'),
          'Bearer synthetic-local-credential',
        );
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          duplicate
              ? '{"ok":true,"generation":1,"generation":2}'
              : '{"ok":true,"generation":1}',
        );
        await request.response.close();
      });
      const body = '{"action":"bootstrap"}';
      expect((await transport(host).postTrust(body)).response, {
        'ok': true,
        'generation': 1,
      });
      duplicate = true;
      await expectLater(transport(host).postTrust(body), throwsFormatException);
      expect(bodies, [body, body]);
    },
  );
  test(
    'real TLS renewal routes strictly parse receipts and error arrays',
    () async {
      final host = await server();
      addTearDown(() => host.close(force: true));
      var raw =
          '{"ok":false,"request_id":"synthetic","error_code":"renewal_grant_expired","message":"Expired","retryable":false,"details":[]}';
      final paths = <String>[];
      host.listen((request) async {
        paths.add(request.uri.path);
        expect(request.method, 'POST');
        expect(
          request.headers.value('authorization'),
          'Bearer synthetic-local-credential',
        );
        expect(await utf8.decoder.bind(request).join(), '{"synthetic":true}');
        request.response.headers.contentType = ContentType.json;
        request.response.write(raw);
        await request.response.close();
      });
      const body = '{"synthetic":true}';
      expect(
        (await transport(host).postRenewalClaim(body)).response['details'],
        isEmpty,
      );
      final oversized = 'x' * 32769;
      for (final invalid in [
        '{"ok":true,"generation":1,"generation":2}',
        '{"ok":true,"generation":1e0}',
        '{"ok":true,"generation":1.0}',
        '{"ok":true,"details":[,]}',
        '{"ok":true,"x":"$oversized"}',
      ]) {
        raw = invalid;
        await expectLater(
          transport(host).postRenewalClaim(body),
          throwsFormatException,
        );
        await expectLater(
          transport(host).postRenewalConfirmation(body),
          throwsFormatException,
        );
      }
      expect(paths.toSet(), {
        '/api/v1/certificate-renewals/claim',
        '/api/v1/certificate-renewals/confirm',
      });
    },
  );
  test('production Java parser rejects malformed or appended DER', () async {
    final der = await File('${temp.path}/cert.der').readAsBytes();
    for (final bytes in [
      <int>[1, 2, 3],
      [...der, 0],
    ]) {
      await expectLater(
        PeerCertificateVerifier.channel.invokeMethod('parse', {
          'der': Uint8List.fromList(bytes),
        }),
        throwsA(isA<PlatformException>()),
      );
    }
  });
  test('actual wrong certificate receives no HTTP request', () async {
    final host = await server();
    addTearDown(() => host.close(force: true));
    var requests = 0;
    host.listen((request) async {
      requests++;
      await request.response.close();
    });
    await expectLater(
      transport(host, fingerprint: '0' * 64).checkStatus(),
      throwsA(isA<SyncRequestFailure>()),
    );
    expect(requests, 0);
  });
  for (final time in [DateTime.utc(2000), DateTime.utc(2100)]) {
    test(
      'real TLS date failure at $time sends no pairing or device secrets',
      () async {
        final host = await server();
        addTearDown(() => host.close(force: true));
        var requests = 0;
        host.listen((request) async {
          requests++;
          await request.response.close();
        });
        await expectLater(
          transport(
            host,
            clock: () => time,
          ).send(PreparedSyncBatch('{"client":"synthetic"}')),
          throwsA(isA<SyncRequestFailure>()),
        );
        await expectLater(
          SecureSocketPairingTransport(
            certificateVerifier: PeerCertificateVerifier(clock: () => time),
          ).postJson(
            Uri.parse('https://127.0.0.1:${host.port}/api/v1/pairing/requests'),
            '{"pairing_code":"123456"}',
            expectedCertificateFingerprint: pin,
          ),
          throwsA(isA<PairingTransportException>()),
        );
        expect(requests, 0);
        final probe =
            await DashboardCertificateChecker(
              certificateVerifier: PeerCertificateVerifier(clock: () => time),
            ).check(
              dashboardUrl: 'https://127.0.0.1:${host.port}/api/v1',
              expectedFingerprint: pin,
            );
        expect(probe.matched, isFalse);
        expect(requests, 0);
      },
    );
  }
  for (final san in ['IP:127.0.0.2', 'DNS:127.0.0.1']) {
    test(
      'real TLS $san cannot authorize loopback IP pairing or Sync',
      () async {
        final executable = Platform.isWindows
            ? r'C:\Program Files\Git\usr\bin\openssl.exe'
            : 'openssl';
        final certPath = '${temp.path}/wrong-san.pem';
        final keyPath = '${temp.path}/wrong-san-key.pem';
        final result = await Process.run(executable, [
          'req',
          '-x509',
          '-newkey',
          'rsa:2048',
          '-nodes',
          '-keyout',
          keyPath,
          '-out',
          certPath,
          '-days',
          '1',
          '-subj',
          '/CN=127.0.0.1',
          '-addext',
          'subjectAltName=$san',
        ]);
        expect(result.exitCode, 0);
        final alternate = SecurityContext()
          ..useCertificateChain(certPath)
          ..usePrivateKey(keyPath);
        final host = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          alternate,
        );
        addTearDown(() => host.close(force: true));
        var requests = 0;
        host.listen((r) async {
          requests++;
          await r.response.close();
        });
        final socket = await SecureSocket.connect(
          '127.0.0.1',
          host.port,
          onBadCertificate: (_) => true,
        );
        final wrongPin = await PeerCertificateVerifier.sha256Hex(
          socket.peerCertificate!.der,
        );
        socket.destroy();
        await expectLater(
          transport(host, fingerprint: wrongPin).checkStatus(),
          throwsA(isA<SyncRequestFailure>()),
        );
        await expectLater(
          const SecureSocketPairingTransport().postJson(
            Uri.parse('https://127.0.0.1:${host.port}/api/v1/pairing/requests'),
            '{"pairing_code":"123456"}',
            expectedCertificateFingerprint: wrongPin,
          ),
          throwsA(isA<PairingTransportException>()),
        );
        final probe = await DashboardCertificateChecker().check(
          dashboardUrl: 'https://127.0.0.1:${host.port}/api/v1',
          expectedFingerprint: wrongPin,
        );
        expect(probe.matched, isFalse);
        expect(requests, 0);
      },
    );
  }
  test('valid real TLS pairing preserves request bytes and pin', () async {
    final host = await server();
    addTearDown(() => host.close(force: true));
    var received = '';
    host.listen((request) async {
      received = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
    });
    final response = await const SecureSocketPairingTransport().postJson(
      Uri.parse('https://127.0.0.1:${host.port}/api/v1/pairing/requests'),
      '{"pairing_code":"123456"}',
      expectedCertificateFingerprint: pin,
    );
    expect(response.statusCode, 200);
    expect(received, '{"pairing_code":"123456"}');
  });
  test(
    'refuses redirects, malformed JSON and oversized real responses',
    () async {
      for (final mode in ['redirect', 'malformed', 'oversized']) {
        final host = await server();
        try {
          host.listen((request) async {
            if (mode == 'redirect') {
              request.response.statusCode = 302;
              request.response.headers.set(
                HttpHeaders.locationHeader,
                'https://127.0.0.1:1/secret',
              );
            } else {
              request.response.write(
                mode == 'malformed' ? 'invalid-json' : 'x' * (1024 * 1024 + 1),
              );
            }
            try {
              await request.response.close();
            } catch (_) {
              /* client intentionally closes */
            }
          });
          await expectLater(
            transport(host).checkStatus(),
            throwsFormatException,
          );
        } finally {
          await host.close(force: true);
        }
      }
    },
  );
}
