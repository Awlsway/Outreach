import 'dart:convert';
import 'dart:io';
import 'package:ansvk_outreach/sync/dashboard_certificate_checker.dart';
import 'package:ansvk_outreach/sync/device_credential_store.dart';
import 'package:ansvk_outreach/sync/secure_sync_transport.dart';
import 'package:ansvk_outreach/sync/sync_batch_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late SecurityContext context;
  late String pin;
  late DeviceCredentialStore credentials;
  setUpAll(() async {
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
    await temp.delete(recursive: true);
  });

  Future<HttpServer> server() =>
      HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  SecureSyncTransport transport(HttpServer server, {String? fingerprint}) =>
      SecureSyncTransport(
        baseUri: Uri.parse('https://127.0.0.1:${server.port}/api/v1'),
        fingerprint: fingerprint ?? pin,
        credentialStore: credentials,
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
      throwsStateError,
    );
    expect(requests, 0);
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
