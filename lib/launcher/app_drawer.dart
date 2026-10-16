import 'package:flutter/material.dart';

import '../models/phone_theme.dart';
import '../services/icon_pack_service.dart';
import 'launcher_icon.dart';

/// Every app, themed, with search. Pull down past the top to close.
class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    required this.apps,
    required this.theme,
    required this.accent,
    required this.onLaunch,
    required this.onLongPress,
  });

  final List<InstalledApp> apps;
  final PhoneTheme theme;
  final Color accent;
  final ValueChanged<InstalledApp> onLaunch;
  final ValueChanged<InstalledApp> onLongPress;

  /// Slides up over the home screen, which stays visible behind it.
  static Route<void> route(AppDrawer drawer) => PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => drawer,
    transitionsBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String _query = '';
  bool _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.theme.palette;
    final query = _query.toLowerCase();
    final apps = query.isEmpty
        ? widget.apps
        : widget.apps
              .where((a) => a.label.toLowerCase().contains(query))
              .toList();

    return Material(
      // Solid, so the home grid doesn't show through the app list.
      color: p.background,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.text.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: widget.theme.bodyStyle(TextStyle(color: p.text)),
                decoration: InputDecoration(
                  hintText: 'Search apps',
                  hintStyle: TextStyle(color: p.textMuted),
                  prefixIcon: Icon(Icons.search_rounded, color: p.textMuted),
                  filled: true,
                  fillColor: p.surface.withValues(alpha: 0.8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollUpdateNotification>(
                // Pulling down past the top closes the drawer.
                onNotification: (n) {
                  if (n.metrics.pixels < -70) _close();
                  return false;
                },
                child: GridView.builder(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: apps.length,
                  itemBuilder: (context, i) => LauncherAppTile(
                    app: apps[i],
                    theme: widget.theme,
                    accent: widget.accent,
                    onTap: () {
                      widget.onLaunch(apps[i]);
                      _close();
                    },
                    onLongPress: () => widget.onLongPress(apps[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
