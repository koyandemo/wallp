import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/store_palette.dart';
import '../../core/app_version.dart';
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
import '../state/live_wallpaper_status.dart';
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

  /// The user may change the home app in Android's settings and come back.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _checkHome);
    _checkHome();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _freeUpSpace(BuildContext context) async {
    final cache = context.read<AssetCache>();
    final before = (await cache.usage()).total;
    await cache.clearUnpinned();
    final freed = before - (await cache.usage()).total;
    if (!context.mounted) return;
    showToast(
      context,
      freed > 0
          ? 'Freed ${formatBytes(freed)}. Your applied theme is kept.'
          : 'Nothing to free: only your applied theme is downloaded',
    );
    _reloadDownloads();
  }

  void _showHomeHelp(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('wallp Home'),
      content: const Text(
        "wallp Home is wallp's own home screen. It shows every app with your "
        "theme's icons, clock and font, and follows the theme you apply.\n\n"
        'You can switch back to your old home screen any time with '
        '"Change home app".',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

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
    final favWalls = [
      for (final id in user.favouriteWallpapers) ?catalog.wallpaper(id),
    ];
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
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Tap the heart on a theme to keep it here.',
              style: TextStyle(color: context.palette.muted),
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
                            backgroundColor: context.palette.background
                                .withValues(alpha: 0.8),
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
        if (favWalls.isNotEmpty) ...[
          SectionHeader(
            title: 'Favourite wallpapers',
            subtitle: plural(favWalls.length, 'wallpaper'),
          ),
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: favWalls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => SizedBox(
                width: 120,
                child: WallpaperCard(
                  wallpaper: favWalls[i],
                  height: 200,
                  onTap: () => StoreRoutes.wallpaper(context, favWalls[i].id),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
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
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Themes you download show here. They work offline.',
                  style: TextStyle(color: context.palette.muted),
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
        if (LauncherService.isSupported) ...[
          const SectionHeader(title: 'wallp Home'),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: _HomeCard(
              isDefault: _isDefaultHome,
              onUse: () async {
                await widget.launcher.requestDefaultHome();
                _checkHome();
              },
              onOpen: () async {
                if (!await widget.launcher.goHome() && context.mounted) {
                  showToast(context, "Couldn't open wallp Home");
                }
              },
              // Android's Home app settings: pick another home screen.
              onChange: () async {
                await widget.launcher.requestDefaultHome();
                _checkHome();
              },
              onHelp: () => _showHomeHelp(context),
            ),
          ),
        ],
        const SectionHeader(title: 'Settings'),
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
        const SizedBox(height: 16),
        _GrayLinks(
          links: [
            if (user.recentSearches.isNotEmpty)
              (
                'Clear recent searches',
                () async {
                  await user.clearSearches();
                  if (context.mounted) {
                    showToast(context, 'Recent searches cleared');
                  }
                },
              ),
            ('Free up space', () => _freeUpSpace(context)),
            if (kDebugMode)
              (
                'Developer',
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DevSettingsScreen(),
                  ),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Center(
            child: Text(
              'wallp $appVersion',
              style: TextStyle(fontSize: 12, color: context.palette.muted),
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
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.palette.outline),
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
                animate: previewsAnimate(context),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isApplied ? 'ON YOUR PHONE' : 'SUGGESTED FOR NOW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: context.palette.brand,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.palette.text,
                    ),
                  ),
                  Text(
                    isApplied ? 'Applied $applied' : 'Nothing applied yet',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Clock: ${preview.look.clockFont.family} · Icons: ${preview.look.icons.pack.name.en}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.palette.muted),
          ],
        ),
      ),
    );
  }
}

/// wallp Home's status, the main action, and gray links for the rest.
class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.isDefault,
    required this.onUse,
    required this.onOpen,
    required this.onChange,
    required this.onHelp,
  });

  /// Null while checking.
  final bool? isDefault;
  final VoidCallback onUse;
  final VoidCallback onOpen;
  final VoidCallback onChange;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final on = isDefault ?? false;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: on ? p.brand : p.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                on ? Icons.check_circle_rounded : Icons.home_outlined,
                color: p.brand,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isDefault == null
                      ? 'Checking your home screen…'
                      : on
                      ? 'wallp is your home screen'
                      : 'Use wallp as your home screen',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            on ? "Every app shows your theme's icons, clock and font." : "Themed icons and clock on every app. You can switch back any time.",
            style: TextStyle(fontSize: 13, color: p.muted, height: 1.35),
          ),
          if (isDefault == false) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: onUse,
                child: const Text('Use wallp Home'),
              ),
            ),
          ],
          const SizedBox(height: 4),
          _GrayLinks(
            padding: EdgeInsets.zero,
            alignment: WrapAlignment.start,
            links: [
              if (on) ('Open wallp Home', onOpen),
              if (on) ('Change home app', onChange),
              ('What is wallp Home?', onHelp),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small gray text links, each its own tap target, separated by dots.
class _GrayLinks extends StatelessWidget {
  const _GrayLinks({
    required this.links,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.alignment = WrapAlignment.center,
  });

  final List<(String, VoidCallback)> links;
  final EdgeInsets padding;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    return Padding(
      padding: padding,
      child: Wrap(
        alignment: alignment,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Each dot travels with the link after it, so a line break
          // never leaves one dangling.
          for (final (i, (label, onTap)) in links.indexed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i > 0)
                  ExcludeSemantics(
                    child: Text('·', style: TextStyle(color: muted)),
                  ),
                TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    foregroundColor: muted,
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    // From the theme, so the links keep the app's font.
                    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  child: Text(label),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
