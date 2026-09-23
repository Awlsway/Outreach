import 'package:flutter/material.dart';
import 'dart:async';
import '../auth/session_controller.dart';
import '../database/outreach_repository.dart' as data;
import '../encounters/encounter_form.dart';
import '../sync/certificate_fingerprint_store.dart';
import '../sync/sync_batch_builder.dart';
import '../sync/sync_review_manifest.dart';
import '../sync/reviewed_sync_plan.dart';
import '../sync/synthetic_review_export.dart';
import '../sync/configured_manual_sync.dart';
import '../sync/manual_sync_runner.dart';
import '../sync/device_credential_store.dart';
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
    this.deviceCredentialStore,
  });
  final SessionController session;
  final HotspotLocationService location;
  final CertificateFingerprintStore? certificateFingerprintStore;
  final DeviceCredentialStore? deviceCredentialStore;
  @override
  State<HotspotWorkspace> createState() => _HotspotWorkspaceState();
}

class _HotspotWorkspaceState extends State<HotspotWorkspace> {
  late final _repository = data.OutreachRepository(
    widget.session.auth.database,
    currentWorkerId: () => widget.session.currentWorkerId,
  );
  final _search = TextEditingController();
  late final CertificateFingerprintStore _certificateFingerprintStore =
      widget.certificateFingerprintStore ?? CertificateFingerprintStore();
  late final DeviceCredentialStore _deviceCredentialStore =
      widget.deviceCredentialStore ?? DeviceCredentialStore();
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
  bool _preparingBatches = false;
  bool _testActionRunning = false;
  String? _testActionMessage;
  Map<String, int>? _batchPreparation;
  String? _batchPreparationMessage;
  ReviewedSyncPlan? _reviewedPlan;
  SyncReviewManifest? get _syncReviewManifest => _reviewedPlan?.manifest;
  bool _pendingChangesLoading = false;
  bool _deletingRecord = false;
  bool _saved = false;
  String? _error;
  String? _recordsError;
  String? _summaryError;
  String? _syncError;
  String? _pendingChangesError;
  int _query = 0;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_invalidateReviewOnLock);
  }

  void _invalidateReviewOnLock() {
    if (_reviewedPlan != null &&
        widget.session.currentWorkerId != _reviewedPlan!.workerId) {
      setState(() {
        _reviewedPlan = null;
        _batchPreparation = null;
        _batchPreparationMessage = null;
      });
      unawaited(SyntheticReviewExport.clear());
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_invalidateReviewOnLock);
    _reviewedPlan = null;
    unawaited(SyntheticReviewExport.clear());
    _query++;
    _search.dispose();
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
    if (_testActionRunning) return;
    if (SyntheticReviewExport.enabled) await SyntheticReviewExport.clear();
    if (!mounted) return;
    widget.session.activity();
    setState(() {
      _page = _Page.sync;
      _syncLoading = true;
      _syncError = null;
      _batchPreparation = null;
      _batchPreparationMessage = null;
      _reviewedPlan = null;
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

  Future<void> _prepareSyncBatches() async {
    if (_preparingBatches || _syncLoading || _testActionRunning) return;
    if (SyntheticReviewExport.enabled) await SyntheticReviewExport.clear();
    if (!mounted) return;
    widget.session.activity();
    final workerId = widget.session.currentWorkerId;
    if (workerId == null) return;
    setState(() {
      _preparingBatches = true;
      _batchPreparation = null;
      _batchPreparationMessage = null;
      _reviewedPlan = null;
    });
    try {
      final operations = await _repository.pendingOperations();
      final plan = operations.isEmpty
          ? null
          : await ReviewedSyncPlan.prepare(
              _repository,
              SyncBatchBuilder(appVersion: '0.9.9+24', clock: DateTime.now),
            );
      final batches = plan?.batches ?? <PreparedSyncBatch>[];
      if (!mounted) return;
      setState(() {
        _preparingBatches = false;
        if (_page != _Page.sync || widget.session.currentWorkerId != workerId) {
          return;
        }
        _batchPreparation = {
          'Prepared changes': operations.length,
          'Prepared batches': batches.length,
          'Total bytes': batches.fold<int>(
            0,
            (total, batch) => total + batch.byteLength,
          ),
        };
        _reviewedPlan = plan;
        _batchPreparationMessage = operations.isEmpty
            ? 'No pending changes to prepare. No data was sent.'
            : 'Local validation passed. No data was sent; all changes remain pending.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preparingBatches = false;
        if (_page != _Page.sync || widget.session.currentWorkerId != workerId) {
          return;
        }
        // Never display parsing exceptions: they may contain client payloads.
        _batchPreparationMessage =
            'Could not prepare changes. All records remain saved and pending. Ask the data assistant to review.';
      });
    }
  }

  Future<void> _reviewedTestAction({required bool send}) async {
    final plan = _reviewedPlan;
    if (!SyntheticReviewExport.enabled || plan == null || _testActionRunning) {
      return;
    }
    widget.session.activity();
    setState(() {
      _testActionRunning = true;
      _testActionMessage = null;
    });
    try {
      await plan.validate(_repository);
      if (send) {
        final result = await ConfiguredManualSync(
          repository: _repository,
          fingerprintStore: _certificateFingerprintStore,
          credentialStore: _deviceCredentialStore,
          builder: SyncBatchBuilder(
            appVersion: '0.9.9+24',
            clock: DateTime.now,
          ),
        ).run(reviewedPlan: plan);
        await SyntheticReviewExport.clear();
        if (!mounted) return;
        setState(() {
          _reviewedPlan = null;
          _testActionMessage =
              'Dashboard confirmed ${result.markedOperations} changes. '
              '${result.outcome == ManualSyncOutcome.uploaded || result.outcome == ManualSyncOutcome.batchLimitReached ? 'Reviewed batch finished.' : 'Test stopped; unconfirmed changes remain pending.'}';
        });
      } else {
        await SyntheticReviewExport.write(plan.batches.first.jsonBody);
        await plan.validate(_repository);
        if (mounted) {
          setState(() {
            _testActionMessage =
                'Test file prepared for private USB review. No data was sent to the dashboard.';
          });
        }
      }
    } catch (_) {
      await SyntheticReviewExport.clear();
      if (mounted) {
        setState(() {
          _reviewedPlan = null;
          _testActionMessage =
              'Test stopped. Prepare changes again; unconfirmed records remain pending.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _testActionRunning = false;
        });
      }
    }
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
          onPressed: _syncLoading || _preparingBatches ? null : _openSyncStatus,
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
                Text(
                  _syncStatus?['dashboard_status'] == 'Paired'
                      ? 'This phone is paired with the dashboard. Your records remain saved on this phone.'
                      : 'New connections will use QR pairing. Your records remain saved on this phone.',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      SyntheticReviewExport.enabled
                          ? 'Synthetic test: prepare and review one batch, then send only after laptop approval.'
                          : 'Check pending changes and prepare them locally. Sending records is not enabled yet.',
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
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const ValueKey('prepare-sync-batches'),
                  onPressed: _preparingBatches ? null : _prepareSyncBatches,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _preparingBatches
                          ? 'Preparing changes...'
                          : 'Prepare changes locally',
                    ),
                  ),
                ),
                if (_batchPreparationMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _batchPreparationMessage!,
                    key: const ValueKey('batch-preparation-message'),
                  ),
                ],
                if (_batchPreparation != null) ...[
                  const SizedBox(height: 12),
                  _summarySection(
                    context,
                    'Local preparation',
                    _batchPreparation!,
                  ),
                ],
                if (_syncReviewManifest != null) ...[
                  const SizedBox(height: 12),
                  _syncReviewCard(_syncReviewManifest!),
                  if (SyntheticReviewExport.enabled) ...[
                    const Text(
                      'Synthetic test only. Send after the laptop approves this exact batch.',
                    ),
                    OutlinedButton(
                      onPressed: _testActionRunning
                          ? null
                          : () => _reviewedTestAction(send: false),
                      child: const Text('Prepare private USB review file'),
                    ),
                    FilledButton(
                      onPressed: _testActionRunning
                          ? null
                          : () => _reviewedTestAction(send: true),
                      child: const Text('Send reviewed test batch'),
                    ),
                  ],
                ],
                if (_testActionMessage != null) Text(_testActionMessage!),
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
                  'Ready to sync': SyntheticReviewExport.enabled
                      ? 'Test only — requires laptop batch approval'
                      : 'No',
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
                const Text(
                  'New connections will use QR pairing. The scanner is not available in this development build.',
                  key: ValueKey('qr-pairing-pending'),
                ),
                const SizedBox(height: 12),
                if (!SyntheticReviewExport.enabled)
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

  int _value(String key) => (_summary?[key] as num?)?.toInt() ?? 0;

  int _syncValue(String key) => (_syncStatus?[key] as num?)?.toInt() ?? 0;

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

  Widget _syncReviewCard(SyncReviewManifest manifest) => Card(
    child: ExpansionTile(
      key: const ValueKey('review-first-sync-batch'),
      title: const Text('Review first batch — no sending'),
      subtitle: Text(
        '${manifest.operations.length} changes · ${manifest.byteLength} bytes',
      ),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Local preview only. No data was sent. Test-data status is unverified. '
          'The data assistant must check every record before a live test. '
          'This preview covers only the first batch; later changes remain pending.',
        ),
        const SizedBox(height: 12),
        Text(
          'Batch: ${manifest.batchId}\nProject: ${manifest.projectId}\n'
          'Worker: ${manifest.workerId}\nDevice: ${manifest.deviceId}\nBatch SHA-256: ${manifest.bodyHash}',
        ),
        const SizedBox(height: 12),
        for (final operation in manifest.operations)
          ExpansionTile(
            key: ValueKey('review-operation-${operation.operationId}'),
            title: Text(
              '${operation.sequence}. ${operation.entityType}: ${operation.label}',
            ),
            subtitle: Text(
              '${operation.action} · revision ${operation.revision}',
            ),
            childrenPadding: const EdgeInsets.all(12),
            children: [
              Text(
                'Operation: ${operation.operationId}\nEntity: ${operation.entityId}\n'
                'Payload SHA-256: ${operation.payloadHash}',
              ),
              Text(
                operation.dependencies.isEmpty
                    ? 'Required parents and earlier revision are covered in this batch.'
                    : operation.dependencies.join('\n'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        const Text(
          'Refresh clears this preview. Prepare again after any record changes; '
          'a later upload must match a freshly reviewed batch.',
        ),
      ],
    ),
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
