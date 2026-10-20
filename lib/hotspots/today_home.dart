import 'package:flutter/material.dart';

/// Presentation only: the workspace supplies the existing local summary/status.
class TodayHome extends StatelessWidget {
  const TodayHome({
    super.key,
    required this.summary,
    required this.syncStatus,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onAddClient,
    required this.onFullSummary,
    required this.onSync,
  });

  final Map<String, Object?>? summary;
  final Map<String, Object?>? syncStatus;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onAddClient;
  final VoidCallback onFullSummary;
  final VoidCallback onSync;

  int _value(String name) => (summary?[name] as num?)?.toInt() ?? 0;

  String _lastSync(BuildContext context) {
    final stamp = syncStatus?['last_successful_sync_at'] as String?;
    if (stamp == null || stamp.isEmpty) return 'No successful sync yet';
    final parsed = DateTime.tryParse(stamp);
    if (parsed == null) return 'Last successful sync: $stamp';
    final local = parsed.toLocal();
    final format = MaterialLocalizations.of(context);
    return 'Last successful sync: ${format.formatCompactDate(local)}, '
        '${format.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('today-home-scroll'),
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        MaterialLocalizations.of(context).formatFullDate(DateTime.now()),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 6),
      Text(
        'Your work today',
        key: const ValueKey('today-home-heading'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 20),
      if (loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Loading today’s totals…'),
            ],
          ),
        )
      else if (error != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(liveRegion: true, child: Text(error!)),
            TextButton(onPressed: onRefresh, child: const Text('Retry')),
          ],
        )
      else if (summary != null)
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns =
                constraints.maxWidth >= 300 &&
                MediaQuery.textScalerOf(context).scale(14) <= 21;
            final width = twoColumns
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final item in [
                  ('unique_people', 'Unique people today'),
                  ('client_records', 'Client records today'),
                  ('hotspots', 'Hotspots visited'),
                  ('hiv_tested', 'HIV tests today'),
                ])
                  SizedBox(
                    width: width,
                    child: Semantics(
                      container: true,
                      label: '${item.$2}: ${_value(item.$1)}',
                      excludeSemantics: true,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_value(item.$1)}',
                                key: ValueKey('today-total-${item.$1}'),
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(item.$2),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      const SizedBox(height: 20),
      FilledButton.icon(
        key: const ValueKey('home-add-client'),
        onPressed: onAddClient,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Add client record'),
        ),
      ),
      const SizedBox(height: 16),
      if (!loading && error == null && syncStatus != null)
        Card.outlined(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${(syncStatus?['pending_operations'] as num?)?.toInt() ?? 0} pending changes',
                  key: const ValueKey('home-pending-count'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(_lastSync(context)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('home-open-sync'),
                  onPressed: onSync,
                  icon: const Icon(Icons.sync_outlined),
                  label: const Text('Open Sync'),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 12),
      TextButton.icon(
        key: const ValueKey('open-daily-summary'),
        onPressed: onFullSummary,
        icon: const Icon(Icons.summarize_outlined),
        label: const Text('Full daily summary'),
      ),
    ],
  );
}
