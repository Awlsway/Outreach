import 'package:flutter/material.dart';
import '../auth/session_controller.dart';
import '../database/outreach_repository.dart' as data;
import '../encounters/encounter_form.dart';
import '../sync/certificate_fingerprint_store.dart';
import '../sync/dashboard_certificate_checker.dart';
import 'location_service.dart';
import 'new_hotspot_form.dart';

enum _Page {
  home,
  list,
  create,
  detail,
  encounter,
  summary,
  records,
  recordDetail,
  editRecord,
  sync,
  dashboardAddress,
  pendingChanges,
}

/// Internal pages stay inside the app's session/lock boundary. They do not push
/// unguarded routes above the lock screen.
class HotspotWorkspace extends StatefulWidget {
  const HotspotWorkspace({
    super.key,
    required this.session,
    required this.location,
    this.certificateFingerprintStore,
    this.dashboardCertificateChecker,
  });
  final SessionController session;
  final HotspotLocationService location;
  final CertificateFingerprintStore? certificateFingerprintStore;
  final DashboardCertificateChecker? dashboardCertificateChecker;
  @override
  State<HotspotWorkspace> createState() => _HotspotWorkspaceState();
}

class _HotspotWorkspaceState extends State<HotspotWorkspace> {
  late final _repository = data.OutreachRepository(
    widget.session.auth.database,
    currentWorkerId: () => widget.session.currentWorkerId,
  );
  final _search = TextEditingController();
  final _dashboardUrl = TextEditingController();
  final _pairingCode = TextEditingController();
  final _certificateFingerprint = TextEditingController();
  late final CertificateFingerprintStore _certificateFingerprintStore =
      widget.certificateFingerprintStore ?? CertificateFingerprintStore();
  late final DashboardCertificateChecker _dashboardCertificateChecker =
      widget.dashboardCertificateChecker ?? DashboardCertificateChecker();
  _Page _page = _Page.home;
  List<data.Row> _rows = [];
  data.Row? _selected;
  data.Row? _selectedRecord;
  List<data.Row> _records = [];
  data.Row? _summary;
  data.Row? _syncStatus;
  List<data.Row> _pendingChanges = [];
  bool _loading = false;
  bool _recordsLoading = false;
  bool _summaryLoading = false;
  bool _syncLoading = false;
  bool _pendingChangesLoading = false;
  bool _savingDashboardAddress = false;
  bool _checkingDashboardCertificate = false;
  bool _deletingRecord = false;
  bool _saved = false;
  String? _error;
  String? _recordsError;
  String? _summaryError;
  String? _syncError;
  String? _pendingChangesError;
  String? _dashboardAddressError;
  String? _dashboardPairingError;
  String? _certificateFingerprintError;
  DashboardCertificateCheckResult? _certificateCheckResult;
  int _query = 0;

  @override
  void dispose() {
    _query++;
    _search.dispose();
    _dashboardUrl.dispose();
    _pairingCode.dispose();
    _certificateFingerprint.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final query = ++_query;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _repository.hotspots(search: _search.text);
      if (!mounted || query != _query) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || query != _query) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load hotspots. Please retry.';
      });
    }
  }

  void _list({bool saved = false}) {
    if (saved) _search.clear();
    setState(() {
      _page = _Page.list;
      _saved = saved;
    });
    _load();
  }

  void _back() {
    if (_page == _Page.list ||
        _page == _Page.summary ||
        _page == _Page.records ||
        _page == _Page.sync) {
      setState(() => _page = _Page.home);
    } else if (_page == _Page.dashboardAddress) {
      _openSyncStatus();
    } else if (_page == _Page.pendingChanges) {
      _openSyncStatus();
    } else if (_page == _Page.recordDetail) {
      _openRecords();
    } else {
      _list();
    }
  }

  Future<void> _openRecords() async {
    widget.session.activity();
    setState(() {
      _page = _Page.records;
      _recordsLoading = true;
      _recordsError = null;
    });
    try {
      final records = await _repository.todayEncounters();
      if (!mounted || _page != _Page.records) return;
      setState(() {
        _records = records;
        _recordsLoading = false;
      });
    } catch (_) {
      if (!mounted || _page != _Page.records) return;
      setState(() {
        _recordsLoading = false;
        _recordsError = 'Unable to load today records. Please retry.';
      });
    }
  }

  Future<void> _openSummary() async {
    widget.session.activity();
    setState(() {
      _page = _Page.summary;
      _summaryLoading = true;
      _summaryError = null;
    });
    try {
      final summary = await _repository.todaySummary();
      if (!mounted || _page != _Page.summary) return;
      setState(() {
        _summary = summary;
        _summaryLoading = false;
      });
    } catch (_) {
      if (!mounted || _page != _Page.summary) return;
      setState(() {
        _summaryLoading = false;
        _summaryError = 'Unable to load today summary. Please retry.';
      });
    }
  }

  Future<void> _openSyncStatus() async {
    widget.session.activity();
    setState(() {
      _page = _Page.sync;
      _syncLoading = true;
      _syncError = null;
    });
    try {
      final status = await _repository.syncStatus();
      final fingerprint = await _certificateFingerprintStore.read();
      if (!mounted || _page != _Page.sync) return;
      setState(() {
        _syncStatus = {
          ...status,
          'certificate_fingerprint_hint': fingerprint == null
              ? null
              : CertificateFingerprintStore.hint(fingerprint),
        };
        _syncLoading = false;
      });
    } catch (_) {
      if (!mounted || _page != _Page.sync) return;
      setState(() {
        _syncLoading = false;
        _syncError = 'Unable to load sync status. Please retry.';
      });
    }
  }

  Future<void> _openDashboardAddress() async {
    widget.session.activity();
    _dashboardUrl.text = (_syncStatus?['dashboard_url'] as String?) ?? '';
    _pairingCode.clear();
    _certificateFingerprint.text =
        await _certificateFingerprintStore.read() ?? '';
    if (!mounted) return;
    setState(() {
      _page = _Page.dashboardAddress;
      _dashboardAddressError = null;
      _dashboardPairingError = null;
      _certificateFingerprintError = null;
      _certificateCheckResult = null;
    });
  }

  Future<void> _openPendingChanges() async {
    widget.session.activity();
    setState(() {
      _page = _Page.pendingChanges;
      _pendingChangesLoading = true;
      _pendingChangesError = null;
    });
    try {
      final rows = await _repository.pendingOperations();
      if (!mounted || _page != _Page.pendingChanges) return;
      setState(() {
        _pendingChanges = rows;
        _pendingChangesLoading = false;
      });
    } catch (_) {
      if (!mounted || _page != _Page.pendingChanges) return;
      setState(() {
        _pendingChangesLoading = false;
        _pendingChangesError = 'Unable to load pending changes.';
      });
    }
  }

  Future<void> _saveDashboardPairing() async {
    if (_savingDashboardAddress || _checkingDashboardCertificate) return;
    widget.session.activity();
    final value = _dashboardUrl.text.trim();
    final code = _pairingCode.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !value.endsWith('/api/v1')) {
      setState(() {
        _dashboardAddressError =
            'Enter the HTTPS device API address ending with /api/v1.';
        _dashboardPairingError = null;
        _certificateFingerprintError = null;
      });
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _dashboardAddressError = null;
        _dashboardPairingError =
            'Enter the exact 6-digit pairing code from the dashboard.';
        _certificateFingerprintError = null;
      });
      return;
    }
    final fingerprint = _certificateFingerprint.text;
    if (!CertificateFingerprintStore.isValidSha256(fingerprint)) {
      setState(() {
        _dashboardAddressError = null;
        _dashboardPairingError = null;
        _certificateFingerprintError =
            'Enter the full SHA-256 certificate fingerprint.';
      });
      return;
    }
    setState(() {
      _savingDashboardAddress = true;
      _dashboardAddressError = null;
      _dashboardPairingError = null;
      _certificateFingerprintError = null;
    });
    try {
      final normalized = CertificateFingerprintStore.normalize(fingerprint);
      await _certificateFingerprintStore.write(normalized);
      await _repository.saveDashboardPairing(value, code);
      if (!mounted) return;
      _savingDashboardAddress = false;
      _openSyncStatus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingDashboardAddress = false;
        _dashboardAddressError = 'Could not save pairing information.';
      });
    }
  }

  Future<void> _clearDashboardAddress() async {
    if (_savingDashboardAddress || _checkingDashboardCertificate) return;
    widget.session.activity();
    setState(() {
      _savingDashboardAddress = true;
      _dashboardAddressError = null;
      _dashboardPairingError = null;
      _certificateFingerprintError = null;
      _certificateCheckResult = null;
    });
    try {
      await _repository.clearDashboardAddress();
      await _certificateFingerprintStore.clear();
      if (!mounted) return;
      _dashboardUrl.clear();
      _pairingCode.clear();
      _certificateFingerprint.clear();
      _savingDashboardAddress = false;
      _openSyncStatus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingDashboardAddress = false;
        _dashboardAddressError = 'Could not clear dashboard pairing.';
      });
    }
  }

  Future<void> _checkDashboardCertificate() async {
    if (_savingDashboardAddress || _checkingDashboardCertificate) return;
    widget.session.activity();
    setState(() {
      _checkingDashboardCertificate = true;
      _dashboardAddressError = null;
      _certificateFingerprintError = null;
      _certificateCheckResult = null;
    });
    final result = await _dashboardCertificateChecker.check(
      dashboardUrl: _dashboardUrl.text,
      expectedFingerprint: _certificateFingerprint.text,
    );
    if (!mounted) return;
    setState(() {
      _checkingDashboardCertificate = false;
      _certificateCheckResult = result;
      if (result.status == DashboardCertificateCheckStatus.invalidAddress) {
        _dashboardAddressError = result.message;
      } else if (result.status ==
          DashboardCertificateCheckStatus.invalidFingerprint) {
        _certificateFingerprintError = result.message;
      }
    });
  }

  Future<void> _deleteSelectedRecord() async {
    final record = _selectedRecord;
    if (_deletingRecord || record == null) return;
    widget.session.activity();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text(
          'Delete ${record['client_code']} from today records? This can be synced later as a deleted record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-record'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingRecord = true);
    try {
      await _repository.deleteEncounter(
        record['encounter_id'] as String,
        expectedRevision: (record['revision'] as num).toInt(),
      );
      if (!mounted) return;
      _selectedRecord = null;
      _deletingRecord = false;
      _openRecords();
    } catch (_) {
      if (!mounted) return;
      setState(() => _deletingRecord = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete record. Please retry.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        _page == _Page.home || widget.session.locked || widget.session.hidden,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: switch (_page) {
      _Page.home => _home(context),
      _Page.list => _listPage(context),
      _Page.create => NewHotspotForm(
        repository: _repository,
        session: widget.session,
        location: widget.location,
        onSaved: () => _list(saved: true),
        onBack: _back,
      ),
      _Page.detail => _detail(context),
      _Page.encounter => EncounterForm(
        repository: _repository,
        session: widget.session,
        hotspot: _selected!,
        onBack: () => setState(() => _page = _Page.detail),
      ),
      _Page.summary => _summaryPage(context),
      _Page.records => _recordsPage(context),
      _Page.recordDetail => _recordDetailPage(context),
      _Page.editRecord => EncounterForm(
        repository: _repository,
        session: widget.session,
        hotspot: {
          'hotspot_id': _selectedRecord!['hotspot_id'],
          'name': _selectedRecord!['hotspot_name'],
        },
        initialRecord: _selectedRecord,
        onBack: () => setState(() => _page = _Page.recordDetail),
        onSaved: _openRecords,
      ),
      _Page.sync => _syncPage(context),
      _Page.dashboardAddress => _dashboardAddressPage(context),
      _Page.pendingChanges => _pendingChangesPage(context),
    },
  );

  Widget _footer() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Signed in as ${widget.session.worker!.username}',
        textAlign: TextAlign.center,
      ),
    ),
  );

  Widget _home(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ANSVK Outreach'),
      actions: [
        IconButton(
          tooltip: 'Lock app',
          onPressed: widget.session.lock,
          icon: const Icon(Icons.lock_outline),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: widget.session.logout,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place_outlined, size: 56),
            const SizedBox(height: 20),
            const Text('You are signed in', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 12),
            const Text(
              'Choose a hotspot or add a new one.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('open-hotspots'),
              onPressed: _list,
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('Hotspots'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('open-daily-summary'),
              onPressed: _openSummary,
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('Daily summary'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('open-today-records'),
              onPressed: _openRecords,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text("Today's records"),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('open-sync-status'),
              onPressed: _openSyncStatus,
              icon: const Icon(Icons.sync_outlined),
              label: const Text('Sync status'),
            ),
          ],
        ),
      ),
    ),
    bottomNavigationBar: _footer(),
  );

  Widget _listPage(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Your hotspots'),
      leading: BackButton(onPressed: _back),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const ValueKey('search-hotspots'),
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Search hotspot name',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) {
                widget.session.activity();
                _load();
              },
            ),
          ),
          if (_saved)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Hotspot saved.'),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _search.text.trim().isEmpty
                            ? 'No hotspots yet. Create your first hotspot.'
                            : 'No matching hotspots.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      final peers = (row['peers'] as List).join(', ');
                      return ListTile(
                        key: ValueKey('hotspot-${row['hotspot_id']}'),
                        title: Text(row['name'] as String),
                        subtitle: Text(
                          peers.isEmpty ? 'No assigned peers' : peers,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => setState(() {
                          _selected = row;
                          _page = _Page.detail;
                        }),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('new-hotspot'),
                onPressed: () => setState(() => _page = _Page.create),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('New hotspot'),
              ),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: _footer(),
  );

  Widget _detail(BuildContext context) {
    final row = _selected!;
    final peers = (row['peers'] as List).cast<String>();
    final available = row['location_status'] == 'Available';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selected hotspot'),
        leading: BackButton(onPressed: _back),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            row['name'] as String,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          Text(
            'Assigned peers',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (peers.isEmpty) const Text('No assigned peers'),
          for (final peer in peers)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(peer),
            ),
          const SizedBox(height: 24),
          Text(
            available ? 'Location captured' : 'GPS unavailable',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (available) ...[
            Text('Latitude: ${(row['latitude'] as num).toStringAsFixed(6)}'),
            Text('Longitude: ${(row['longitude'] as num).toStringAsFixed(6)}'),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('open-client-entry'),
            onPressed: () => setState(() => _page = _Page.encounter),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Enter client record'),
          ),
        ],
      ),
      bottomNavigationBar: _footer(),
    );
  }

  Widget _recordsPage(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text("Today's records"),
      leading: BackButton(onPressed: _back),
      actions: [
        IconButton(
          key: const ValueKey('refresh-today-records'),
          tooltip: 'Refresh',
          onPressed: _recordsLoading ? null : _openRecords,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: _recordsLoading
          ? const Center(child: CircularProgressIndicator())
          : _recordsError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_recordsError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _openRecords,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _records.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No client records saved today.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: _records.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final record = _records[index];
                return ListTile(
                  key: ValueKey('record-${record['encounter_id']}'),
                  title: Text(record['client_code'] as String),
                  subtitle: Text(
                    "${record['hotspot_name']} - ${_recordKind(record)} - ${_testSummary(record)}",
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_savedTime(record)),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => setState(() {
                    _selectedRecord = record;
                    _page = _Page.recordDetail;
                  }),
                );
              },
            ),
    ),
    bottomNavigationBar: _footer(),
  );

  Widget _recordDetailPage(BuildContext context) {
    final record = _selectedRecord!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record detail'),
        leading: BackButton(onPressed: _back),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            record['client_code'] as String,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text("${record['hotspot_name']} - ${record['visit_date']}"),
          const SizedBox(height: 20),
          _summarySection(context, 'Client', {
            'Type': _recordKind(record),
            'User type': _text(record['user_type']),
            'Gender': _text(record['gender']),
            'Previous HIV': _text(record['previous_hiv']),
            'Previous HCV': _text(record['previous_hcv']),
            'Previous HBV': _text(record['previous_hbv']),
            'Previous MMT': _text(record['previous_mmt']),
            'Previous ART': _text(record['previous_art']),
          }),
          const SizedBox(height: 20),
          _summarySection(context, 'Testing', {
            'HIV': _text(record['hiv']),
            'HCV': _text(record['hcv']),
            'HBV': _text(record['hbv']),
            'Syphilis': _text(record['syphilis']),
          }),
          const SizedBox(height: 20),
          _summarySection(context, 'Distribution', {
            '3cc': _text(record['dist_3cc']),
            '1cc': _text(record['dist_1cc']),
            'LDS': _text(record['dist_lds']),
            'Alcohol swab': _text(record['dist_alcohol_swab']),
            'Sterile water': _text(record['dist_sterile_water']),
            'Condom': _text(record['dist_condom']),
          }),
          const SizedBox(height: 20),
          _summarySection(context, 'Recollection', {
            '3cc': _text(record['recollect_3cc']),
            '1cc': _text(record['recollect_1cc']),
            'LDS': _text(record['recollect_lds']),
          }),
          const SizedBox(height: 20),
          _summarySection(context, 'Other', {
            'Refer to DIC': record['refer_dic'] == 1 ? 'Yes' : 'No',
            'Saved time': _savedTime(record),
            'Remark': _text(record['remark']),
          }),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('edit-record'),
            onPressed: _deletingRecord
                ? null
                : () => setState(() => _page = _Page.editRecord),
            icon: const Icon(Icons.edit_outlined),
            label: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Edit record'),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('delete-record'),
            onPressed: _deletingRecord ? null : _deleteSelectedRecord,
            icon: const Icon(Icons.delete_outline),
            label: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_deletingRecord ? 'Deleting...' : 'Delete record'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _footer(),
    );
  }

  Widget _summaryPage(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Daily summary'),
      leading: BackButton(onPressed: _back),
      actions: [
        IconButton(
          key: const ValueKey('refresh-daily-summary'),
          tooltip: 'Refresh',
          onPressed: _summaryLoading ? null : _openSummary,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: _summaryLoading
          ? const Center(child: CircularProgressIndicator())
          : _summaryError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_summaryError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _openSummary,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  "Today's work",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Only your saved records on this phone are counted.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                _summaryGrid(context, [
                  _SummaryItem('Hotspots', _value('hotspots')),
                  _SummaryItem('Records', _value('client_records')),
                  _SummaryItem('Unique people', _value('unique_people')),
                  _SummaryItem('DIC referrals', _value('dic_referrals')),
                ]),
                const SizedBox(height: 20),
                _summarySection(context, 'Client type', {
                  'New': _value('new_clients'),
                  'Old': _value('old_clients'),
                  'Not specified': _value('unspecified_clients'),
                }),
                const SizedBox(height: 20),
                _summarySection(context, 'Testing', {
                  'HIV tested': _value('hiv_tested'),
                  'HIV reactive': _value('hiv_reactive'),
                  'HCV tested': _value('hcv_tested'),
                  'HCV reactive': _value('hcv_reactive'),
                  'HBV tested': _value('hbv_tested'),
                  'HBV reactive': _value('hbv_reactive'),
                  'Syphilis tested': _value('syphilis_tested'),
                  'Syphilis reactive': _value('syphilis_reactive'),
                }),
                const SizedBox(height: 20),
                _summarySection(context, 'Distribution', {
                  '3cc': _value('dist_3cc'),
                  '1cc': _value('dist_1cc'),
                  'LDS': _value('dist_lds'),
                  'Alcohol swab': _value('dist_alcohol_swab'),
                  'Sterile water': _value('dist_sterile_water'),
                  'Condom': _value('dist_condom'),
                }),
                const SizedBox(height: 20),
                _summarySection(context, 'Recollection', {
                  '3cc': _value('recollect_3cc'),
                  '1cc': _value('recollect_1cc'),
                  'LDS': _value('recollect_lds'),
                }),
              ],
            ),
    ),
    bottomNavigationBar: _footer(),
  );

  Widget _syncPage(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sync status'),
      leading: BackButton(onPressed: _back),
      actions: [
        IconButton(
          key: const ValueKey('refresh-sync-status'),
          tooltip: 'Refresh',
          onPressed: _syncLoading ? null : _openSyncStatus,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: _syncLoading
          ? const Center(child: CircularProgressIndicator())
          : _syncError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_syncError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _openSyncStatus,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Desktop connection',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'The Windows dashboard is not configured yet. Your records remain saved on this phone.',
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'This screen is for checking pending changes only. Sync will stay unavailable until the office dashboard is built and paired.',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _summaryGrid(context, [
                  _SummaryItem(
                    'Pending changes',
                    ((_syncStatus?['pending_operations'] as num?) ?? 0).toInt(),
                  ),
                ]),
                const SizedBox(height: 20),
                _summarySection(context, 'Connection', {
                  'Status': _text(_syncStatus?['dashboard_status']),
                  'Dashboard': _text(_syncStatus?['dashboard_name']),
                  'Address': _text(_syncStatus?['dashboard_url']),
                  'Paired at': _text(_syncStatus?['paired_at']),
                  'Pairing prepared at': _text(
                    _syncStatus?['pairing_prepared_at'],
                  ),
                  'Certificate fingerprint': _text(
                    _syncStatus?['certificate_fingerprint_hint'],
                  ),
                  'Last successful sync': _text(
                    _syncStatus?['last_successful_sync_at'],
                  ),
                }),
                const SizedBox(height: 20),
                _summarySection(context, 'Sync readiness', {
                  'Dashboard address saved': _yesNo(
                    _hasText(_syncStatus?['dashboard_url']),
                  ),
                  'Pairing code saved': _yesNo(
                    _syncStatus?['pairing_code_saved'] == 1,
                  ),
                  'Certificate fingerprint saved': _yesNo(
                    _hasText(_syncStatus?['certificate_fingerprint_hint']),
                  ),
                  'Ready to request pairing': _yesNo(
                    _hasText(_syncStatus?['dashboard_url']) &&
                        _syncStatus?['pairing_code_saved'] == 1 &&
                        _hasText(_syncStatus?['certificate_fingerprint_hint']),
                  ),
                  'Dashboard paired': _yesNo(
                    _syncStatus?['dashboard_status'] == 'Paired',
                  ),
                  'Ready to sync': 'No',
                }),
                const SizedBox(height: 20),
                _summarySection(context, 'Retention safety', {
                  'Keep days on phone': _syncValue('retention_keep_days'),
                  'Old client records': _syncValue('old_client_records'),
                  'Held because unsynced': _syncValue(
                    'old_client_records_held_unsynced',
                  ),
                  'Eligible after acknowledgement': _syncValue(
                    'old_client_records_eligible_after_ack',
                  ),
                  'Cleanup enabled': _yesNo(
                    _syncStatus?['retention_cleanup_enabled'] == 1,
                  ),
                  'Retention cutoff date': _text(
                    _syncStatus?['retention_cutoff_day'],
                  ),
                }),
                const SizedBox(height: 20),
                _summarySection(context, 'Pending details', {
                  'Worker changes': _syncValue('pending_workers'),
                  'Hotspot changes': _syncValue('pending_hotspots'),
                  'Client record changes': _syncValue('pending_encounters'),
                  'Creates': _syncValue('pending_creates'),
                  'Updates': _syncValue('pending_updates'),
                  'Deletes': _syncValue('pending_deletes'),
                }),
                const SizedBox(height: 20),
                _summarySection(context, 'App identity', {
                  'Project': _text(_syncStatus?['project_name']),
                  'Project ID': _text(_syncStatus?['project_id']),
                  'Device ID': _shortDeviceId(_syncStatus?['device_id']),
                }),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  key: const ValueKey('view-pending-changes'),
                  onPressed: _openPendingChanges,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('View pending changes'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('configure-dashboard-address'),
                  onPressed: () {
                    _openDashboardAddress();
                  },
                  icon: const Icon(Icons.settings_ethernet_outlined),
                  label: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Set pairing information'),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('sync-disabled'),
                  onPressed: null,
                  icon: const Icon(Icons.sync_disabled_outlined),
                  label: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Sync unavailable until dashboard setup'),
                  ),
                ),
              ],
            ),
    ),
    bottomNavigationBar: _footer(),
  );

  Widget _pendingChangesPage(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Pending changes'),
      leading: BackButton(onPressed: _back),
      actions: [
        IconButton(
          key: const ValueKey('refresh-pending-changes'),
          tooltip: 'Refresh',
          onPressed: _pendingChangesLoading ? null : _openPendingChanges,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: _pendingChangesLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingChangesError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_pendingChangesError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _openPendingChanges,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _pendingChanges.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No pending changes.', textAlign: TextAlign.center),
              ),
            )
          : ListView.separated(
              itemCount: _pendingChanges.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = _pendingChanges[index];
                return ListTile(
                  key: ValueKey('pending-${row['operation_id']}'),
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(_operationLabel(row)),
                  subtitle: Text(
                    'Revision ${row['revision']} - ${_operationTime(row)}',
                  ),
                );
              },
            ),
    ),
    bottomNavigationBar: _footer(),
  );

  Widget _dashboardAddressPage(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Dashboard pairing'),
      leading: BackButton(onPressed: _back),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Future dashboard connection',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Save the Windows dashboard HTTPS device API address, six-digit pairing code, and certificate fingerprint. You can also check that the dashboard certificate matches this fingerprint. This prepares the phone only; it does not pair, upload, sync or delete data yet.',
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey('dashboard-address'),
            controller: _dashboardUrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Dashboard address',
              hintText: 'https://192.168.1.50:3443/api/v1',
              errorText: _dashboardAddressError,
              prefixIcon: const Icon(Icons.link_outlined),
            ),
            onChanged: (_) => widget.session.activity(),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('dashboard-pairing-code'),
            controller: _pairingCode,
            keyboardType: TextInputType.number,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Pairing code',
              helperText: 'Enter exactly 6 digits. Leading zeros are kept.',
              errorText: _dashboardPairingError,
              prefixIcon: const Icon(Icons.pin_outlined),
            ),
            onChanged: (_) => widget.session.activity(),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('dashboard-certificate-fingerprint'),
            controller: _certificateFingerprint,
            keyboardType: TextInputType.text,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Certificate SHA-256 fingerprint',
              helperText:
                  'Paste the full fingerprint shown by the LAN dashboard.',
              hintText: '64 hex characters',
              errorText: _certificateFingerprintError,
              prefixIcon: const Icon(Icons.verified_user_outlined),
            ),
            onChanged: (_) => widget.session.activity(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('check-dashboard-certificate'),
            onPressed:
                _savingDashboardAddress || _checkingDashboardCertificate
                ? null
                : _checkDashboardCertificate,
            icon: const Icon(Icons.fact_check_outlined),
            label: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _checkingDashboardCertificate
                    ? 'Checking certificate...'
                    : 'Check certificate',
              ),
            ),
          ),
          if (_certificateCheckResult != null) ...[
            const SizedBox(height: 12),
            _certificateCheckCard(context, _certificateCheckResult!),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('save-dashboard-address'),
            onPressed:
                _savingDashboardAddress || _checkingDashboardCertificate
                ? null
                : _saveDashboardPairing,
            icon: const Icon(Icons.save_outlined),
            label: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _savingDashboardAddress
                    ? 'Saving...'
                    : 'Save pairing info only',
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('clear-dashboard-address'),
            onPressed:
                _savingDashboardAddress ||
                    _checkingDashboardCertificate ||
                    _dashboardUrl.text.isEmpty
                ? null
                : _clearDashboardAddress,
            icon: const Icon(Icons.clear_outlined),
            label: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Clear saved pairing'),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: _footer(),
  );

  int _value(String key) => (_summary?[key] as num?)?.toInt() ?? 0;

  int _syncValue(String key) => (_syncStatus?[key] as num?)?.toInt() ?? 0;

  Widget _certificateCheckCard(
    BuildContext context,
    DashboardCertificateCheckResult result,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final success = result.status == DashboardCertificateCheckStatus.match;
    final details = [
      if (result.fingerprintHint != null)
        'Fingerprint: ${result.fingerprintHint}',
      if (result.expectedHint != null) 'Expected: ${result.expectedHint}',
      if (result.actualHint != null) 'Dashboard: ${result.actualHint}',
    ];
    return Card(
      color: success ? colorScheme.primaryContainer : colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              success
                  ? Icons.verified_user_outlined
                  : Icons.warning_amber_outlined,
              color: success
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle(
                style: TextStyle(
                  color: success
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onErrorContainer,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.message,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final line in details) ...[
                      const SizedBox(height: 4),
                      Text(line),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryGrid(BuildContext context, List<_SummaryItem> items) =>
      GridView.count(
        crossAxisCount: 2,
        childAspectRatio: 1.9,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final item in items)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.value.toString(),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(item.label),
                  ],
                ),
              ),
            ),
        ],
      );

  Widget _summarySection(
    BuildContext context,
    String title,
    Map<String, Object> values,
  ) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final entry in values.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(entry.key)),
                  Text(
                    entry.value.toString(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  String _recordKind(data.Row record) =>
      (record['client_kind'] as String?) ?? 'Not specified';

  String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  bool _hasText(Object? value) => _text(value) != '-';

  String _yesNo(bool value) => value ? 'Yes' : 'No';

  String _testSummary(data.Row record) {
    final tested = [
      if (record['hiv'] != 'No') 'HIV',
      if (record['hcv'] != 'No') 'HCV',
      if (record['hbv'] != 'No') 'HBV',
      if (record['syphilis'] != 'No') 'Syphilis',
    ];
    return tested.isEmpty ? 'No tests' : 'Tested ${tested.join(', ')}';
  }

  String _savedTime(data.Row record) {
    final value = record['created_at'] as String?;
    if (value == null) return '';
    final time = DateTime.tryParse(value)?.toLocal();
    if (time == null) return '';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _operationLabel(data.Row operation) {
    final action = _text(operation['action']);
    final type = _text(operation['entity_type']);
    return '${_capitalize(action)} ${_operationType(type)}';
  }

  String _operationType(String value) => switch (value) {
    'worker' => 'worker account',
    'hotspot' => 'hotspot',
    'encounter' => 'client record',
    _ => value,
  };

  String _operationTime(data.Row operation) {
    final value = operation['occurred_at'] as String?;
    if (value == null) return '-';
    final time = DateTime.tryParse(value)?.toLocal();
    if (time == null) return '-';
    final date =
        '${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$date $hour:$minute';
  }

  String _capitalize(String value) {
    if (value.isEmpty || value == '-') return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _shortDeviceId(Object? value) {
    final text = value?.toString() ?? '';
    if (text.length <= 12) return _text(text);
    return '${text.substring(0, 8)}...${text.substring(text.length - 4)}';
  }
}

class _SummaryItem {
  const _SummaryItem(this.label, this.value);
  final String label;
  final int value;
}
