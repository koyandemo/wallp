import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/date_format.dart';
import '../../data/assets/asset_cache.dart';
import '../../data/assets/downloads.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../dev/dev_settings_screen.dart';
import '../../look/look_controller.dart';
import '../../look/resolved_look.dart';
import '../../services/launcher_service.dart';
import '../logic/previews.dart';
import '../logic/queries.dart';
import '../routes.dart';
import '../state/user_store.dart';
import '../widgets/common.dart';

/// Me: what's applied, favourites, history, downloads and settings.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key, this.launcher = const LauncherService()});

  final LauncherService launcher;

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  Future<List<DownloadedTheme>>? _downloads;
  bool? _isDefaultHome;

  @override
  void initState() {
    super.initState();
    _checkHome();
  }

  Future<void> _checkHome() async {
    if (!LauncherService.isSupported) return;
    final on = await widget.launcher.isDefaultHome();
    if (mounted) setState(() => _isDefaultHome = on);
  }

  void _reloadDownloads() => setState(() {
    _downloads = downloadedThemes(
      catalog: context.read<CatalogRepository>(),
      cache: context.read<AssetCache>(),
      applied: context.read<LookController>().look,
    );
  });

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final user = context.watch<UserStore>();
    final looks = context.watch<LookController>();
    final now = nowOf(context);
    _downloads ??= downloadedThemes(
      catalog: context.read<CatalogRepository>(),
      cache: context.read<AssetCache>(),
      applied: looks.look,
    );
    final favs = [for (final id in user.favouriteThemes) ?catalog.theme(id)];
    final history = [
      for (final e in user.history)
        if (catalog.theme(e.themeId) case final t?) (t, e.at),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const TabHeader(
          title: 'Me',
          subtitle: 'Your look, favourites and settings',
        ),
        if (looks.look case final look?)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: _CurrentLook(
              name: look.theme.name.en,
              isApplied: looks.isApplied,
              applied: DateFormatX.ago(look.appliedAt.toLocal(), now),
              preview: ResolvedLook.of(look, now),
              onOpen: () => StoreRoutes.theme(context, look.theme.id),
            ),
          ),
        SectionHeader(
          title: 'Favourites',
          subtitle: plural(favs.length, 'theme'),
        ),
        if (favs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Tap the heart on a theme to keep it here.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          SizedBox(
            height: 268,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: favs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final t = favs[i];
                return SizedBox(
                  width: 140,
                  child: Stack(
                    children: [
                      ThemeCard(
                        theme: t,
                        height: 220,
                        onTap: () => StoreRoutes.theme(context, t.id),
                      ),
                      Positioned(
                        // Bottom of the picture: the badge is at the top.
                        right: 2,
                        top: 172,
                        child: IconButton(
                          tooltip: 'Remove ${t.name.en} from favourites',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.background.withValues(
                              alpha: 0.8,
                            ),
                          ),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final at = await user.toggleTheme(t.id);
                            messenger
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${t.name.en} removed from favourites',
                                  ),
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    onPressed: () =>
                                        user.restoreTheme(t.id, at ?? 0),
                                  ),
                                ),
                              );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 24),
        if (history.isNotEmpty) ...[
          const SectionHeader(title: 'Recently applied'),
          for (final (t, at) in history.take(5))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: SizedBox(
                width: 36,
                height: 56,
                child: SceneThumb(
                  theme: previewOf(t, catalog, now),
                  radius: 10,
                  showClock: false,
                ),
              ),
              title: Text(t.name.en),
              subtitle: Text(DateFormatX.ago(at.toLocal(), now)),
              onTap: () => StoreRoutes.theme(context, t.id),
            ),
          const SizedBox(height: 16),
        ],
        const SectionHeader(title: 'Downloads'),
        FutureBuilder(
          future: _downloads,
          builder: (context, snap) {
            final list = snap.data;
            if (list == null) return const SizedBox(height: 48);
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Themes you download show here. They work offline.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              );
            }
            return Column(
              children: [
                for (final d in list)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(d.theme.name.en),
                    subtitle: Text(
                      d.isApplied
                          ? '${formatBytes(d.bytes)} · In use'
                          : formatBytes(d.bytes),
                    ),
                    trailing: d.isApplied
                        ? null
                        : IconButton(
                            tooltip: 'Delete ${d.theme.name.en} download',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              final freed = await deleteDownload(
                                d,
                                context.read<AssetCache>(),
                              );
                              if (!context.mounted) return;
                              showToast(context, 'Freed ${formatBytes(freed)}');
                              _reloadDownloads();
                            },
                          ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Settings'),
        if (LauncherService.isSupported)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: Icon(
              _isDefaultHome == true
                  ? Icons.check_circle_rounded
                  : Icons.home_outlined,
              color: AppColors.brand,
            ),
            title: const Text('wallp Home'),
            subtitle: Text(
              _isDefaultHome == true
                  ? 'Your home screen'
                  : 'Use wallp as your home screen for themed icons',
            ),
            onTap: _isDefaultHome == true
                ? null
                : () async {
                    await widget.launcher.requestDefaultHome();
                    _checkHome();
                  },
          ),
        for (final (s, title, sub) in const [
          (
            UserSetting.themedLockClock,
            'Themed lock screen clock',
            "Your theme's font on the lock screen, with the live wallpaper on",
          ),
          (
            UserSetting.festivalReminders,
            'Festival reminders',
            'A note 7 days before a festival theme goes live',
          ),
          (
            UserSetting.followNextFestival,
            'Follow the next festival',
            'Switch theme automatically when a festival starts',
          ),
          (
            UserSetting.matchAppToTheme,
            'Match app to my theme',
            "The store's colours follow the theme on screen",
          ),
        ])
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            title: Text(title),
            subtitle: Text(sub),
            value: user.setting(s),
            onChanged: (v) => user.set(s, v),
          ),
        if (kDebugMode)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.developer_mode_rounded),
            title: const Text('Developer'),
            subtitle: const Text(
              'Pretend network, date, catalog and downloads',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DevSettingsScreen(),
              ),
            ),
          ),
      ],
    );
  }
}

class _CurrentLook extends StatelessWidget {
  const _CurrentLook({
    required this.name,
    required this.isApplied,
    required this.applied,
    required this.preview,
    required this.onOpen,
  });

  final String name;
  final bool isApplied;
  final String applied;
  final ResolvedLook preview;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 120,
              child: SceneThumb(
                theme: preview.wallpaperTheme,
                radius: 14,
                showClock: false,
                animate: true,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isApplied ? 'ON YOUR PHONE' : 'SUGGESTED FOR NOW',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    isApplied ? 'Applied $applied' : 'Nothing applied yet',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Clock: ${preview.look.clockFont.family} · Icons: ${preview.look.icons.pack.name.en}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
