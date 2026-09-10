import 'package:flutter/material.dart' hide Row;
import '../auth/session_controller.dart';
import '../database/outreach_repository.dart';
import 'location_service.dart';
import 'new_hotspot_form.dart';

enum _Page { home, list, create, detail }

/// Internal pages stay inside the app's session/lock boundary. They do not push
/// unguarded routes above the lock screen.
class HotspotWorkspace extends StatefulWidget {
  const HotspotWorkspace({
    super.key,
    required this.session,
    required this.location,
  });
  final SessionController session;
  final HotspotLocationService location;
  @override
  State<HotspotWorkspace> createState() => _HotspotWorkspaceState();
}

class _HotspotWorkspaceState extends State<HotspotWorkspace> {
  late final _repository = OutreachRepository(
    widget.session.auth.database,
    currentWorkerId: () => widget.session.currentWorkerId,
  );
  final _search = TextEditingController();
  _Page _page = _Page.home;
  List<Row> _rows = [];
  Row? _selected;
  bool _loading = false;
  bool _saved = false;
  String? _error;
  int _query = 0;

  @override
  void dispose() {
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
    if (_page == _Page.list) {
      setState(() => _page = _Page.home);
    } else {
      _list();
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
          const Text('Client-entry forms are coming next.'),
        ],
      ),
      bottomNavigationBar: _footer(),
    );
  }
}
