import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_colors.dart';
import '../services/launcher_service.dart';
import '../services/my_themes.dart';
import '../services/theme_prefs.dart';
import '../widgets/current_theme_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/primary_button.dart';
import 'theme_detail_screen.dart';

/// Settings tab: the applied theme, making wallp the phone's home screen,
/// and the live wallpaper's lock screen clock.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.launcher = const LauncherService(),
    this.prefs,
  });

  final LauncherService launcher;
  final ThemePrefs? prefs;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late final ThemePrefs _prefs = widget.prefs ?? ThemePrefs();
  bool? _isDefaultHome;
  bool? _lockClock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _loadLockClock();
  }

  Future<void> _loadLockClock() async {
    final on = await _prefs.loadLockClock();
    if (mounted) setState(() => _lockClock = on);
  }

  Future<void> _setLockClock(bool on) async {
    setState(() => _lockClock = on);
    await _prefs.saveLockClock(on);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android's "default home app" screen.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final isDefault = await widget.launcher.isDefaultHome();
    if (mounted) setState(() => _isDefaultHome = isDefault);
  }

  Widget _currentTheme(BuildContext context) {
    final current = context.watch<MyThemes>().current;
    if (current == null) {
      return const _NoThemeCard();
    }
    return CurrentThemeCard(
      entry: current,
      now: DateTime.now(),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ThemeDetailScreen(theme: current.theme, accent: current.accent),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('Settings', style: text.headlineLarge),
          const SizedBox(height: 20),
          Text('Current theme', style: text.titleMedium),
          const SizedBox(height: 12),
          _currentTheme(context),
          const SizedBox(height: 28),
          if (!LauncherService.isSupported)
            const EmptyState(
              icon: Icons.phone_android_rounded,
              title: 'Home screen',
              message: 'Using wallp as your home screen needs Android.',
            )
          else ...[
            _HomeScreenCard(
              isDefault: _isDefaultHome,
              onPressed: widget.launcher.requestDefaultHome,
            ),
            const SizedBox(height: 16),
            _LockClockCard(value: _lockClock, onChanged: _setLockClock),
          ],
        ],
      ),
    );
  }
}

class _HomeScreenCard extends StatelessWidget {
  const _HomeScreenCard({required this.isDefault, required this.onPressed});

  /// Null while checking.
  final bool? isDefault;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final on = isDefault ?? false;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                on ? Icons.check_circle_rounded : Icons.home_rounded,
                color: AppColors.brand,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('wallp Home', style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            on
                ? 'wallp is your home screen. Every app icon follows the '
                      'theme you apply.'
                : 'Use wallp as your home screen so every app icon matches '
                      'your theme, not just the wallpaper.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: on ? 'Change home app' : 'Set as home screen',
            icon: Icons.home_rounded,
            onPressed: isDefault == null ? null : onPressed,
          ),
        ],
      ),
    );
  }
}

class _LockClockCard extends StatelessWidget {
  const _LockClockCard({required this.value, required this.onChanged});

  /// Null while loading.
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_clock_rounded, color: AppColors.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Themed lock screen clock',
                  style: text.titleMedium,
                ),
              ),
              Switch(
                value: value ?? false,
                onChanged: value == null ? null : onChanged,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              "With the live wallpaper on, shows the time in your theme's "
              "font on the lock screen. Your phone's own clock still shows "
              "at the top; Android doesn't let apps change it.",
              style: text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the current theme card before any theme is applied.
class _NoThemeCard extends StatelessWidget {
  const _NoThemeCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.palette_outlined, color: AppColors.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No theme applied yet. Pick one in Explore and apply it.',
              style: text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
