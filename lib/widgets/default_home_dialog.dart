import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../icons/themed_icon_painter.dart';
import '../models/phone_theme.dart';

/// "Set wallp as your home app?" — shown before applying a theme when wallp
/// isn't the default home app yet. True = go ahead, false/null = cancel.
Future<bool?> showDefaultHomeDialog(
  BuildContext context, {
  required PhoneTheme theme,
  required Color accent,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final glyph in const [
              Icons.phone_rounded,
              Icons.chat_bubble_rounded,
              Icons.photo_camera_rounded,
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                // Dashboard themes have downloaded icons, not painted ones.
                child: theme.iconStyle == null
                    ? Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: theme.palette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: accent, width: 2),
                        ),
                        child: Icon(glyph, color: accent, size: 26),
                      )
                    : ThemedIcon(
                        style: theme.iconStyle!,
                        accent: accent,
                        glyph: glyph,
                        size: 52,
                      ),
              ),
          ],
        ),
        title: Text(
          'Set wallp as your home app?',
          textAlign: TextAlign.center,
          style: text.titleMedium?.copyWith(fontSize: 20),
        ),
        content: Text(
          '${theme.name} changes your wallpaper and every app icon. '
          'To show the themed icons, wallp needs to be your default home '
          'app. You can switch back any time in Settings.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: AppColors.onColor(accent),
            ),
            child: const Text('Set as home app'),
          ),
        ],
      );
    },
  );
}
