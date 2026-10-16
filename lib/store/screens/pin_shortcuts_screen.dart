import 'package:flutter/material.dart';

import '../../core/store_palette.dart';
import '../../launcher/launcher_icon.dart';
import '../../models/phone_theme.dart';
import '../../services/icon_pack_service.dart';
import '../../services/launcher_service.dart';
import '../../services/wallpaper_service.dart';
import '../widgets/common.dart';

/// For people who keep another home screen app: lists installed apps with
/// the applied pack's icon; "Add" pins each one to that home screen as a
/// shortcut that opens the real app.
class PinShortcutsScreen extends StatefulWidget {
  const PinShortcutsScreen({
    super.key,
    required this.theme,
    required this.accent,
    this.service = const IconPackService(),
    this.launcher = const LauncherService(),
  });

  final PhoneTheme theme;
  final Color accent;
  final IconPackService service;
  final LauncherService launcher;

  @override
  State<PinShortcutsScreen> createState() => _PinShortcutsScreenState();
}

class _PinShortcutsScreenState extends State<PinShortcutsScreen> {
  late final Future<(bool, bool, List<InstalledApp>)> _load = _loadApps();
  final _added = <String>{};
  String? _pinning;
  String _query = '';

  /// (can pin shortcuts, wallp is the home app, installed apps).
  Future<(bool, bool, List<InstalledApp>)> _loadApps() async {
    final canPin = await widget.service.canPinShortcuts();
    if (canPin) return (true, false, await widget.service.installedApps());
    // Pinning goes through the current home app, and wallp Home doesn't
    // take pinned shortcuts: it themes every icon itself. Still list the
    // apps so the user can see their themed icons.
    if (await widget.launcher.isDefaultHome()) {
      return (false, true, await widget.service.installedApps());
    }
    return (false, false, <InstalledApp>[]);
  }

  Future<void> _add(InstalledApp app) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pinning = app.packageName);
    String message;
    try {
      final asked = await widget.service.pin(
        theme: widget.theme,
        app: app,
        accent: widget.accent,
      );
      if (asked) _added.add(app.packageName);
      message = asked
          ? 'Confirm to add ${app.label} to your home screen'
          : "Your home screen didn't accept the icon";
    } on WallpaperException catch (e) {
      message = e.message;
    }
    if (mounted) setState(() => _pinning = null);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.theme.name} icons',
          style: text.titleMedium?.copyWith(fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyMessage(
              icon: Icons.error_outline_rounded,
              title: "Couldn't load your apps",
              message: '${snapshot.error}',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (canPin, wallpIsHome, apps) = snapshot.data!;
          if (!canPin && !wallpIsHome) {
            return const EmptyMessage(
              icon: Icons.phonelink_off_rounded,
              title: 'Not available on this phone',
              message:
                  'Themed icons need Android 8 or newer and a home screen '
                  'app that allows adding shortcuts.',
            );
          }
          final query = _query.toLowerCase();
          final shown = query.isEmpty
              ? apps
              : apps
                    .where((a) => a.label.toLowerCase().contains(query))
                    .toList();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Intro(
                  theme: widget.theme,
                  accent: widget.accent,
                  wallpIsHome: wallpIsHome,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search apps',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: context.palette.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final app = shown[i];
                  return _AppRow(
                    theme: widget.theme,
                    app: app,
                    accent: widget.accent,
                    added: _added.contains(app.packageName),
                    busy: _pinning == app.packageName,
                    canAdd: canPin,
                    onAdd: _pinning == null ? () => _add(app) : null,
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.theme,
    required this.accent,
    required this.wallpIsHome,
  });

  final PhoneTheme theme;
  final Color accent;

  /// wallp Home themes every icon itself, so there's nothing to add.
  final bool wallpIsHome;

  static const _samples = [
    InstalledApp(packageName: 'com.google.android.dialer', label: 'Phone'),
    InstalledApp(
      packageName: 'com.google.android.apps.messaging',
      label: 'Messages',
    ),
    InstalledApp(packageName: 'com.android.camera', label: 'Camera'),
    InstalledApp(packageName: 'com.android.chrome', label: 'Chrome'),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final app in _samples)
                LauncherIcon(app: app, theme: theme, accent: accent, size: 60),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            wallpIsHome
                ? 'Your ${theme.name} icons'
                : 'Add ${theme.name} icons to your home screen',
            style: text.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            wallpIsHome
                ? 'wallp is your home screen, so every app already shows '
                      'these icons.'
                : 'Each icon is a shortcut that opens the real app. Android '
                      'asks you to confirm each one. Then move them where you '
                      'like, and hide the original icons if your launcher '
                      'allows it.',
            style: text.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.theme,
    required this.app,
    required this.accent,
    required this.added,
    required this.busy,
    required this.canAdd,
    required this.onAdd,
  });

  final PhoneTheme theme;
  final InstalledApp app;
  final Color accent;
  final bool added;
  final bool busy;

  /// False with wallp as the home app: the icon is a preview only.
  final bool canAdd;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: LauncherIcon(app: app, theme: theme, accent: accent, size: 48),
      title: Text(
        app.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleMedium,
      ),
      trailing: !canAdd
          ? null
          : busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : TextButton.icon(
              onPressed: onAdd,
              icon: Icon(added ? Icons.check_rounded : Icons.add_rounded),
              label: Text(added ? 'Added' : 'Add'),
              style: TextButton.styleFrom(
                foregroundColor: added
                    ? context.palette.muted
                    : context.palette.brand,
              ),
            ),
    );
  }
}
