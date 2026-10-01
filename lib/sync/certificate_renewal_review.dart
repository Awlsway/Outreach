import 'dart:async';
import 'package:flutter/material.dart';
import 'certificate_renewal_qr.dart';

/// Embed inside the worker session/lock shell. A root route must not bypass it.
/// Approval only hands off a revalidated grant; this screen never changes trust.
class CertificateRenewalReview extends StatefulWidget {
  const CertificateRenewalReview({
    super.key,
    required this.renewal,
    required this.loadContext,
    required this.onApproved,
    required this.onCancel,
    this.clock,
  });

  final VerifiedCertificateRenewal renewal;
  final Future<CertificateRenewalContext> Function() loadContext;
  final ValueChanged<VerifiedCertificateRenewal> onApproved;
  final VoidCallback onCancel;
  final DateTime Function()? clock;

  @override
  State<CertificateRenewalReview> createState() =>
      _CertificateRenewalReviewState();
}

class _CertificateRenewalReviewState extends State<CertificateRenewalReview> {
  late final Timer _timer;
  bool _busy = false, _approved = false;
  String? _error;
  DateTime _now() => (widget.clock ?? DateTime.now)().toUtc();
  int get _remaining =>
      widget.renewal.expiresAt - (_now().millisecondsSinceEpoch ~/ 1000);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _approve() async {
    if (_busy || _approved || _remaining <= 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final current = await widget.loadContext();
      if (current.binding != widget.renewal.context.binding) {
        throw const CertificateRenewalQrException('trust_changed');
      }
      final verified = await CertificateRenewalQrVerifier(clock: widget.clock)
          .verify(
            CertificateRenewalQrVerifier.prefix + widget.renewal.compactJws,
            context: current,
          );
      final latest = await widget.loadContext();
      if (latest.binding != current.binding) {
        throw const CertificateRenewalQrException('trust_changed');
      }
      if (_remaining <= 0) {
        throw const CertificateRenewalQrException('expired');
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _approved = true;
      });
      widget.onApproved(verified);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is CertificateRenewalQrException
            ? error.message
            : const CertificateRenewalQrException('trust_changed').message;
      });
    }
  }

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final renewal = widget.renewal;
    final remaining = _remaining;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Certificate renewal', maxLines: 2),
        leading: BackButton(
          onPressed: _busy || _approved ? null : widget.onCancel,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.verified_user_outlined, size: 32),
            const SizedBox(height: 12),
            Text(
              'Review office approval',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            _field('Office', Uri.parse(renewal.context.apiBaseUrl).host),
            _field('Worker', renewal.context.workerId),
            _field('Phone', renewal.context.deviceId),
            _field('Dashboard', renewal.context.dashboardId),
            _field(
              'QR validity',
              remaining > 0
                  ? 'Expires in $remaining seconds'
                  : 'Expired. Ask for a new renewal QR.',
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Certificate details'),
              children: [
                _field(
                  'Current fingerprint',
                  renewal.context.certificateSha256,
                ),
                _field('Approved fingerprint', renewal.toCertificateSha256),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy || _approved ? null : widget.onCancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _busy || _approved || remaining <= 0
                      ? null
                      : _approve,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text(
                    'Continue renewal',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
