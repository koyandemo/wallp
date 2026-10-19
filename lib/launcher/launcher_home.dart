import 'dart:async';

import 'package:flutter/material.dart';

import '../core/date_format.dart';
import '../data/api/event_queue.dart';
import '../look/accent_paint.dart';
import '../look/applied_look.dart';
import '../look/look_store.dart';
import '../look/resolved_look.dart';
import '../render/font_registry.dart';
import '../models/phone_theme.dart';
import '../services/icon_pack_service.dart';
import '../services/launcher_service.dart';
import '../store/state/user_store.dart';
import '../services/wallpaper_service.dart';
import '../widgets/live_now.dart';
import 'add_apps_sheet.dart';
import 'app_drawer.dart';
import 'home_arrangement.dart';
import 'home_layout.dart';
import 'launcher_icon.dart';

/// wallp's home screen: clock + countdown, pages of apps and a dock, all in
/// the applied theme's style, over the real system wallpaper. Long-press to
/// edit: drag icons between slots, pages and the dock.
class LauncherHome extends StatefulWidget {
  const LauncherHome({
    super.key,
    this.appsService = const IconPackService(),
    this.launcher = const LauncherService(),
    this.looks,
    this.store,
  });

  final IconPackService appsService;
  final LauncherService launcher;

  /// The applied look: what to draw, and a pending apply to finish.
  final LookStore? looks;
  final HomeStore? store;

  @override
  State<LauncherHome> createState() => _LauncherHomeState();
}

class _LauncherHomeState extends State<LauncherHome>
    with WidgetsBindingObserver {
  late final LookStore _looks = widget.looks ?? LookStore();
  late final HomeStore _store = widget.store ?? HomeStore();
  final _pages = PageController();

  ResolvedLook? _applied;
  List<InstalledApp>? _apps;
  Map<String, InstalledApp> _byPackage = const {};
  HomeArrangement? _arrangement;
  DateTime? _appsLoadedAt;
  String? _error;

  bool _editing = false;
  int _page = 0;

  /// Flips pages while an icon is held at the screen edge.
  Timer? _edgeTimer;

  /// Upward distance of the current drag on the home screen.
  double _dragDy = 0;

  /// Re-read the app list on return to home at most this often.
  static const _appsMaxAge = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LauncherService.listen(
      onHomePressed: _onHomePressed,
      onAppsChanged: _onAppsChanged,
    );
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _edgeTimer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  /// Finishes a theme apply that switching the home app to wallp cut short.
  /// Never throws: the home screen must load regardless.
  Future<AppliedLook?> _applyPending() async {
    try {
      final look = await _looks.takePending();
      if (look == null) return null;
      await _looks.save(look);
      // Load first: recording into an empty store would drop the history.
      final user = UserStore();
      await user.load();
      await user.recordApplied(look.theme.id, look.appliedAt);
      // Queued only: the store sends it. A repeat from the store's own
      // finish is dropped as a duplicate.
      await EventQueue().add(AppEventType.themeApplied, look.theme.id);
      return look;
    } on Object {
      return null;
    }
  }

  /// After the next frame, when the home screen's Scaffold exists.
  void _announceApplied(AppliedLook look) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${look.theme.name.en} applied')),
        );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from an app or the theme store: pick up a newly applied theme
    // and any installed/removed apps.
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final pending = await _applyPending();
    final now = DateTime.now();
    final look = await _looks.load(now: now);
    // Draw at once; redraw when this engine has loaded the downloaded
    // fonts (a slow disk must never hold back the home screen).
    FontRegistry.shared.ensureAll(look.fonts.values).then((_) {
      if (mounted) setState(() {});
    });
    final applied = ResolvedLook.of(look, now);
    if (!mounted) return;
    setState(() => _applied = applied);
    if (pending != null) _announceApplied(pending);

    final loadedAt = _appsLoadedAt;
    if (loadedAt != null && DateTime.now().difference(loadedAt) < _appsMaxAge) {
      return;
    }
    try {
      final apps = await widget.appsService.installedApps();
      final byPackage = {for (final app in apps) app.packageName: app};
      final saved = _arrangement ?? await _store.load();
      final arrangement =
          (saved ?? HomeArrangement.fromLayout(HomeLayout.suggested(apps)))
              .retainInstalled(byPackage.keys.toSet());
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _byPackage = byPackage;
        _arrangement = arrangement;
        _appsLoadedAt = DateTime.now();
        _error = null;
      });
      if (arrangement != saved) await _store.save(arrangement);
    } on WallpaperException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// An app was installed, updated or removed: patch just those entries
  /// instead of reloading every app.
  Future<void> _onAppsChanged(
    List<String> packages, {
    required bool removed,
  }) async {
    final current = _apps;
    if (current == null) return;
    final apps = current
        .where((a) => !packages.contains(a.packageName))
        .toList();
    if (!removed) {
      for (final package in packages) {
        final app = await widget.appsService.app(package);
        if (app != null) apps.add(app);
      }
      apps.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
    }
    if (!mounted) return;
    final byPackage = {for (final app in apps) app.packageName: app};
    final arrangement = _arrangement?.retainInstalled(byPackage.keys.toSet());
    final changed = arrangement != _arrangement;
    setState(() {
      _apps = apps;
      _byPackage = byPackage;
      _arrangement = arrangement;
    });
    if (changed && arrangement != null) await _store.save(arrangement);
  }

  void _update(HomeArrangement next) {
    setState(() => _arrangement = next);
    _store.save(next);
  }

  void _onHomePressed() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (_editing) {
      _stopEditing();
    } else if (_page != 0 && _pages.hasClients) {
      _pages.animateToPage(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _startEditing() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _editing = true);
  }

  void _stopEditing() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    final cleaned = _arrangement!.withoutEmptyPages();
    _update(cleaned);
    setState(() {
      _editing = false;
      _page = _page.clamp(0, cleaned.pages.length - 1);
    });
    if (_pages.hasClients) _pages.jumpToPage(_page);
  }

  void _addPage() {
    _update(_arrangement!.addPage());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pages.hasClients) {
        _pages.animateToPage(
          _arrangement!.pages.length - 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _addApps() async {
    final applied = _applied!;
    final arrangement = _arrangement!;
    final picked = await showAddAppsSheet(
      context,
      apps: [
        for (final app in _apps!)
          if (!arrangement.contains(app.packageName)) app,
      ],
      theme: applied.homeTheme,
      accent: applied.accent,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    var next = _arrangement!;
    for (final package in picked) {
      next = next.add(package, page: _page);
    }
    _update(next);
  }

  /// While dragging, holding an icon at the left/right edge flips the page
  /// (adding a new page past the last one).
  void _holdAtEdge(int direction) {
    _edgeTimer ??= Timer(const Duration(milliseconds: 600), () {
      _edgeTimer = null;
      if (!mounted || !_pages.hasClients) return;
      final target = _page + direction;
      if (target < 0) return;
      if (target >= _arrangement!.pages.length) {
        _update(_arrangement!.addPage());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pages.hasClients) {
          _pages.animateToPage(
            target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        }
      });
    });
  }

  void _leaveEdge() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
  }

  void _launch(InstalledApp app) => widget.launcher.launchApp(app.packageName);

  void _openDrawer() {
    final applied = _applied;
    final apps = _apps;
    if (applied == null || apps == null || _editing) return;
    Navigator.of(context).push(
      AppDrawer.route(
        AppDrawer(
          apps: apps,
          theme: applied.homeTheme,
          accent: applied.accent,
          onLaunch: _launch,
          onLongPress: _showAppMenu,
        ),
      ),
    );
  }

  void _showAppMenu(InstalledApp app) {
    final applied = _applied!;
    final onHome = _arrangement?.contains(app.packageName) ?? false;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        void act(VoidCallback action) {
          Navigator.pop(sheet);
          action();
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: LauncherIcon(
                  app: app,
                  theme: applied.homeTheme,
                  accent: applied.accent,
                  size: 44,
                ),
                title: Text(
                  app.label,
                  style: applied.homeTheme.appNameStyle(
                    const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const Divider(),
              if (onHome)
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline_rounded),
                  title: const Text('Remove from home screen'),
                  onTap: () =>
                      act(() => _update(_arrangement!.remove(app.packageName))),
                )
              else
                ListTile(
                  leading: const Icon(Icons.add_circle_outline_rounded),
                  title: const Text('Add to home screen'),
                  onTap: () => act(
                    () => _update(
                      _arrangement!.add(app.packageName, page: _page),
                    ),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Edit home screen'),
                onTap: () => act(_startEditing),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('App info'),
                onTap: () =>
                    act(() => widget.launcher.openAppInfo(app.packageName)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHomeMenu() {
    if (_editing) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit home screen'),
              onTap: () {
                Navigator.pop(sheet);
                _startEditing();
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_rounded),
              title: const Text('Change theme'),
              subtitle: const Text('Open the wallp theme store'),
              onTap: () {
                Navigator.pop(sheet);
                widget.launcher.openThemes();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final applied = _applied;
    if (applied == null) return const SizedBox.expand();
    final theme = applied.homeTheme;
    final accent = applied.accent;
    final arrangement = _arrangement;

    return PopScope(
      // Back never leaves the home screen; in edit mode it finishes editing.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (_editing) _stopEditing();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: _editing ? null : _showHomeMenu,
          // A quick flick or a short drag up both open the drawer.
          // Off while editing so it doesn't fight with dragging icons.
          onVerticalDragStart: _editing ? null : (_) => _dragDy = 0,
          onVerticalDragUpdate: _editing ? null : (d) => _dragDy += d.delta.dy,
          onVerticalDragEnd: _editing
              ? null
              : (d) {
                  if ((d.primaryVelocity ?? 0) < -250 || _dragDy < -80) {
                    _openDrawer();
                  }
                },
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 28),
                _ClockHeader(
                  theme: theme,
                  accent: accent,
                  clockColor: applied.clockColor,
                  clockScale: applied.clockScale,
                  clockGradient: applied.clockGradient,
                  accentGradient: applied.accentGradient,
                ),
                const SizedBox(height: 16),
                if (_editing)
                  Text(
                    'Drag icons to move them · hold at the edge for '
                    'another page',
                    style: _shadowed(theme, 12),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: arrangement == null
                      ? Center(
                          child: _error != null
                              ? Text(_error!, style: _shadowed(theme, 14))
                              : CircularProgressIndicator(color: accent),
                        )
                      : _buildPages(arrangement, theme, accent),
                ),
                if (arrangement != null)
                  _PageDots(count: arrangement.pages.length, current: _page),
                const SizedBox(height: 6),
                if (_editing)
                  _EditBar(
                    accent: accent,
                    onAddApps: _addApps,
                    onAddPage: _addPage,
                    onDone: _stopEditing,
                  )
                else
                  _AllAppsHint(theme: theme, onTap: _openDrawer),
                const SizedBox(height: 8),
                if (arrangement != null) _buildDock(arrangement, theme, accent),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPages(
    HomeArrangement arrangement,
    PhoneTheme theme,
    Color accent,
  ) {
    final pages = PageView.builder(
      controller: _pages,
      itemCount: arrangement.pages.length,
      onPageChanged: (i) => setState(() => _page = i),
      itemBuilder: (context, pageIndex) => LayoutBuilder(
        builder: (context, box) {
          const columns = 4;
          const rows = HomeArrangement.pageSlots ~/ columns;
          final cellWidth = (box.maxWidth - 24) / columns;
          final cellHeight = box.maxHeight / rows;
          final iconSize = (cellHeight - 30).clamp(36.0, 56.0);
          final packages = arrangement.pages[pageIndex];
          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: cellWidth / cellHeight,
            ),
            itemCount: HomeArrangement.pageSlots,
            itemBuilder: (context, i) => _slot(
              SlotRef.page(pageIndex, i),
              i < packages.length ? _byPackage[packages[i]] : null,
              theme: theme,
              accent: accent,
              iconSize: iconSize,
            ),
          );
        },
      ),
    );
    if (!_editing) return pages;
    return Stack(
      children: [
        pages,
        for (final direction in [-1, 1])
          Positioned(
            top: 0,
            bottom: 0,
            width: 28,
            left: direction < 0 ? 0 : null,
            right: direction > 0 ? 0 : null,
            child: DragTarget<String>(
              onWillAcceptWithDetails: (_) => false,
              onMove: (_) => _holdAtEdge(direction),
              onLeave: (_) => _leaveEdge(),
              builder: (context, _, _) => const SizedBox.expand(),
            ),
          ),
      ],
    );
  }

  Widget _buildDock(
    HomeArrangement arrangement,
    PhoneTheme theme,
    Color accent,
  ) {
    final slots = _editing
        ? HomeArrangement.dockSlots
        : arrangement.dock.length;
    if (slots == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.palette.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: theme.palette.text.withValues(alpha: 0.14)),
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            for (var i = 0; i < slots; i++)
              Expanded(
                child: _slot(
                  SlotRef.dock(i),
                  i < arrangement.dock.length
                      ? _byPackage[arrangement.dock[i]]
                      : null,
                  theme: theme,
                  accent: accent,
                  iconSize: 56,
                  label: false,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One home/dock cell. In edit mode it accepts dropped icons, and its own
  /// icon can be dragged away or removed with the − badge.
  Widget _slot(
    SlotRef ref,
    InstalledApp? app, {
    required PhoneTheme theme,
    required Color accent,
    required double iconSize,
    bool label = true,
  }) {
    Widget tile(InstalledApp app) => LauncherAppTile(
      app: app,
      theme: theme,
      accent: accent,
      iconSize: iconSize,
      showLabel: label,
      onTap: () => _launch(app),
      onLongPress: () => _showAppMenu(app),
    );

    if (!_editing) {
      return app == null ? const SizedBox.shrink() : _fit(tile(app));
    }

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != app?.packageName,
      onAcceptWithDetails: (d) => _update(_arrangement!.move(d.data, ref)),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: hovering ? accent.withValues(alpha: 0.18) : null,
            border: Border.all(
              color: hovering
                  ? accent
                  : Colors.white.withValues(alpha: app == null ? 0.18 : 0),
              width: hovering ? 2 : 1,
            ),
          ),
          child: app == null
              ? const SizedBox.expand()
              : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _fit(
                      Draggable<String>(
                        data: app.packageName,
                        onDragEnd: (_) => _leaveEdge(),
                        feedback: Material(
                          color: Colors.transparent,
                          child: LauncherIcon(
                            app: app,
                            theme: theme,
                            accent: accent,
                            size: iconSize + 8,
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.25,
                          child: IgnorePointer(child: tile(app)),
                        ),
                        // AbsorbPointer (not IgnorePointer): the icon must
                        // still be hit-testable so the Draggable gets touches.
                        child: AbsorbPointer(child: tile(app)),
                      ),
                    ),
                    Positioned(
                      top: -4,
                      right: -2,
                      child: _RemoveBadge(
                        label: 'Remove ${app.label}',
                        onTap: () =>
                            _update(_arrangement!.remove(app.packageName)),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// Shrinks a tile on small screens instead of overflowing its slot.
Widget _fit(Widget tile) => Center(
  child: FittedBox(fit: BoxFit.scaleDown, child: tile),
);

const _textShadow = [
  Shadow(color: Color(0xCC000000), blurRadius: 8, offset: Offset(0, 1)),
];

TextStyle _shadowed(PhoneTheme theme, double size) => theme.bodyStyle(
  TextStyle(fontSize: size, color: Colors.white, shadows: _textShadow),
);

class _RemoveBadge extends StatelessWidget {
  const _RemoveBadge({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Color(0xFFE5484D),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.remove_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox(height: 6);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == current ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == current ? 0.95 : 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class _AllAppsHint extends StatelessWidget {
  const _AllAppsHint({required this.theme, required this.onTap});

  final PhoneTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'All apps',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              const Icon(
                Icons.keyboard_arrow_up_rounded,
                color: Colors.white,
                shadows: _textShadow,
              ),
              Text('Swipe up for all apps', style: _shadowed(theme, 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.accent,
    required this.onAddApps,
    required this.onAddPage,
    required this.onDone,
  });

  final Color accent;
  final VoidCallback onAddApps;
  final VoidCallback onAddPage;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.light
        ? Colors.black
        : Colors.white;
    final tonal = FilledButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: 0.55),
      foregroundColor: Colors.white,
    );
    return Wrap(
      spacing: 8,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: onAddApps,
          style: tonal,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Apps'),
        ),
        FilledButton.icon(
          onPressed: onAddPage,
          style: tonal,
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Page'),
        ),
        FilledButton.icon(
          onPressed: onDone,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: onAccent,
          ),
          icon: const Icon(Icons.check_rounded),
          label: const Text('Done'),
        ),
      ],
    );
  }
}

class _ClockHeader extends StatelessWidget {
  const _ClockHeader({
    required this.theme,
    required this.accent,
    this.clockColor,
    this.clockScale = 1,
    this.clockGradient,
    this.accentGradient,
  });

  final PhoneTheme theme;
  final Color accent;

  /// Paints the clock when it's drawn in a gradient accent.
  final Gradient? clockGradient;

  /// Paints the countdown icon when the accent is a gradient.
  final Gradient? accentGradient;

  /// The applied clock style's colour; null = accent or white, by theme.
  final Color? clockColor;
  final double clockScale;

  @override
  Widget build(BuildContext context) {
    final use24h = MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;
    return LiveNow(
      builder: (context, now) => Column(
        children: [
          GradientText(
            gradient: clockGradient,
            child: Text(
              DateFormatX.clock(now, use24h: use24h),
              style: theme.displayStyle(
                TextStyle(
                  fontSize: 72 * clockScale,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color:
                      clockColor ?? (theme.accentClock ? accent : Colors.white),
                  // A shadow would show through the gradient's mask.
                  shadows: clockGradient == null ? _textShadow : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(DateFormatX.longDate(now), style: _shadowed(theme, 16)),
          // Undated collections (Minimal) have no countdown.
          if (theme.event case final event?) ...[
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: theme.palette.background.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GradientText(
                    gradient: accentGradient,
                    child: Icon(theme.eventIcon, size: 16, color: accent),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${event.countdownLabel(now)} · ${event.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyStyle(
                        TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.palette.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
