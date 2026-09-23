import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'certificate_fingerprint_store.dart';
import 'dashboard_certificate_checker.dart';
import 'device_credential_store.dart';
import 'manual_sync_runner.dart';
import 'sync_batch_builder.dart';

abstract interface class SyncHttpsConnection {
  List<int> get certificateDer;
  Future<SyncBatchReply> request(
    Uri uri,
    String method,
    String credential,
    String? body,
  );
  void close();
}

typedef SyncHttpsConnector = Future<SyncHttpsConnection> Function(Uri uri);

/// Not wired into worker UI. Checks the peer before sending any HTTP secrets.
class SecureSyncTransport implements SyncBatchTransport {
  SecureSyncTransport({
    required this.baseUri,
    required this.fingerprint,
    required this.credentialStore,
    SyncHttpsConnector? connector,
    this.timeout = const Duration(seconds: 30),
    this.beforeSend,
  }) : _connector = connector ?? _connect;
  final Uri baseUri;
  final String fingerprint;
  final DeviceCredentialStore credentialStore;
  final SyncHttpsConnector _connector;
  final Duration timeout;
  final Future<void> Function()? beforeSend;

  @override
  Future<SyncBatchReply> send(PreparedSyncBatch batch) {
    if (batch.byteLength > SyncBatchBuilder.maxBytes) {
      throw const FormatException('Batch exceeds size limit');
    }
    return _request('batches', batch.jsonBody);
  }

  /// This reply conveys status only; it never marks operations acknowledged.
  Future<SyncBatchReply> checkStatus() => _request('status', null);

  Future<SyncBatchReply> _request(String endpoint, String? body) async {
    final expected = CertificateFingerprintStore.normalize(fingerprint);
    if (baseUri.scheme != 'https' ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        baseUri.path != '/api/v1' ||
        !CertificateFingerprintStore.isValidSha256(expected)) {
      throw const FormatException('Invalid secure sync configuration');
    }
    final credential = await credentialStore.read();
    if (credential == null || !RegExp(r'^[\x21-\x7E]+$').hasMatch(credential)) {
      throw StateError('Device credential unavailable');
    }
    final uri = baseUri.replace(path: '/api/v1/sync/$endpoint');
    SyncHttpsConnection? connection;
    var expired = false;
    try {
      return await (() async {
        final peer = await _connector(uri);
        connection = peer;
        if (expired) {
          peer.close();
          throw TimeoutException('Sync timed out');
        }
        final actual = await DashboardCertificateChecker.sha256Hex(
          peer.certificateDer,
        );
        if (expired || actual != expected) {
          throw StateError('Dashboard certificate mismatch');
        }
        await beforeSend?.call();
        if (expired) throw TimeoutException('Sync timed out');
        return await peer.request(
          uri,
          body == null ? 'GET' : 'POST',
          credential,
          body,
        );
      })().timeout(timeout);
    } finally {
      expired = true;
      connection?.close();
    }
  }

  static Future<SyncHttpsConnection> _connect(Uri uri) async =>
      _SocketConnection(
        await SecureSocket.connect(
          uri.host,
          uri.port,
          timeout: const Duration(seconds: 30),
          onBadCertificate: (_) => true,
        ),
      );
}

class _SocketConnection implements SyncHttpsConnection {
  _SocketConnection(this.socket);
  final SecureSocket socket;
  HttpClient? client;
  @override
  List<int> get certificateDer => socket.peerCertificate?.der ?? <int>[];
  @override
  Future<SyncBatchReply> request(
    Uri uri,
    String method,
    String credential,
    String? body,
  ) async {
    final http = HttpClient();
    client = http;
    http.findProxy = (_) => 'DIRECT';
    var used = false;
    http.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (used) {
        throw StateError('Unexpected additional connection');
      }
      used = true;
      return ConnectionTask.fromSocket(
        Future<Socket>.value(socket),
        socket.destroy,
      );
    };
    final request = await http.openUrl(method, uri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $credential');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final reply = await request.close();
    if (reply.isRedirect) {
      throw const FormatException('Dashboard redirect refused');
    }
    final bytes = <int>[];
    await for (final chunk in reply) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const FormatException('Dashboard response exceeds limit');
      }
      bytes.addAll(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid dashboard JSON');
    }
    return SyncBatchReply(reply.statusCode, decoded);
  }

  @override
  void close() {
    client?.close(force: true);
    socket.destroy();
  }
}
