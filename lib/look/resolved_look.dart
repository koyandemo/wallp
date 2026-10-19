import 'package:flutter/material.dart';

import '../catalog/catalog.dart';
import '../models/phone_theme.dart';
import '../render/image_icons.dart';
import '../render/layered_scene.dart';
import 'accent_contrast.dart';
import 'accent_paint.dart';
import 'applied_look.dart';
import 'event_icons.dart';

/// An [AppliedLook] turned into what today's renderers draw: a [PhoneTheme]
/// per screen and plain colours.
///
/// This is the bridge until Phase 6 teaches the renderers the catalog
/// format. Each screen gets its own PhoneTheme because the clock font can
/// be on the lock screen but not wallp Home (or only on app labels), and
/// the wallpaper can come from a different theme than the icons.
class ResolvedLook {
  ResolvedLook._({
    required this.look,
    required this.lockTheme,
    required this.homeTheme,
    required this.wallpaperTheme,
    required this.accent,
    required this.wallpaperAccent,
    required this.clockColor,
    required this.accentGradient,
    required this.clockGradient,
    required this.onAccent,
  });

  factory ResolvedLook.of(AppliedLook look, DateTime now) {
    final accent = _color(look.accent.primary);
    final theme = phoneThemeOf(
      look.theme,
      look.festival,
      look.fonts,
      now: now,
      variantId: look.variantId,
      accent: look.accent,
    );
    final clockFamily = look.clockFont.family;
    final places = look.clock.places;
    final labelsFamily = look.fonts[look.theme.fonts.labels]!.family;

    final pack = look.icons.pack;
    final iconStyle = pack.kind == IconPackKind.painted
        ? SceneKind.values.asNameMap()[pack.painter]
        : null;

    final choice = look.wallpaper;
    final PhoneTheme wallpaperTheme;
    final Color wallpaperAccent;
    if (choice.theme case final other?) {
      wallpaperTheme = phoneThemeOf(
        other,
        look.festival,
        look.fonts,
        now: now,
        variantId: choice.variantId,
        accent: choice.accent,
      );
      wallpaperAccent = _color(choice.accent!.primary);
    } else if (choice.wallpaper case final w?) {
      wallpaperTheme = wallpaperPhoneTheme(w, theme);
      wallpaperAccent = accent;
    } else {
      wallpaperTheme = theme;
      wallpaperAccent = accent;
    }

    final clockColorChoice = look.clock.color;
    return ResolvedLook._(
      look: look,
      accentGradient: look.accent.gradient,
      clockGradient: clockColorChoice.isAccent ? look.accent.gradient : null,
      onAccent: _color(labelOn(look.accent)),
      lockTheme: places.lockScreen
          ? theme.copyWith(displayFont: clockFamily)
          : theme,
      homeTheme: theme.copyWith(
        displayFont: places.homeClock ? clockFamily : null,
        bodyFont: places.appLabels ? clockFamily : labelsFamily,
        labelFont: places.appLabels ? clockFamily : labelsFamily,
        hasIconPack: iconStyle != null,
        iconStyle: iconStyle,
        imageIcons: pack.kind == IconPackKind.images
            ? ImageIconPack.of(pack, look.icons.shape)
            : null,
        appPictures: PackAppPictures.of(pack),
        iconShape: look.icons.shape,
        labelColor: switch (look.icons.labels) {
          final l when l.isAccent => accent,
          final l when l.hex != null => _color(l.hex!),
          _ => theme.labelColor,
        },
        systemLabels: look.icons.labelFont == LabelFont.system,
      ),
      wallpaperTheme: wallpaperTheme,
      accent: accent,
      wallpaperAccent: wallpaperAccent,
      clockColor: switch (look.clock.color) {
        final c when c.isAccent => accent,
        final c when c.isText => theme.palette.text,
        final c => _color(c.hex!),
      },
    );
  }

  final AppliedLook look;

  /// For the live wallpaper's lock screen clock and countdown.
  final PhoneTheme lockTheme;

  /// For wallp Home: clock, labels and icons.
  final PhoneTheme homeTheme;

  /// For the scene on the wallpaper.
  final PhoneTheme wallpaperTheme;

  /// The accent's main colour. Gradients draw as this until Phase 6.
  final Color accent;
  final Color wallpaperAccent;
  final Color clockColor;

  /// The accent as a gradient; null for a solid accent.
  final Gradient? accentGradient;

  /// Set when the clock is drawn in a gradient accent.
  final Gradient? clockGradient;

  /// Icons and text on an accent fill: dark on light accents.
  final Color onAccent;

  double get clockScale => look.clock.size.scale;
}

Color _color(HexColor c) => Color(c.argb);

/// [theme] as the old [PhoneTheme], with [variantId]'s colours and
/// [accent] first among its accent options.
PhoneTheme phoneThemeOf(
  ThemeDetail theme,
  Festival festival,
  Map<String, CatalogFont> fonts, {
  required DateTime now,
  String? variantId,
  Accent? accent,
}) {
  final p = theme.paletteFor(variantId);
  final first = accent ?? theme.defaultAccent;
  final options = <Color>[
    _color(first.primary),
    for (final a in theme.accents)
      if (a.primary != first.primary) _color(a.primary),
  ];
  String family(String id) => fonts[id]?.family ?? 'Space Grotesk';
  return PhoneTheme(
    id: theme.id,
    categoryId: theme.festivalId,
    name: theme.name.en,
    subtitle: theme.subtitle?.en,
    scene: SceneKind.values.asNameMap()[theme.scene.engine],
    palette: ThemePalette(
      background: _color(p.background),
      deep: _color(p.deep),
      surface: _color(p.surface),
      text: _color(p.text),
      textMuted: _color(p.textMuted),
      accentOptions: options,
    ),
    displayFont: family(theme.fonts.display),
    bodyFont: family(theme.fonts.body),
    labelFont: family(theme.fonts.labels),
    event: eventOf(festival, now),
    eventIcon: eventIconFor(theme.eventIcon),
    accentClock: theme.accentClock,
    labelColor: theme.labelColor == null
        ? Colors.white
        : _color(theme.labelColor!),
    hasIconPack: theme.isBuiltIn,
    layered: theme.scene.layers == null
        ? null
        : LayeredScene(
            layers: theme.scene.layers!,
            tokens: {
              '@background': _color(p.background),
              '@deep': _color(p.deep),
              '@surface': _color(p.surface),
              '@text': _color(p.text),
              '@motif': _color(p.motif ?? p.text),
              '@accent': _color(first.primary),
            },
            accentGradient: first.gradient,
          ),
  );
}

/// The festival's next run as the old fixed-date [ThemeEvent]; on a day it
/// runs (Thingyan lasts 4), today, so the countdown says "Happy …!".
ThemeEvent? eventOf(Festival festival, DateTime now) {
  final run = festival.nextRun(now);
  if (run == null) return null;
  final day = run.isOn(now) ? now : run.start;
  return ThemeEvent(
    name: festival.name.en,
    month: day.month,
    day: day.day,
    unit: festival.unit.name,
  );
}

/// A stand-alone wallpaper as a [PhoneTheme]: its painter or layers, in its
/// own colours; [current] supplies fonts and the countdown.
PhoneTheme wallpaperPhoneTheme(Wallpaper w, PhoneTheme current) {
  final sky = [
    for (final layer in w.scene?.layers ?? const <Layer>[])
      if (layer is GradientLayer)
        for (final c in layer.colors)
          if (!c.isToken) Color(HexColor(c.value).argb),
  ];
  final dominant = w.image?.dominant;
  final top = sky.firstOrNull ?? (dominant == null ? null : _color(dominant));
  final p = current.palette;
  return PhoneTheme(
    id: w.id,
    categoryId: w.festivalId,
    name: w.name.en,
    scene: w.scene == null
        ? null
        : SceneKind.values.asNameMap()[w.scene!.engine],
    palette: ThemePalette(
      background: sky.lastOrNull ?? top ?? p.background,
      deep: top ?? p.deep,
      surface: p.surface,
      text: p.text,
      textMuted: p.textMuted,
      accentOptions: p.accentOptions,
    ),
    displayFont: current.displayFont,
    bodyFont: current.bodyFont,
    event: current.event,
    eventIcon: current.eventIcon,
    // Wallpaper scenes use literal colours only, so no tokens are needed.
    layered: w.scene?.layers == null
        ? null
        : LayeredScene(layers: w.scene!.layers!, tokens: const {}),
  );
}
