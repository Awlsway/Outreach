import 'dart:convert';
import 'certificate_renewal_qr.dart';
import 'certificate_renewal_state.dart';
import 'initial_certificate_trust.dart';
import 'lifecycle_gate.dart';
import 'peer_certificate_verifier.dart';
import 'secure_sync_transport.dart';
import 'sync_run_control.dart';

enum CertificateRenewalOutcome { confirmed, rejected, noPendingRenewal }

class CertificateRenewalService {
  CertificateRenewalService({required this.trust});
  final InitialCertificateTrust trust;

  Future<void> _guard(
    CertificateRenewalState state,
    SyncRunControl? control,
  ) async {
    control?.check();
    if ((await trust.renewalStateWhileHeld()).context.binding !=
        state.context.binding) {
      throw const CertificateRenewalQrException('trust_changed');
    }
    control?.check();
  }

  Future<CertificateRenewalOutcome> accept(
    VerifiedCertificateRenewal approved, {
    SyncRunControl? control,
  }) => LifecycleGate.run(() async {
    final state = await trust.renewalStateWhileHeld();
    control?.check();
    if (state.pendingClaim != null) {
      throw const CertificateRenewalQrException('renewal_pending');
    }
    if (approved.context.binding != state.context.binding ||
        state.records.any((r) => r.grant.grantId == approved.grantId)) {
      throw const CertificateRenewalQrException('trust_changed');
    }
    final grant = await CertificateRenewalQrVerifier(clock: trust.clock).verify(
      CertificateRenewalQrVerifier.prefix + approved.compactJws,
      context: state.context,
    );
    await _guard(state, control);
    final stamp = trust.clock().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (stamp < grant.issuedAt || stamp >= grant.expiresAt) {
      throw const CertificateRenewalQrException('expired');
    }
    await trust.mutateRenewalsWhileHeld(state, (tx) async {
      // This durable intent precedes TLS and survives a lost claim reply.
      await tx.insert(certificateRenewalTable, {
        'grant_id': grant.grantId,
        'state': 'claim_pending',
        'verified_at': stamp,
        'compact_jws': grant.compactJws,
      });
    }, control: control);
    return _resume(control);
  });

  Future<CertificateRenewalOutcome> resume({SyncRunControl? control}) =>
      LifecycleGate.run(() => _resume(control));

  SecureSyncTransport _transport(
    CertificateRenewalState state,
    CertificateRenewalRecord record,
    SyncRunControl? control,
  ) => SecureSyncTransport(
    baseUri: Uri.parse(record.grant.context.apiBaseUrl),
    fingerprint: record.grant.toCertificateSha256,
    credentialStore: trust.credentials,
    connector: trust.connector,
    certificateVerifier: PeerCertificateVerifier(clock: trust.clock),
    control: control,
    beforeSend: () => _guard(state, control),
  );

  Future<CertificateRenewalOutcome> _resume(SyncRunControl? control) async {
    var state = await trust.renewalStateWhileHeld();
    control?.check();
    final claim = state.pendingClaim;
    if (claim != null) {
      control?.report('Checking certificate renewal...');
      final reply = await _transport(state, claim, control).postRenewalClaim(
        jsonEncode({
          'api_version': 1,
          'protocol': 'ansvk-outreach-sync',
          'protocol_version': 1,
          'grant_id': claim.grant.grantId,
          'grant_digest': claim.grant.grantDigest,
        }),
      );
      await _guard(state, control);
      final rejected = authenticatedUnusedRejection(
        reply.response,
        reply.httpStatus,
      );
      if (rejected != null) {
        await trust.mutateRenewalsWhileHeld(state, (tx) async {
          await tx.update(
            certificateRenewalTable,
            {'state': 'rejected', 'rejection_code': rejected},
            where: 'grant_id = ?',
            whereArgs: [claim.grant.grantId],
          );
        }, control: control);
        return CertificateRenewalOutcome.rejected;
      }
      if (reply.httpStatus != 200 && reply.httpStatus != 201) {
        throw const CertificateRenewalQrException('renewal_unavailable');
      }
      final receipt = renewalClaimReply(
        reply.response,
        reply.httpStatus,
        claim.grant,
      );
      await trust.mutateRenewalsWhileHeld(state, (tx) async {
        // A matching next receipt proves LAN confirmed our committed from state.
        // Retain the earlier receipt; do not fabricate its lost confirmation reply.
        final prior = state.pendingConfirmation;
        if (prior != null) {
          await tx.update(
            certificateRenewalTable,
            {
              'state': 'confirmed_by_successor',
              'confirmed_by_grant_id': claim.grant.grantId,
            },
            where: 'grant_id = ?',
            whereArgs: [prior.grant.grantId],
          );
        }
        await tx.update(
          certificateRenewalTable,
          {
            'state': 'confirmation_pending',
            'receipt_json': jsonEncode(receipt),
          },
          where: 'grant_id = ?',
          whereArgs: [claim.grant.grantId],
        );
      }, control: control);
      state = await trust.renewalStateWhileHeld();
    }
    final confirmation = state.pendingConfirmation;
    if (confirmation == null) {
      return claim == null
          ? CertificateRenewalOutcome.noPendingRenewal
          : CertificateRenewalOutcome.confirmed;
    }
    control?.report('Confirming certificate renewal...');
    final receipt = confirmation.receipt!;
    final reply = await _transport(state, confirmation, control)
        .postRenewalConfirmation(
          jsonEncode({
            'api_version': 1,
            'protocol': 'ansvk-outreach-sync',
            'protocol_version': 1,
            'receipt_id': receipt['receipt_id'],
            'grant_id': receipt['grant_id'],
            'grant_digest': receipt['grant_digest'],
            'dashboard_id': receipt['dashboard_id'],
            'project_id': receipt['project_id'],
            'device_id': receipt['device_id'],
            'worker_id': receipt['worker_id'],
            'api_base_url': receipt['api_base_url'],
            'certificate_sha256': receipt['to_certificate_sha256'],
            'generation': receipt['to_generation'],
          }),
        );
    await _guard(state, control);
    if (reply.httpStatus != 200) {
      throw const CertificateRenewalQrException('renewal_unavailable');
    }
    final confirmed = renewalConfirmation(
      reply.response,
      reply.httpStatus,
      receipt,
    );
    await trust.mutateRenewalsWhileHeld(state, (tx) async {
      await tx.update(
        certificateRenewalTable,
        {'state': 'confirmed', 'confirmation_json': jsonEncode(confirmed)},
        where: 'grant_id = ?',
        whereArgs: [confirmation.grant.grantId],
      );
    }, control: control);
    return CertificateRenewalOutcome.confirmed;
  }
}
