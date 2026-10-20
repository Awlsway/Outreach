import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite_common/sqlite_api.dart';
import '../database/outreach_repository.dart';
import 'certificate_fingerprint_store.dart';
import 'certificate_renewal_qr.dart';
import 'certificate_renewal_state.dart';
import 'device_credential_store.dart';
import 'lifecycle_gate.dart';
import 'peer_certificate_verifier.dart';
import 'secure_sync_transport.dart';
import 'sync_run_control.dart';

class InitialCertificateTrust {
  InitialCertificateTrust({
    required this.repository,
    required this.legacyPins,
    required this.credentials,
    this.connector,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final OutreachRepository repository;
  final CertificateFingerprintStore legacyPins;
  final DeviceCredentialStore credentials;
  final SyncHttpsConnector? connector;
  final DateTime Function() clock;
  static const table = 'initial_certificate_trust';

  Future<Map<String, dynamic>> _context() async {
    final token = repository.sessionToken;
    final worker = repository.currentWorkerId();
    if (worker == null) throw StateError('Worker session unavailable');
    final config = await repository.dashboardPairingPreparation();
    final identity = await repository.appIdentity();
    final credential = await credentials.read();
    if (config['status'] != 'Paired' ||
        credential == null ||
        credential.isEmpty ||
        repository.sessionToken != token) {
      throw StateError('Pairing unavailable');
    }
    return {
      'project_id': identity['project_id'],
      'dashboard_id': config['dashboard_id'],
      'device_id': identity['device_id'],
      'worker_id': worker,
      'api_base_url': config['dashboard_url'],
      'paired_at': config['paired_at'],
      'credential_sha256': await _hash(utf8.encode(credential)),
    };
  }

  Future<void> _guard(
    Map<String, dynamic> snapshot,
    String token,
    SyncRunControl? control,
  ) async {
    control?.check();
    final context = await _context();
    if (repository.sessionToken != token ||
        context.keys.any((key) => context[key] != snapshot[key])) {
      throw StateError('Trust context changed');
    }
    control?.check();
  }

  Future<Row?> _row() async {
    final rows = await repository.database.connection.query(table);
    if (rows.length > 1) throw StateError('Conflicting trust state');
    return rows.isEmpty ? null : rows.single;
  }

  static Map<String, dynamic> _object(Object? text) {
    if (text is! String) throw const FormatException('Invalid saved trust');
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid saved trust');
    }
    return value;
  }

  static void _fields(Map<String, dynamic> value, List<String> keys) {
    if (value.length != keys.length ||
        keys.any((key) => !value.containsKey(key))) {
      throw const FormatException('Invalid trust fields');
    }
  }

  static String _string(Object? value) {
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw const FormatException('Invalid trust string');
    }
    return value;
  }

  static int _integer(Object? value, int max) {
    if (value is! int || value <= 0 || value > max) {
      throw const FormatException('Invalid trust integer');
    }
    return value;
  }

  static Future<String> _hash(List<int> bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  static String _pin(Object? value) {
    final pin = _string(value);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pin)) {
      throw const FormatException('Invalid trust pin');
    }
    return pin;
  }

  static void _endpoint(Object? value) {
    final text = _string(value);
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !PeerCertificateVerifier.isIpv4(uri.host) ||
        text != 'https://${uri.host}:3443/api/v1') {
      throw const FormatException('Invalid trust endpoint');
    }
  }

  Future<void> _validateBootstrap(
    Map<String, dynamic> response,
    Map<String, dynamic> snapshot,
  ) async {
    _fields(response, [
      'ok',
      'request_id',
      'action',
      'bootstrap_id',
      'dashboard_id',
      'project_id',
      'device_id',
      'worker_id',
      'api_base_url',
      'certificate_sha256',
      'generation',
      'renewal_authority',
    ]);
    if (response['ok'] != true || response['action'] != 'bootstrap') {
      throw const FormatException('Trust rejected');
    }
    _string(response['request_id']);
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(_string(response['bootstrap_id']))) {
      throw const FormatException('Invalid bootstrap ID');
    }
    for (final key in [
      'dashboard_id',
      'project_id',
      'device_id',
      'worker_id',
      'api_base_url',
      'certificate_sha256',
    ]) {
      _string(response[key]);
      if (response[key] != snapshot[key]) {
        throw const FormatException('Trust identity mismatch');
      }
    }
    _endpoint(response['api_base_url']);
    _pin(response['certificate_sha256']);
    _integer(response['generation'], 2147483647);
    final a = response['renewal_authority'];
    if (a is! Map<String, dynamic>) {
      throw const FormatException('Invalid authority');
    }
    _fields(a, [
      'authority_id',
      'kid',
      'public_jwk',
      'not_before',
      'expires_at',
    ]);
    _string(a['authority_id']);
    final kid = _pin(a['kid']);
    final before = _integer(a['not_before'], 253402300799),
        after = _integer(a['expires_at'], 253402300799);
    final now = clock().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (before >= after || now < before || now >= after) {
      throw const FormatException('Authority not current');
    }
    final jwk = a['public_jwk'];
    if (jwk is! Map<String, dynamic>) {
      throw const FormatException('Invalid JWK');
    }
    _fields(jwk, ['kty', 'crv', 'x', 'kid']);
    final x = _string(jwk['x']);
    if (jwk['kty'] != 'OKP' ||
        jwk['crv'] != 'Ed25519' ||
        jwk['kid'] != kid ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(x)) {
      throw const FormatException('Invalid JWK');
    }
    final bytes = base64Url.decode(base64Url.normalize(x));
    if (bytes.length != 32 ||
        base64Url.encode(bytes).replaceAll('=', '') != x ||
        await _hash(bytes) != kid) {
      throw const FormatException('Invalid authority digest');
    }
  }

  Future<void> _write(
    Row next,
    Row? previous,
    Map<String, dynamic> snapshot,
    String token,
    SyncRunControl? control,
  ) async {
    await _guard(snapshot, token, control);
    await repository.database.connection.transaction((tx) async {
      final current = await tx.query(table);
      if (jsonEncode(current.isEmpty ? null : current.single) !=
          jsonEncode(previous)) {
        throw StateError('Trust changed');
      }
      final config = (await tx.query('dashboard_connection')).single;
      final identity = (await tx.query('app_identity')).single;
      if (config['status'] != 'Paired' ||
          config['dashboard_id'] != snapshot['dashboard_id'] ||
          config['dashboard_url'] != snapshot['api_base_url'] ||
          config['paired_at'] != snapshot['paired_at'] ||
          identity['project_id'] != snapshot['project_id'] ||
          identity['device_id'] != snapshot['device_id']) {
        throw StateError('Pairing changed');
      }
      if (previous == null) {
        await tx.insert(table, next);
      } else {
        await tx.update(table, next, where: 'singleton_id = 1');
      }
      // Roll back the transaction if lock/session changed during its last await.
      if (repository.sessionToken != token) {
        throw StateError('Worker session changed');
      }
      control?.check();
    });
  }

  Future<void> ensure({SyncRunControl? control}) =>
      LifecycleGate.run(() => ensureWhileHeld(control: control));

  /// Called by a caller already holding LifecycleGate; never starts sync itself.
  Future<void> ensureWhileHeld({SyncRunControl? control}) async {
    final token = repository.sessionToken;
    var row = await _row();
    Map<String, dynamic> snapshot;
    if (row == null) {
      snapshot = await _context();
      final pin = await legacyPins.read();
      if (pin == null || !CertificateFingerprintStore.isValidSha256(pin)) {
        throw StateError('Approved pairing pin missing');
      }
      snapshot['certificate_sha256'] = CertificateFingerprintStore.normalize(
        pin,
      ).toLowerCase();
      _endpoint(snapshot['api_base_url']);
      final next = <String, Object?>{
        'singleton_id': 1,
        'state': 'bootstrap_pending',
        'snapshot_json': jsonEncode(snapshot),
        'bootstrap_json': null,
      };
      await _write(next, null, snapshot, token, control);
      row = next;
    } else {
      snapshot = _object(row['snapshot_json']);
    }
    await _guard(snapshot, token, control);
    if ((await repository.database.connection.query(
      certificateRenewalTable,
    )).isNotEmpty) {
      final renewal = await renewalStateWhileHeld();
      control?.check();
      if (!renewal.canSync) {
        throw const CertificateRenewalQrException('renewal_pending');
      }
      return;
    }
    final transport = SecureSyncTransport(
      baseUri: Uri.parse(_string(snapshot['api_base_url'])),
      fingerprint: _pin(snapshot['certificate_sha256']),
      credentialStore: credentials,
      connector: connector,
      control: control,
      beforeSend: () async {
        await _guard(snapshot, token, control);
        if (jsonEncode(await _row()) != jsonEncode(row) ||
            repository.sessionToken != token) {
          throw StateError('Trust changed during TLS setup');
        }
      },
    );
    Map<String, dynamic> proof;
    if (row['state'] == 'bootstrap_pending') {
      final request = <String, Object?>{
        'api_version': 1,
        'protocol': 'ansvk-outreach-sync',
        'protocol_version': 1,
        'action': 'bootstrap',
        for (final key in [
          'project_id',
          'dashboard_id',
          'device_id',
          'worker_id',
          'api_base_url',
          'certificate_sha256',
        ])
          key: snapshot[key],
      };
      final reply = await transport.postTrust(jsonEncode(request));
      if (reply.httpStatus != 200) {
        throw StateError('Trust bootstrap unavailable');
      }
      proof = Map<String, dynamic>.from(reply.response);
      await _validateBootstrap(proof, snapshot);
      final next = <String, Object?>{
        ...row,
        'state': 'confirmation_pending',
        'bootstrap_json': jsonEncode(proof),
      };
      await _write(next, row, snapshot, token, control);
      row = next;
      // Authority and pin are now authoritative. Failure deleting legacy bytes
      // cannot create a second trust source or undo this committed record.
      try {
        await legacyPins.clear();
      } catch (_) {
        /* ignored, never read again */
      }
    } else {
      proof = _object(row['bootstrap_json']);
      await _validateBootstrap(proof, snapshot);
    }
    if (row['state'] == 'confirmed') {
      await _guard(snapshot, token, control);
      return;
    }
    if (row['state'] != 'confirmation_pending') {
      throw StateError('Invalid trust state');
    }
    final request = {
      'api_version': 1,
      'protocol': 'ansvk-outreach-sync',
      'protocol_version': 1,
      'action': 'confirm_bootstrap',
      'bootstrap_id': proof['bootstrap_id'],
      'authority_kid': proof['renewal_authority']['kid'],
      'certificate_sha256': proof['certificate_sha256'],
      'generation': proof['generation'],
    };
    final reply = await transport.postTrust(jsonEncode(request));
    if (reply.httpStatus != 200) {
      throw StateError('Trust confirmation unavailable');
    }
    final response = Map<String, dynamic>.from(reply.response);
    _fields(response, [
      'ok',
      'request_id',
      'action',
      'bootstrap_id',
      'authority_kid',
      'certificate_sha256',
      'generation',
      'state',
    ]);
    if (response['ok'] != true || response['state'] != 'confirmed') {
      throw const FormatException('Invalid trust confirmation');
    }
    _string(response['request_id']);
    for (final key in [
      'action',
      'bootstrap_id',
      'authority_kid',
      'certificate_sha256',
      'generation',
    ]) {
      if (response[key] != request[key]) {
        throw const FormatException('Confirmation mismatch');
      }
    }
    await _write({...row, 'state': 'confirmed'}, row, snapshot, token, control);
  }

  Future<String> recordStamp() async => jsonEncode([
    await _row(),
    await repository.database.connection.query(
      certificateRenewalTable,
      orderBy: 'sequence',
    ),
  ]);

  /// Read only authenticated, committed trust. A lost confirmation reply can
  /// leave this state pending; the later claim receipt must prove LAN accepted it.
  Future<CertificateRenewalContext> renewalContext() =>
      renewalState().then((state) => state.context);

  Future<CertificateRenewalState> renewalState() =>
      LifecycleGate.run(renewalStateWhileHeld);

  /// For callers already holding LifecycleGate. No network or mutation.
  Future<CertificateRenewalState> renewalStateWhileHeld() async {
    final token = repository.sessionToken;
    final row = await _row();
    if (row == null ||
        !['confirmed', 'confirmation_pending'].contains(row['state'])) {
      throw const CertificateRenewalQrException('authority_unavailable');
    }
    final snapshot = _object(row['snapshot_json']);
    final proof = _object(row['bootstrap_json']);
    await _validateBootstrap(proof, snapshot);
    await _guard(snapshot, token, null);
    final rows = await repository.database.connection.query(
      certificateRenewalTable,
      orderBy: 'sequence',
    );
    final binding = jsonEncode([token, row, rows]);
    final base = CertificateRenewalContext(
      dashboardId: _string(proof['dashboard_id']),
      projectId: _string(proof['project_id']),
      deviceId: _string(proof['device_id']),
      workerId: _string(proof['worker_id']),
      apiBaseUrl: _string(proof['api_base_url']),
      certificateSha256: _pin(proof['certificate_sha256']),
      generation: _integer(proof['generation'], 2147483647),
      authorityJson: jsonEncode(proof['renewal_authority']),
      binding: binding,
    );
    final state = await CertificateRenewalState.restore(
      base,
      rows,
      row['state'] == 'confirmed',
    );
    await _guard(snapshot, token, null);
    if (binding !=
            jsonEncode([
              repository.sessionToken,
              await _row(),
              await repository.database.connection.query(
                certificateRenewalTable,
                orderBy: 'sequence',
              ),
            ]) ||
        repository.sessionToken != token) {
      throw const CertificateRenewalQrException('trust_changed');
    }
    final authority = proof['renewal_authority'] as Map<String, dynamic>;
    final now = clock().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (now < authority['not_before'] || now >= authority['expires_at']) {
      throw const CertificateRenewalQrException('authority_unavailable');
    }
    return state;
  }

  /// Compare and mutate inside one transaction, including a final session and
  /// credential guard. Never invoke repository DB helpers inside this callback.
  Future<void> mutateRenewalsWhileHeld(
    CertificateRenewalState expected,
    Future<void> Function(Transaction tx) mutation, {
    SyncRunControl? control,
  }) async {
    final token = repository.sessionToken;
    control?.check();
    if ((await renewalStateWhileHeld()).context.binding !=
        expected.context.binding) {
      throw const CertificateRenewalQrException('trust_changed');
    }
    await repository.database.connection.transaction((tx) async {
      final initial = (await tx.query(table)).single;
      final rows = await tx.query(certificateRenewalTable, orderBy: 'sequence');
      if (jsonEncode([token, initial, rows]) != expected.context.binding) {
        throw const CertificateRenewalQrException('trust_changed');
      }
      final snapshot = _object(initial['snapshot_json']);
      final config = (await tx.query('dashboard_connection')).single;
      final identity = (await tx.query('app_identity')).single;
      if (config['status'] != 'Paired' ||
          config['dashboard_id'] != snapshot['dashboard_id'] ||
          config['dashboard_url'] != snapshot['api_base_url'] ||
          config['paired_at'] != snapshot['paired_at'] ||
          identity['project_id'] != snapshot['project_id'] ||
          identity['device_id'] != snapshot['device_id']) {
        throw const CertificateRenewalQrException('trust_changed');
      }
      control?.check();
      await mutation(tx);
      final credential = await credentials.read();
      if (credential == null ||
          await _hash(utf8.encode(credential)) !=
              snapshot['credential_sha256'] ||
          repository.currentWorkerId() != snapshot['worker_id'] ||
          repository.sessionToken != token) {
        throw const CertificateRenewalQrException('trust_changed');
      }
      control?.check();
    });
  }

  Future<VerifiedCertificateRenewal> reviewRenewalQr(String scanned) async {
    final context = await renewalContext();
    final renewal = await CertificateRenewalQrVerifier(
      clock: clock,
    ).verify(scanned, context: context);
    if ((await renewalContext()).binding != context.binding) {
      throw const CertificateRenewalQrException('trust_changed');
    }
    return renewal;
  }

  Future<String> confirmedPin() async {
    final state = await renewalStateWhileHeld();
    if (!state.canSync) {
      throw StateError('Certificate trust confirmation required');
    }
    return CertificateFingerprintStore.normalize(
      state.context.certificateSha256,
    );
  }
}
