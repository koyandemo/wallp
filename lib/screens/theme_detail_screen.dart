import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_colors.dart';
import '../models/phone_theme.dart';
import '../models/wallpaper_target.dart';
import '../services/launcher_service.dart';
import '../services/my_themes.dart';
import '../services/wallpaper_service.dart';
import '../widgets/apply_sheet.dart';
import '../widgets/default_home_dialog.dart';
import '../widgets/favorite_button.dart';
import '../widgets/primary_button.dart';
import 'icon_pack_screen.dart';
import '../widgets/live_now.dart';
import '../widgets/theme_preview.dart';

/// Full preview of one theme: swipe Lock / Home / Live, pick an accent, apply.
class ThemeDetailScreen extends StatefulWidget {
  const ThemeDetailScreen({super.key, required this.theme, this.accent});

  final PhoneTheme theme;

  /// Accent to start with; defaults to the one picked last for this theme.
  final Color? accent;

  @override
  State<ThemeDetailScreen> createState() => _ThemeDetailScreenState();
}

class _ThemeDetailScreenState extends State<ThemeDetailScreen> {
  final _pages = PageController(viewportFraction: 0.8);
  int _page = 0;
  late int _accentIndex = _initialAccentIndex();
  bool _applying = false;
  final _wallpapers = const WallpaperService();
  final _launcher = const LauncherService();

  PhoneTheme get _theme => widget.theme;
  Color get _accent => _theme.palette.accentOptions[_accentIndex];

  int _initialAccentIndex() {
    final wanted = widget.accent ?? context.read<MyThemes>().accentFor(_theme);
    final i = _theme.palette.accentOptions.indexOf(wanted);
    return i == -1 ? 0 : i;
  }

  void _pickAccent(int index) {
    setState(() => _accentIndex = index);
    context.read<MyThemes>().rememberAccent(_theme, _accent);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _showPage(int index) {
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void _openIconPack() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IconPackScreen(theme: _theme, accent: _accent),
      ),
    );
  }

  /// A theme is applied only with wallp as the home app (so the icons
  /// change too). Asks first; false means don't apply.
  Future<bool> _ensureHomeApp() async {
    // iOS has no home app to switch to; Apply just saves the wallpaper.
    if (!LauncherService.isSupported) return true;
    if (await _launcher.isDefaultHome()) return true;
    if (!mounted) return false;
    final confirmed = await showDefaultHomeDialog(
      context,
      theme: _theme,
      accent: _accent,
    );
    if (confirmed != true || !mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    final myThemes = context.read<MyThemes>();
    // Android jumps to the new home screen as soon as wallp becomes the home
    // app, so this screen may never see the result. wallp Home applies the
    // pending theme when it starts.
    await myThemes.savePending(_theme, _accent);
    final isDefault = await _launcher.requestDefaultHome();
    // Back here: the apply continues below (or was declined).
    await myThemes.clearPending();
    if (!isDefault) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              "wallp isn't your home app, so the theme wasn't applied",
            ),
          ),
        );
    }
    return isDefault;
  }

  Future<void> _apply() async {
    if (!await _ensureHomeApp() || !mounted) return;

    // iOS can't set wallpapers, so there's no Home / Lock choice to make.
    final target = WallpaperService.canSetDirectly
        ? await showApplySheet(context)
        : WallpaperTarget.both;
    if (target == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final myThemes = context.read<MyThemes>();
    final screenPixels = View.of(context).physicalSize;
    setState(() => _applying = true);
    String message;
    if (target == WallpaperTarget.live) {
      // Record first: the live wallpaper engine reads the applied theme.
      await myThemes.recordApplied(_theme, _accent);
      final opened = await _wallpapers.openLiveWallpaper();
      message = opened
          ? 'Tap "Set wallpaper" to make ${_theme.name} live'
          : "This phone didn't open the live wallpaper picker";
      if (mounted) setState(() => _applying = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    try {
      final result = await _wallpapers.apply(
        theme: _theme,
        accent: _accent,
        target: target,
        fallbackPixelSize: screenPixels,
      );
      // History + the theme wallp Home follows.
      await myThemes.recordApplied(_theme, _accent);
      message = switch (result) {
        ApplyResult.applied => 'Wallpaper set on ${target.label.toLowerCase()}',
        ApplyResult.savedToPhotos =>
          'Saved to Photos. Set it in Settings › Wallpaper',
      };
    } on WallpaperException catch (e) {
      message = e.message;
    }
    if (mounted) setState(() => _applying = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _theme.name,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontSize: 18),
        ),
        centerTitle: true,
        actions: [FavoriteButton(theme: _theme)],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: LiveNow(
                builder: (context, now) => PageView.builder(
                  controller: _pages,
                  itemCount: PhoneScreen.values.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => _PhoneFrame(
                    child: ThemePreview(
                      theme: _theme,
                      now: now,
                      screen: PhoneScreen.values[i],
                      accent: _accent,
                      // Only the visible page animates, to save battery.
                      animate: i == _page,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ScreenTabs(selected: _page, onSelected: _showPage),
            const SizedBox(height: 16),
            _AccentPicker(
              colors: _theme.palette.accentOptions,
              selected: _accentIndex,
              onSelected: _pickAccent,
            ),
            if (_theme.hasIconPack && WallpaperService.canSetDirectly) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openIconPack,
                icon: const Icon(Icons.apps_rounded),
                label: Text('${_theme.name} app icons'),
                style: TextButton.styleFrom(foregroundColor: _accent),
              ),
              const SizedBox(height: 4),
            ] else
              const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PrimaryButton(
                label: WallpaperService.canSetDirectly
                    ? 'Apply'
                    : 'Save to Photos',
                icon: Icons.wallpaper_rounded,
                color: _accent,
                loading: _applying,
                onPressed: _apply,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Rounded phone-shaped frame with a soft shadow.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  static const _radius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Center(
        child: AspectRatio(
          aspectRatio: kSceneSize.width / kSceneSize.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: _radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(borderRadius: _radius, child: child),
          ),
        ),
      ),
    );
  }
}

class _ScreenTabs extends StatelessWidget {
  const _ScreenTabs({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.titleMedium!;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final screen in PhoneScreen.values)
            _TabPill(
              label: screen.label,
              selected: screen.index == selected,
              style: text,
              onTap: () => onSelected(screen.index),
            ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.surfaceHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        elevation: selected ? 1 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            child: Text(
              label,
              style: style.copyWith(
                fontSize: 14,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccentPicker extends StatelessWidget {
  const _AccentPicker({
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final List<Color> colors;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Accent', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 12),
        for (var i = 0; i < colors.length; i++)
          Semantics(
            label: 'Accent color ${i + 1}',
            selected: i == selected,
            button: true,
            child: InkResponse(
              onTap: () => onSelected(i),
              radius: 24,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      width: 2.5,
                      color: i == selected
                          ? AppColors.textPrimary
                          : Colors.transparent,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors[i],
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
