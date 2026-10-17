import 'package:flutter/material.dart';

import '../../catalog/catalog.dart';
import '../../look/accent_paint.dart';
import '../../look/applied_look.dart';
import '../../look/event_icons.dart';
import '../../look/resolved_look.dart';
import '../../models/phone_theme.dart';
import '../../render/layered_scene.dart';

/// What a theme looks like on a card, from its catalog summary alone (no
/// download): its scene, colours, accent and display font. With [detail]
/// (the full file), variants and every accent work too.
PhoneTheme previewOf(
  ThemeSummary summary,
  Catalog catalog,
  DateTime now, {
  ThemeDetail? detail,
  String? variantId,
  Accent? accent,
}) {
  final festival = catalog.festival(summary.festivalId);
  if (detail != null && festival != null) {
    return phoneThemeOf(
      detail,
      festival,
      {for (final id in detail.fonts.ids) id: ?catalog.font(id)},
      now: now,
      variantId: variantId,
      accent: accent,
    );
  }
  final p = summary.palette;
  final a = accent ?? summary.accent;
  Color c(HexColor h) => Color(h.argb);
  final family = catalog.font(summary.displayFont)?.family ?? 'Sora';
  return PhoneTheme(
    id: summary.id,
    categoryId: summary.festivalId,
    name: summary.name.en,
    subtitle: summary.subtitle?.en,
    scene: SceneKind.values.asNameMap()[summary.scene.engine],
    palette: ThemePalette(
      background: c(p.background),
      deep: c(p.deep),
      surface: c(p.surface),
      text: c(p.text),
      textMuted: c(p.textMuted),
      accentOptions: [a.color],
    ),
    displayFont: family,
    bodyFont: family,
    event: festival == null ? null : eventOf(festival, now),
    eventIcon: eventIconFor('event'),
    hasIconPack: summary.isBuiltIn,
    layered: summary.scene.layers == null
        ? null
        : LayeredScene(
            layers: summary.scene.layers!,
            tokens: {
              '@background': c(p.background),
              '@deep': c(p.deep),
              '@surface': c(p.surface),
              '@text': c(p.text),
              '@motif': c(p.motif ?? p.text),
              '@accent': a.color,
            },
            accentGradient: a.gradient,
          ),
  );
}

/// [preview] with the user's own wallp Home choices from [look]: icon
/// shape, and app name colour and font. "Theme" colour means [preview]'s
/// theme's; "Accent" means [accent], the accent being previewed.
PhoneTheme withUserIcons(PhoneTheme preview, AppliedLook? look, Color accent) {
  if (look == null) return preview;
  final icons = look.icons;
  return preview.copyWith(
    iconShape: icons.shape,
    labelColor: switch (icons.labels) {
      final l when l.isAccent => accent,
      final l when l.hex != null => Color(l.hex!.argb),
      _ => preview.labelColor,
    },
    systemLabels: icons.labelFont == LabelFont.system,
  );
}

/// A stand-alone wallpaper on a card.
PhoneTheme wallpaperPreviewOf(Wallpaper w, Catalog catalog, DateTime now) {
  // Its festival's built-in theme supplies fonts for the placeholder text.
  final host = PhoneTheme(
    id: w.id,
    categoryId: w.festivalId,
    name: w.name.en,
    scene: null,
    palette: const ThemePalette(
      background: Color(0xFF1A1720),
      deep: Color(0xFF0E0C12),
      surface: Color(0xFF26222E),
      text: Color(0xFFF5F1EA),
      textMuted: Color(0xFFA39DAE),
      accentOptions: [Color(0xFFFFB547)],
    ),
    displayFont: 'Sora',
    bodyFont: 'Sora',
    event: null,
  );
  return wallpaperPhoneTheme(w, host);
}
