import 'package:flutter/material.dart';

import '../services/icon_pack_service.dart';

/// Which apps sit in the dock and on the home grid.
class HomeLayout {
  const HomeLayout({required this.dock, required this.home});

  final List<InstalledApp> dock;
  final List<InstalledApp> home;

  static const homeSlots = 12;

  /// Dock: phone, messages, browser, camera (when installed).
  static const _dockGlyphs = [
    Icons.phone_rounded,
    Icons.chat_bubble_rounded,
    Icons.public_rounded,
    Icons.photo_camera_rounded,
  ];

  /// Home grid: well-known apps in this order, then the rest alphabetically.
  static const _homeGlyphs = [
    Icons.forum_rounded,
    Icons.photo_rounded,
    Icons.play_arrow_rounded,
    Icons.map_rounded,
    Icons.mail_rounded,
    Icons.calendar_month_rounded,
    Icons.schedule_rounded,
    Icons.music_note_rounded,
    Icons.music_video_rounded,
    Icons.camera_rounded,
    Icons.thumb_up_rounded,
    Icons.shop_rounded,
    Icons.settings_rounded,
    Icons.calculate_rounded,
    Icons.cloud_rounded,
    Icons.folder_rounded,
  ];

  /// A sensible first layout until the user arranges their own (L2).
  factory HomeLayout.suggested(List<InstalledApp> apps) {
    final dock = <InstalledApp>[
      for (final glyph in _dockGlyphs)
        ?apps.where((a) => a.glyph == glyph).firstOrNull,
    ];
    final rest = apps.where((a) => !dock.contains(a)).toList();

    int rank(InstalledApp app) {
      final i = _homeGlyphs.indexOf(app.glyph ?? Icons.apps);
      return i == -1 ? _homeGlyphs.length : i;
    }

    // Stable sort: by rank, keeping the alphabetical order within a rank.
    final indexed = rest.indexed.toList()
      ..sort((a, b) {
        final byRank = rank(a.$2).compareTo(rank(b.$2));
        return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
      });
    return HomeLayout(
      dock: dock,
      home: indexed.map((e) => e.$2).take(homeSlots).toList(),
    );
  }
}
