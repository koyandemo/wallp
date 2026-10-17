import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../catalog/catalog.dart';
import '../core/clock.dart';
import '../data/assets/download_manager.dart';
import '../data/catalog/catalog_repository.dart';
import '../look/applied_look.dart';
import '../look/look_controller.dart';
import '../look/resolved_look.dart';
import '../models/phone_theme.dart';
import '../models/wallpaper_target.dart';
import '../services/launcher_service.dart';
import '../services/wallpaper_service.dart';
import '../widgets/apply_sheet.dart';
import '../widgets/default_home_dialog.dart';
import 'state/live_wallpaper_status.dart';
import 'state/user_store.dart';
import 'widgets/common.dart';

/// Every apply the store's screens make, start to finish:
///
/// 1. A whole theme needs wallp as the home app (its icons and clock live
///    there). If it isn't, ask; Android may then jump straight to wallp
///    Home, so the look is saved as pending first and wallp Home finishes.
/// 2. Download everything (the progress card shows), then apply: all or
///    nothing (LookController).
/// 3. Put the wallpaper on the system: home, lock, both, or the animated
///    live wallpaper.
/// 4. Say what happened, in words the user can act on.
class ApplyFlow {
  const ApplyFlow({
    this.launcher = const LauncherService(),
    this.wallpapers = const WallpaperService(),
  });

  final LauncherService launcher;
  final WallpaperService wallpapers;

  Future<void> applyTheme(
    BuildContext context,
    ThemeDetail theme, {
    ApplyOption option = ApplyOption.wholeTheme,
    String? variantId,
    Accent? accent,
  }) async {
    final looks = context.read<LookController>();
    final user = context.read<UserStore>();
    final clock = context.read<Clock>();
    final name = theme.name.en;

    if (option == ApplyOption.wholeTheme) {
      final ok = await _ensureHomeApp(context, () async {
        // Downloads happen here, before Android leaves this app.
        await looks.applyTheme(
          theme.id,
          variantId: variantId,
          accent: accent,
          asPending: true,
        );
      }, preview: () => _preview(context, theme, variantId, accent));
      if (ok == null || !context.mounted) return;
    }

    final AppliedLook look;
    try {
      look = await looks.applyTheme(
        theme.id,
        option: option,
        variantId: variantId,
        accent: accent,
      );
    } on Object catch (e) {
      if (context.mounted) showToast(context, failureMessage(e, name));
      return;
    }
    if (option == ApplyOption.wholeTheme) {
      await user.recordApplied(theme.id, clock.now());
    }
    if (!context.mounted) return;

    if (option == ApplyOption.clockFontOnly) {
      showToast(context, '${look.clockFont.family} clock font applied');
      return;
    }
    final wallpaperMessage = await _setWallpaper(context, look);
    if (!context.mounted) return;
    showToast(
      context,
      option == ApplyOption.wholeTheme
          ? '$name applied to wallp Home${wallpaperMessage == null ? '' : '. $wallpaperMessage'}'
          : wallpaperMessage ?? '$name wallpaper chosen',
    );
  }

  Future<void> applyWallpaper(BuildContext context, Wallpaper wallpaper) async {
    final looks = context.read<LookController>();
    final AppliedLook look;
    try {
      look = await looks.applyWallpaper(wallpaper.id);
    } on Object catch (e) {
      if (context.mounted) {
        showToast(context, failureMessage(e, wallpaper.name.en));
      }
      return;
    }
    if (!context.mounted) return;
    final message = await _setWallpaper(context, look);
    if (context.mounted) {
      showToast(context, message ?? '${wallpaper.name.en} chosen');
    }
  }

  Future<void> applyFont(
    BuildContext context,
    CatalogFont font, {
    ClockSize? size,
    ClockColor? color,
    ClockPlaces? places,
  }) async {
    try {
      await context.read<LookController>().applyClockFont(
        font.id,
        size: size,
        color: color,
        places: places,
      );
      if (context.mounted) showToast(context, '${font.family} applied');
    } on Object catch (e) {
      if (context.mounted) showToast(context, failureMessage(e, font.family));
    }
  }

  Future<void> applyIconPack(
    BuildContext context,
    IconPack pack, {
    IconShape? shape,
    LabelColor? labels,
    LabelFont? labelFont,
  }) async {
    try {
      await context.read<LookController>().applyIconPack(
        pack.id,
        shape: shape,
        labels: labels,
        labelFont: labelFont,
      );
      if (context.mounted) {
        showToast(context, '${pack.name.en} icons applied to wallp Home');
      }
    } on Object catch (e) {
      if (context.mounted) showToast(context, failureMessage(e, pack.name.en));
    }
  }

  /// What went wrong, for a toast.
  static String failureMessage(Object error, String name) => switch (error) {
    DownloadFailedException() => error.message,
    DownloadCancelledException() => 'Download of $name cancelled',
    ThemeUnavailableException(isOffline: true) =>
      "Couldn't open $name. Check your connection.",
    _ => "Couldn't apply $name. Try again.",
  };

  _HomeDialogPreview _preview(
    BuildContext context,
    ThemeDetail theme,
    String? variantId,
    Accent? accent,
  ) {
    final repo = context.read<CatalogRepository>();
    final now = context.read<Clock>().now();
    final look = AppliedLook.wholeTheme(
      repo.catalog,
      theme,
      at: now,
      variantId: variantId,
      accent: accent,
    );
    final r = ResolvedLook.of(look, now);
    return (theme: r.homeTheme, accent: r.accent);
  }

  /// True: go on applying. Null: stop (declined, or Android didn't make
  /// wallp the home app; the user is told why).
  Future<bool?> _ensureHomeApp(
    BuildContext context,
    Future<void> Function() savePending, {
    required _HomeDialogPreview Function() preview,
  }) async {
    if (!LauncherService.isSupported || await launcher.isDefaultHome()) {
      return true;
    }
    if (!context.mounted) return null;
    final p = preview();
    final confirmed = await showDefaultHomeDialog(
      context,
      theme: p.theme,
      accent: p.accent,
    );
    if (confirmed != true || !context.mounted) return null;
    final looks = context.read<LookController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await savePending();
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(e, 'this theme'))),
      );
      return null;
    }
    final isDefault = await launcher.requestDefaultHome();
    // Back here: wallp Home didn't take over the apply, so this screen
    // finishes it (or it was declined).
    await looks.clearPending();
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
      return null;
    }
    return true;
  }

  /// Asks where, sets it, and returns what to tell the user (null if they
  /// closed the sheet).
  ///
  /// "Live wallpaper" goes straight to the live wallpaper: if it's already
  /// on, it redraws with the new look by itself; if not, the system
  /// preview opens at once.
  Future<String?> _setWallpaper(BuildContext context, AppliedLook look) async {
    final status = context.read<LiveWallpaperStatus?>();
    final target = WallpaperService.canSetDirectly
        ? await showApplySheet(context)
        : WallpaperTarget.both;
    if (target == null || !context.mounted) return null;
    final now = context.read<Clock>().now();
    final resolved = ResolvedLook.of(look, now);
    if (target == WallpaperTarget.live) {
      if (await wallpapers.isLiveWallpaperActive()) {
        return 'Live wallpaper updated';
      }
      final outcome = await wallpapers.openLiveWallpaper();
      status?.refresh();
      return switch (outcome) {
        LivePickerResult.set => 'Live wallpaper on',
        LivePickerResult.cancelled => 'Live wallpaper not set',
        LivePickerResult.unavailable =>
          "This phone didn't open the live wallpaper picker",
      };
    }
    if (!context.mounted) return null;
    final pixels = View.of(context).physicalSize;
    try {
      final result = await wallpapers.apply(
        theme: resolved.wallpaperTheme,
        accent: resolved.wallpaperAccent,
        target: target,
        fallbackPixelSize: pixels,
      );
      // A still picture replaces the live wallpaper.
      status?.refresh();
      return switch (result) {
        ApplyResult.applied => 'Wallpaper set on ${target.label.toLowerCase()}',
        ApplyResult.savedToPhotos =>
          'Saved to Photos. Set it in Settings › Wallpaper',
      };
    } on WallpaperException catch (e) {
      return e.message;
    }
  }
}

typedef _HomeDialogPreview = ({PhoneTheme theme, Color accent});
