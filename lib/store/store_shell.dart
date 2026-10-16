import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_colors.dart';
import '../data/catalog/catalog_repository.dart';
import '../look/look_controller.dart';
import 'screens/fonts_screen.dart';
import 'screens/me_screen.dart';
import 'screens/store_home_screen.dart';
import 'screens/themes_screen.dart';
import 'screens/wallpapers_screen.dart';
import 'state/user_store.dart';

/// The store's five tabs: Store, Themes, Wallpapers, Fonts, Me. Pages
/// opened from them (a theme, a festival, search) cover the tab bar.
class StoreShell extends StatefulWidget {
  const StoreShell({super.key});

  /// Switches tab from a page inside it (a banner's "Try fonts").
  static void showTab(BuildContext context, StoreTab tab) =>
      context.findAncestorStateOfType<_StoreShellState>()?._select(tab);

  @override
  State<StoreShell> createState() => _StoreShellState();
}

enum StoreTab {
  store('Store', Icons.home_outlined, Icons.home_rounded),
  themes('Themes', Icons.grid_view_outlined, Icons.grid_view_rounded),
  wallpapers('Wallpapers', Icons.image_outlined, Icons.image_rounded),
  fonts('Fonts', Icons.text_fields_outlined, Icons.text_fields_rounded),
  me('Me', Icons.person_outline_rounded, Icons.person_rounded);

  const StoreTab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _StoreShellState extends State<StoreShell> {
  StoreTab _tab = StoreTab.store;
  late final AppLifecycleListener _lifecycle;

  /// A filter a banner asked for ("Christmas" wallpapers).
  String? wallpaperFilter;

  @override
  void initState() {
    super.initState();
    // wallp Home may have finished a pending apply while we were away.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        context.read<LookController>().load();
        context.read<UserStore>().load();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _select(StoreTab tab, {String? wallpaperFilter}) => setState(() {
    _tab = tab;
    if (wallpaperFilter != null) this.wallpaperFilter = wallpaperFilter;
  });

  @override
  Widget build(BuildContext context) {
    final ready = context.watch<CatalogRepository>().isReady;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: !ready
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.brand),
              )
            : IndexedStack(
                index: _tab.index,
                children: [
                  for (final t in StoreTab.values)
                    // Hidden tabs stop animating their scenes.
                    TickerMode(
                      enabled: t == _tab,
                      child: switch (t) {
                        StoreTab.store => const StoreHomeScreen(),
                        StoreTab.themes => const ThemesScreen(),
                        StoreTab.wallpapers => WallpapersScreen(
                          key: ValueKey(wallpaperFilter),
                          initialFilter: wallpaperFilter,
                        ),
                        StoreTab.fonts => const FontsScreen(),
                        StoreTab.me => const MeScreen(),
                      },
                    ),
                ],
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (i) => _select(StoreTab.values[i]),
        destinations: [
          for (final t in StoreTab.values)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

/// Opens the Wallpapers tab filtered to [festivalId] (a banner's action).
void showWallpapersTab(BuildContext context, {String? festivalId}) => context
    .findAncestorStateOfType<_StoreShellState>()
    ?._select(StoreTab.wallpapers, wallpaperFilter: festivalId);
