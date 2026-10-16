import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_colors.dart';
import '../core/date_format.dart';
import '../data/assets/asset_cache.dart';
import '../data/assets/download_manager.dart';
import '../data/catalog/catalog_repository.dart';
import 'dev_settings.dart';

/// Debug builds only: the mock network, a pretend date, and what the
/// catalog repository is doing.
class DevSettingsScreen extends StatelessWidget {
  const DevSettingsScreen({super.key});

  static const _networkLabels = {
    'fast': ('Fast', 'No delay'),
    'slow': ('Slow', '600 ms, 64 KB/s'),
    'offline': ('Offline', 'Every request fails'),
    'flaky': ('Flaky', '1 in 3 requests fails'),
  };

  @override
  Widget build(BuildContext context) {
    final dev = context.watch<DevSettings>();
    final repo = context.watch<CatalogRepository>();
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Developer')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Catalog', style: text.titleMedium),
          const SizedBox(height: 12),
          _CatalogStatus(repo: repo, now: dev.clock.now()),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: repo.isRefreshing ? null : repo.refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh now'),
              ),
              OutlinedButton.icon(
                onPressed: repo.isRefreshing ? null : repo.forgetSaved,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Forget saved catalog'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('Downloads', style: text.titleMedium),
          const SizedBox(height: 12),
          const _DownloadStatus(),
          const SizedBox(height: 28),
          Text('Pretend network', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'For the mock catalog only. Applies to the next request.',
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          RadioGroup<String>(
            groupValue: dev.network,
            onChanged: (v) => dev.setNetwork(v!),
            child: Column(
              children: [
                for (final MapEntry(key: key, value: (title, sub))
                    in _networkLabels.entries)
                  RadioListTile<String>(
                    value: key,
                    title: Text(title),
                    subtitle: Text(sub),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Pretend today is', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Moves countdowns, NEW badges and banner dates. '
            'The time of day stays real.',
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(context, dev),
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(
                    dev.pretendToday == null
                        ? 'Real date'
                        : DateFormatX.longDate(dev.pretendToday!),
                  ),
                ),
              ),
              if (dev.pretendToday != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Back to the real date',
                  onPressed: () => dev.setPretendToday(null),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext context, DevSettings dev) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: dev.pretendToday ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 4),
    );
    if (picked != null) await dev.setPretendToday(picked);
  }
}

class _CatalogStatus extends StatelessWidget {
  const _CatalogStatus({required this.repo, required this.now});

  final CatalogRepository repo;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final catalog = repo.isReady ? repo.catalog : null;
    final rows = <(String, String)>[
      (
        'Showing',
        switch (repo.origin) {
          CatalogOrigin.builtIn => 'Built-in (no download yet)',
          CatalogOrigin.cache => 'Saved on this phone',
          CatalogOrigin.network => 'Downloaded this run',
          null => 'Loading…',
        },
      ),
      ('Version', repo.catalogVersion ?? '–'),
      if (catalog != null)
        (
          'Contents',
          '${catalog.themes.length} themes, ${catalog.wallpapers.length} '
              'wallpapers, ${catalog.iconPacks.length} icon packs',
        ),
      if (repo.hiddenForUpdate > 0)
        ('Hidden', '${repo.hiddenForUpdate} need a newer app'),
      if (catalog != null && catalog.issues.isNotEmpty)
        ('Skipped', '${catalog.issues.length} broken items'),
      (
        'Last check',
        repo.isRefreshing
            ? 'Checking…'
            : repo.lastCheckedAt == null
            ? 'Never'
            : DateFormatX.ago(repo.lastCheckedAt!, now),
      ),
      if (repo.lastError != null) ('Error', '${repo.lastError}'),
      if (repo.updateRecommended) ('Update', 'The server asks for a newer app'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      label,
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(child: Text(value, style: text.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DownloadStatus extends StatefulWidget {
  const _DownloadStatus();

  @override
  State<_DownloadStatus> createState() => _DownloadStatusState();
}

class _DownloadStatusState extends State<_DownloadStatus> {
  ({int total, int unpinned})? _usage;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final usage = await context.read<AssetCache>().usage();
    if (mounted) setState(() => _usage = usage);
  }

  String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final task = context.watch<DownloadManager>().current;
    final usage = _usage;
    return ListenableBuilder(
      listenable: task ?? const _Never(),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task != null) ...[
            Text(switch (task.state) {
              DownloadState.downloading =>
                '${task.label}: ${_mb(task.receivedBytes)} of '
                    '${_mb(task.totalBytes)}',
              DownloadState.done => '${task.label}: done',
              DownloadState.failed => '${task.label}: ${task.error}',
              DownloadState.cancelled => '${task.label}: cancelled',
            }, style: text.bodyMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: task.progress),
            if (task.isActive)
              TextButton(onPressed: task.cancel, child: const Text('Cancel')),
            const SizedBox(height: 12),
          ],
          Text(
            usage == null
                ? 'Checking space…'
                : 'On the phone: ${_mb(usage.total)} '
                      '(${_mb(usage.total - usage.unpinned)} kept for the '
                      'applied look)',
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await context.read<AssetCache>().clearUnpinned();
              await _refresh();
            },
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Delete files no look uses'),
          ),
        ],
      ),
    );
  }
}

/// A listenable that never fires, for when no download has run yet.
class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
