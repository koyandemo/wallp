import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../catalog/catalog.dart';
import '../../core/app_colors.dart';
import '../../core/clock.dart';
import '../../core/date_format.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../look/look_controller.dart';
import '../../models/phone_theme.dart';
import '../../scenes/scene_view.dart';
import '../logic/previews.dart';
import '../logic/queries.dart';

/// "Now" for the store: the real time, or Developer settings' pretend date.
DateTime nowOf(BuildContext context) => context.read<Clock>().now();

Catalog catalogOf(BuildContext context) =>
    context.watch<CatalogRepository>().catalog;

/// The applied theme's ID, for APPLIED badges.
String? appliedIdOf(BuildContext context) {
  final looks = context.watch<LookController>();
  return looks.isApplied ? looks.look?.theme.id : null;
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// A row of filter chips, one selected: a radio group, as in the design.
class ChipRow<T> extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// For screen readers: "Filter themes".
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      container: true,
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: options.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final (key, text) = options[i];
            final on = key == value;
            return Semantics(
              inMutuallyExclusiveGroup: true,
              checked: on,
              button: true,
              child: Material(
                color: on ? AppColors.textPrimary : AppColors.surface,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: on ? AppColors.textPrimary : AppColors.outline,
                  ),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onChanged(key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: on
                              ? AppColors.background
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class BadgeChip extends StatelessWidget {
  const BadgeChip(this.badge, {super.key});

  final CardBadge badge;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (badge) {
      CardBadge.applied ||
      CardBadge.inUse => (AppColors.brand, AppColors.background),
      CardBadge.isNew => (AppColors.textPrimary, AppColors.background),
      CardBadge.live => (AppColors.background, AppColors.textPrimary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge == CardBadge.applied || badge == CardBadge.inUse) ...[
            Icon(Icons.check_rounded, size: 11, color: fg),
            const SizedBox(width: 3),
          ],
          if (badge == CardBadge.live) ...[
            Icon(Icons.play_arrow_rounded, size: 11, color: fg),
            const SizedBox(width: 2),
          ],
          Text(
            badge.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// A theme's scene in a rounded frame, with its clock on top: the cards in
/// the design. [highlight] draws the brand border (applied / in use).
class SceneThumb extends StatelessWidget {
  const SceneThumb({
    super.key,
    required this.theme,
    this.badge,
    this.highlight = false,
    this.radius = 22,
    this.showClock = true,
    this.animate = false,
  });

  final PhoneTheme theme;
  final CardBadge? badge;
  final bool highlight;
  final double radius;
  final bool showClock;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final accent = theme.palette.accent;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: highlight ? AppColors.brand : Colors.transparent,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            SceneView(theme: theme, accent: accent, animate: animate),
            if (showClock)
              Positioned(
                left: 0,
                right: 0,
                // Below the badge, so it never covers the date.
                top: badge == null ? 18 : 36,
                child: Column(
                  children: [
                    Text(
                      DateFormatX.shortDate(nowOf(context)),
                      style: theme.bodyStyle(
                        TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: theme.palette.text,
                        ),
                      ),
                    ),
                    Text(
                      DateFormatX.clock(
                        nowOf(context),
                        // Like the lock screen: the phone's own setting.
                        use24h: MediaQuery.alwaysUse24HourFormatOf(context),
                      ),
                      style: theme.displayStyle(
                        TextStyle(
                          fontSize: 36,
                          height: 1.05,
                          color: theme.accentClock
                              ? accent
                              : theme.palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (badge case final b?)
              Positioned(right: 8, top: 8, child: BadgeChip(b)),
          ],
        ),
      ),
    );
  }
}

/// A theme in a grid or row: picture, name, a line about it.
class ThemeCard extends StatelessWidget {
  const ThemeCard({
    super.key,
    required this.theme,
    required this.onTap,
    this.subtitle,
    this.height = 290,
  });

  final ThemeSummary theme;
  final VoidCallback onTap;
  final String? subtitle;
  final double height;

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final now = nowOf(context);
    final applied = appliedIdOf(context);
    final badge = themeBadge(theme, appliedId: applied, now: now);
    final festival = catalog.festival(theme.festivalId);
    final line =
        subtitle ??
        (festival == null
            ? ''
            : '${festival.name.en} · ${festival.countdown(now).label()}');
    return Semantics(
      button: true,
      label:
          '${theme.name.en}, $line${badge == null ? '' : ', ${badge.label.toLowerCase()}'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: height,
              child: SceneThumb(
                theme: previewOf(theme, catalog, now),
                badge: badge,
                highlight: badge == CardBadge.applied,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              theme.name.en,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WallpaperCard extends StatelessWidget {
  const WallpaperCard({
    super.key,
    required this.wallpaper,
    required this.onTap,
    this.inUseId,
  });

  final Wallpaper wallpaper;
  final VoidCallback onTap;
  final String? inUseId;

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final badge = wallpaperBadge(wallpaper, inUseId: inUseId);
    final festival = catalog.festival(wallpaper.festivalId)?.name.en ?? '';
    return Semantics(
      button: true,
      label:
          '${wallpaper.name.en}, $festival${wallpaper.isLive ? ', live wallpaper' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 290,
              child: SceneThumb(
                theme: wallpaperPreviewOf(wallpaper, catalog, nowOf(context)),
                badge: badge,
                highlight: badge == CardBadge.inUse,
                radius: 20,
                showClock: false,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    wallpaper.name.en,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  festival,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brand,
                minimumSize: const Size(44, 44),
              ),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A tab's header: big title and a count line, with optional actions.
class TabHeader extends StatelessWidget {
  const TabHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// The round outlined icon buttons in tab headers (Search, Sort).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.text,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: AppColors.surface,
          shape: const StadiumBorder(
            side: BorderSide(color: AppColors.outline),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onPressed,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: text == null ? 12 : 14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: AppColors.textPrimary),
                    if (text != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        text!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
