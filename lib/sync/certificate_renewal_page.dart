import 'dart:async';
import 'package:flutter/material.dart';
import '../auth/session_controller.dart';
import 'certificate_renewal_qr.dart';
import 'certificate_renewal_review.dart';
import 'certificate_renewal_service.dart';
import 'certificate_renewal_state.dart';
import 'initial_certificate_trust.dart';
import 'qr_pairing_scanner_page.dart';
import 'sync_run_control.dart';

typedef RenewalScannerBuilder =
    Widget Function(ValueChanged<String> onScanned, VoidCallback onCancel);

/// An internal workspace page, never a route above the worker lock shell.
class CertificateRenewalPage extends StatefulWidget {
  const CertificateRenewalPage({
    super.key,
    required this.session,
    required this.trust,
    required this.onBack,
    required this.onBusyChanged,
    this.scannerBuilder,
  });
  final SessionController session;
  final InitialCertificateTrust trust;
  final VoidCallback onBack;
  final ValueChanged<bool> onBusyChanged;
  final RenewalScannerBuilder? scannerBuilder;

  @override
  State<CertificateRenewalPage> createState() => _CertificateRenewalPageState();
}

class _CertificateRenewalPageState extends State<CertificateRenewalPage> {
  CertificateRenewalState? _state;
  VerifiedCertificateRenewal? _draft;
  SyncRunControl? _control;
  bool _loading = true, _scanning = false;
  String? _message, _error;
  int _operation = 0;
  late int _revision = widget.session.revision;
  late final String? _workerId = widget.session.currentWorkerId;
  late bool _sessionAvailable = _workerId != null;
  CertificateRenewalService get _service =>
      CertificateRenewalService(trust: widget.trust);
  bool get _active =>
      widget.session.currentWorkerId != null &&
      widget.session.currentWorkerId == _workerId &&
      widget.session.revision == _revision;
  bool _current(int operation) => mounted && _active && operation == _operation;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _operation++;
    _control?.stop();
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    final available =
        widget.session.currentWorkerId != null &&
        widget.session.currentWorkerId == _workerId;
    if (_revision == widget.session.revision &&
        available == _sessionAvailable) {
      return;
    }
    _revision = widget.session.revision;
    _sessionAvailable = available;
    _operation++;
    _control?.stop();
    setState(() {
      _draft = null;
      _scanning = false;
      _state = null;
      _message = null;
      _error = null;
      _loading = false;
    });
    if (_active && _control == null) unawaited(_load());
  }

  String _safeError(Object error) => error is CertificateRenewalQrException
      ? error.message
      : 'Certificate renewal is not available. Records remain saved. Retry or contact the data assistant.';

  Future<void> _load({bool keepResult = false}) async {
    if (!mounted || !_active || _control != null) return;
    final operation = ++_operation;
    setState(() {
      _loading = true;
      _state = null;
      if (!keepResult) _error = null;
    });
    try {
      final state = await widget.trust.renewalState();
      if (!_current(operation)) return;
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (error) {
      if (!_current(operation)) return;
      setState(() {
        _loading = false;
        _error = _safeError(error);
      });
    }
  }

  void _scan() {
    if (!mounted ||
        !_active ||
        _loading ||
        _control != null ||
        _state == null ||
        _state!.pendingClaim != null) {
      return;
    }
    widget.session.activity();
    setState(() {
      _scanning = true;
      _message = null;
      _error = null;
    });
  }

  void _cancelDraft() {
    if (!mounted || !_active || _control != null) return;
    widget.session.activity();
    _operation++;
    setState(() {
      _draft = null;
      _scanning = false;
    });
    unawaited(_load());
  }

  Future<void> _scanned(String qr) async {
    if (!mounted || !_active || !_scanning || _control != null) return;
    widget.session.activity();
    final operation = ++_operation;
    setState(() {
      _scanning = false;
      _loading = true;
      _error = null;
    });
    try {
      final grant = await widget.trust.reviewRenewalQr(qr);
      if (!_current(operation)) return;
      setState(() {
        _draft = grant;
        _loading = false;
      });
    } catch (error) {
      if (!_current(operation)) return;
      setState(() {
        _loading = false;
        _error = _safeError(error);
      });
    }
  }

  Future<void> _run({VerifiedCertificateRenewal? approved}) async {
    if (!mounted || !_active || _loading || _control != null) return;
    widget.session.activity();
    final operation = ++_operation;
    final control = SyncRunControl(
      onProgress: (message) {
        if (_current(operation)) setState(() => _message = message);
      },
    );
    setState(() {
      _control = control;
      _draft = null;
      _scanning = false;
      _error = null;
      _message = 'Checking certificate renewal...';
    });
    widget.onBusyChanged(true);
    try {
      final outcome = approved == null
          ? await _service.resume(control: control)
          : await _service.accept(approved, control: control);
      if (!_current(operation)) return;
      setState(() {
        _message = switch (outcome) {
          CertificateRenewalOutcome.confirmed =>
            'Certificate renewal complete.',
          CertificateRenewalOutcome.rejected =>
            'This unused approval expired or was cancelled. Ask the data assistant for a new QR.',
          CertificateRenewalOutcome.noPendingRenewal =>
            'No certificate renewal is pending.',
        };
      });
    } catch (error) {
      if (!_current(operation)) return;
      setState(() {
        _message = null;
        _error = error is SyncStopped || control.stopped
            ? 'Renewal stopped. Saved progress and records were kept.'
            : _safeError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _control = null);
        widget.onBusyChanged(false);
        // A new authenticated session must reread durable state, never reuse
        // an old scanned approval or act on a late result.
        if (_active) {
          await _load(keepResult: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();
    if (_scanning) {
      final builder = widget.scannerBuilder;
      void scanned(String value) => unawaited(_scanned(value));
      return builder != null
          ? builder(scanned, _cancelDraft)
          : QrPairingScannerPage(
              title: 'Scan renewal QR',
              onScanned: scanned,
              onCancel: _cancelDraft,
            );
    }
    if (_draft != null) {
      return CertificateRenewalReview(
        renewal: _draft!,
        clock: widget.trust.clock,
        loadContext: widget.trust.renewalContext,
        onApproved: (grant) => unawaited(_run(approved: grant)),
        onCancel: _cancelDraft,
      );
    }
    final state = _state;
    final pending =
        state?.pendingClaim != null || state?.pendingConfirmation != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Renewal'),
        leading: BackButton(onPressed: _control == null ? widget.onBack : null),
        actions: [
          IconButton(
            tooltip: 'Lock app',
            onPressed: widget.session.lock,
            icon: const Icon(Icons.lock_outline),
          ),
          IconButton(
            key: const ValueKey('refresh-renewal'),
            tooltip: 'Refresh',
            onPressed: _loading || _control != null ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (state != null) ...[
                    Text(
                      state.pendingClaim != null
                          ? 'Waiting for renewal receipt'
                          : state.pendingConfirmation != null ||
                                !state.bootstrapConfirmed && !state.canSync
                          ? 'Waiting for dashboard confirmation'
                          : 'No pending renewal',
                      key: const ValueKey('renewal-state'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(Uri.parse(state.context.apiBaseUrl).host),
                    const SizedBox(height: 8),
                    const Text('Records and pending uploads remain saved.'),
                    const SizedBox(height: 20),
                  ],
                  if (_message != null) ...[
                    Text(_message!, key: const ValueKey('renewal-message')),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null) ...[
                    Text(
                      _error!,
                      key: const ValueKey('renewal-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_control != null) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('stop-renewal'),
                      onPressed: () {
                        widget.session.activity();
                        _control?.stop();
                      },
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Stop'),
                    ),
                  ] else ...[
                    if (pending) ...[
                      FilledButton.icon(
                        key: const ValueKey('resume-renewal'),
                        onPressed: () => unawaited(_run()),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Resume renewal'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (state != null && state.pendingClaim == null)
                      OutlinedButton.icon(
                        key: const ValueKey('scan-renewal-qr'),
                        onPressed: _scan,
                        icon: const Icon(Icons.qr_code_scanner_outlined),
                        label: const Text('Scan renewal QR'),
                      ),
                    if (state == null)
                      FilledButton.icon(
                        key: const ValueKey('retry-renewal-status'),
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}
