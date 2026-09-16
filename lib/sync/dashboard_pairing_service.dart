import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../database/outreach_repository.dart';
import 'certificate_fingerprint_store.dart';
import 'dashboard_certificate_checker.dart';
import 'device_credential_store.dart';
import 'pairing_request_builder.dart';
import 'pairing_response.dart';

class DashboardPairingService {
  DashboardPairingService({
    required this.repository,
    required this.credentialStore,
    required this.requestBuilder,
    PairingTransport? transport,
  }) : transport = transport ?? const SecureSocketPairingTransport();

  final OutreachRepository repository;
  final DeviceCredentialStore credentialStore;
  final PairingRequestBuilder requestBuilder;
  final PairingTransport transport;

  Future<DashboardPairingAttemptResult> pair({
    required String expectedCertificateFingerprint,
  }) async {
    final config = await repository.dashboardPairingPreparation();
    final dashboardUrl = (config['dashboard_url'] as String?)?.trim() ?? '';
    final pairingCode = (config['pairing_code'] as String?)?.trim() ?? '';
    final fingerprint = CertificateFingerprintStore.normalize(
      expectedCertificateFingerprint,
    );

    final baseUri = Uri.tryParse(dashboardUrl);
    if (baseUri == null || baseUri.scheme != 'https' || baseUri.host.isEmpty) {
      return const DashboardPairingAttemptResult.invalidConfiguration(
        'Enter a valid HTTPS dashboard address first.',
      );
    }
    if (!RegExp(r'^\d{6}$').hasMatch(pairingCode)) {
      return const DashboardPairingAttemptResult.invalidConfiguration(
        'Enter the exact 6-digit pairing code from the dashboard.',
      );
    }
    if (!CertificateFingerprintStore.isValidSha256(fingerprint)) {
      return const DashboardPairingAttemptResult.invalidConfiguration(
        'Enter the full SHA-256 certificate fingerprint first.',
      );
    }

    final appIdentity = await repository.appIdentity();
    final worker = await repository.currentWorkerProfile();
    final request = requestBuilder.build(
      appIdentity: appIdentity,
      worker: worker,
      pairingCode: pairingCode,
    );

    PairingTransportResponse response;
    try {
      response = await transport.postJson(
        _pairingUri(baseUri),
        jsonEncode(request),
        expectedCertificateFingerprint: fingerprint,
      );
    } on PairingTransportException catch (error) {
      return DashboardPairingAttemptResult.transportBlocked(
        error.code,
        error.message,
      );
    } catch (_) {
      return const DashboardPairingAttemptResult.transportBlocked(
        'dashboard_unavailable',
        'Could not reach the dashboard pairing service. Check Wi-Fi, address, and dashboard status.',
      );
    }

    final decoded = _decodeJson(response.body);
    if (decoded == null) {
      return const DashboardPairingAttemptResult.invalidResponse(
        'Dashboard returned an unreadable pairing response.',
      );
    }

    final PairingResponseResult parsed;
    try {
      parsed = PairingResponseResult.parse(
        decoded,
        expectedDeviceId: appIdentity['device_id']! as String,
        expectedWorkerId: worker['worker_id']! as String,
      );
    } catch (_) {
      return const DashboardPairingAttemptResult.invalidResponse(
        'Dashboard returned a pairing response that does not match this phone.',
      );
    }

    if (parsed is PairingFailure) {
      return DashboardPairingAttemptResult.rejected(parsed);
    }

    final success = parsed as PairingSuccess;
    try {
      await credentialStore.write(success.deviceCredential);
      await repository.applyDashboardPairing(success);
    } catch (_) {
      await credentialStore.clear();
      return const DashboardPairingAttemptResult.invalidResponse(
        'The phone could not safely save the pairing result. Try again before syncing.',
      );
    }

    return DashboardPairingAttemptResult.paired(success);
  }

  static Uri _pairingUri(Uri baseUri) {
    final segments = [
      ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      'pairing',
      'requests',
    ];
    return baseUri.replace(pathSegments: segments, query: null, fragment: null);
  }

  static Map<String, Object?>? _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

abstract class PairingTransport {
  Future<PairingTransportResponse> postJson(
    Uri uri,
    String jsonBody, {
    required String expectedCertificateFingerprint,
  });
}

class PairingTransportResponse {
  const PairingTransportResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

class PairingTransportException implements Exception {
  const PairingTransportException(this.code, this.message);

  final String code;
  final String message;
}

class SecureSocketPairingTransport implements PairingTransport {
  const SecureSocketPairingTransport({this.timeout = const Duration(seconds: 30)});

  final Duration timeout;

  @override
  Future<PairingTransportResponse> postJson(
    Uri uri,
    String jsonBody, {
    required String expectedCertificateFingerprint,
  }) async {
    final expected = CertificateFingerprintStore.normalize(
      expectedCertificateFingerprint,
    );
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const PairingTransportException(
        'invalid_dashboard_address',
        'Dashboard pairing requires a valid HTTPS address.',
      );
    }
    if (!CertificateFingerprintStore.isValidSha256(expected)) {
      throw const PairingTransportException(
        'invalid_certificate_fingerprint',
        'The approved certificate fingerprint is invalid.',
      );
    }

    final socket = await SecureSocket.connect(
      uri.host,
      uri.hasPort ? uri.port : 443,
      timeout: timeout,
      onBadCertificate: (_) => true,
    );
    try {
      final certificate = socket.peerCertificate;
      if (certificate == null) {
        throw const PairingTransportException(
          'untrusted_dashboard_certificate',
          'Dashboard did not present a certificate.',
        );
      }
      final actual = await DashboardCertificateChecker.sha256Hex(
        certificate.der,
      );
      if (actual != expected) {
        throw const PairingTransportException(
          'dashboard_certificate_changed',
          'Dashboard certificate does not match the approved fingerprint.',
        );
      }

      final path = uri.hasQuery && uri.query.isNotEmpty
          ? '${uri.path}?${uri.query}'
          : uri.path;
      final bodyBytes = utf8.encode(jsonBody);
      final hostHeader = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
      socket.add(
        ascii.encode(
          'POST $path HTTP/1.1\r\n'
          'Host: $hostHeader\r\n'
          'Content-Type: application/json\r\n'
          'Accept: application/json\r\n'
          'Connection: close\r\n'
          'Content-Length: ${bodyBytes.length}\r\n'
          '\r\n',
        ),
      );
      socket.add(bodyBytes);
      await socket.flush();

      final responseBytes = await socket
          .timeout(timeout)
          .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
      return _parseHttpResponse(responseBytes);
    } finally {
      socket.destroy();
    }
  }

  static PairingTransportResponse _parseHttpResponse(List<int> responseBytes) {
    final separator = <int>[13, 10, 13, 10];
    final headerEnd = _indexOf(responseBytes, separator);
    if (headerEnd < 0) {
      throw const PairingTransportException(
        'invalid_dashboard_response',
        'Dashboard returned an invalid HTTP response.',
      );
    }
    final header = ascii.decode(responseBytes.sublist(0, headerEnd));
    final statusLine = header.split('\r\n').first;
    final match = RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})\b').firstMatch(
      statusLine,
    );
    if (match == null) {
      throw const PairingTransportException(
        'invalid_dashboard_response',
        'Dashboard returned an invalid HTTP status.',
      );
    }
    final status = int.parse(match.group(1)!);
    final body = utf8.decode(responseBytes.sublist(headerEnd + separator.length));
    return PairingTransportResponse(statusCode: status, body: body);
  }

  static int _indexOf(List<int> bytes, List<int> pattern) {
    for (var i = 0; i <= bytes.length - pattern.length; i++) {
      var matched = true;
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
  }
}

enum DashboardPairingAttemptStatus {
  paired,
  rejected,
  transportBlocked,
  invalidConfiguration,
  invalidResponse,
}

class DashboardPairingAttemptResult {
  const DashboardPairingAttemptResult._({
    required this.status,
    required this.message,
    this.success,
    this.failure,
    this.errorCode,
  });

  const DashboardPairingAttemptResult.paired(PairingSuccess success)
    : this._(
        status: DashboardPairingAttemptStatus.paired,
        message: 'Phone paired with dashboard.',
        success: success,
      );

  DashboardPairingAttemptResult.rejected(PairingFailure failure)
    : this._(
        status: DashboardPairingAttemptStatus.rejected,
        message: failure.workerMessage,
        failure: failure,
        errorCode: failure.errorCode,
      );

  const DashboardPairingAttemptResult.transportBlocked(
    String errorCode,
    String message,
  ) : this._(
        status: DashboardPairingAttemptStatus.transportBlocked,
        message: message,
        errorCode: errorCode,
      );

  const DashboardPairingAttemptResult.invalidConfiguration(String message)
    : this._(
        status: DashboardPairingAttemptStatus.invalidConfiguration,
        message: message,
      );

  const DashboardPairingAttemptResult.invalidResponse(String message)
    : this._(
        status: DashboardPairingAttemptStatus.invalidResponse,
        message: message,
      );

  final DashboardPairingAttemptStatus status;
  final String message;
  final PairingSuccess? success;
  final PairingFailure? failure;
  final String? errorCode;

  bool get paired => status == DashboardPairingAttemptStatus.paired;
}
