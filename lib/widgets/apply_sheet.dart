import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/wallpaper_target.dart';

/// Asks where to apply the wallpaper. Returns null if dismissed.
Future<WallpaperTarget?> showApplySheet(BuildContext context) {
  return showModalBottomSheet<WallpaperTarget>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'Set wallpaper on',
                  style: text.titleMedium?.copyWith(fontSize: 18),
                ),
              ),
              for (final target in WallpaperTarget.values)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Icon(target.icon, color: AppColors.brand),
                  title: Text(target.label, style: text.titleMedium),
                  onTap: () => Navigator.pop(context, target),
                ),
            ],
          ),
        ),
      );
    },
  );
}
