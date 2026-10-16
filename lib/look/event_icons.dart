import 'package:flutter/material.dart';

/// The icons a catalog theme may name as its `eventIcon`
/// (docs/theme-api.md §7.3). Flutter can't make an icon from any string and
/// still drop unused icons from the build, so the list is fixed here; the
/// dashboard offers only these names.
const eventIcons = <String, IconData>{
  'event': Icons.event,
  'nightlight_round': Icons.nightlight_round,
  'card_giftcard_rounded': Icons.card_giftcard_rounded,
  'water_drop_rounded': Icons.water_drop_rounded,
  'light_mode_rounded': Icons.light_mode_rounded,
  'celebration_rounded': Icons.celebration_rounded,
  'local_florist_rounded': Icons.local_florist_rounded,
  'ac_unit_rounded': Icons.ac_unit_rounded,
  'star_rounded': Icons.star_rounded,
  'favorite_rounded': Icons.favorite_rounded,
  'music_note_rounded': Icons.music_note_rounded,
};

/// The icon for [name]; unknown names get the plain calendar icon.
IconData eventIconFor(String name) => eventIcons[name] ?? Icons.event;
