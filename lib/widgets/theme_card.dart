import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/phone_theme.dart';
import 'favorite_button.dart';
import 'theme_preview.dart';

/// Grid tile: phone-shaped preview with the theme's name and countdown below.
class ThemeCard extends StatelessWidget {
  const ThemeCard({
    super.key,
    required this.theme,
    required this.now,
    required this.onTap,
  });

  /// Height of the name + countdown block under the preview.
  static const labelHeight = 56.0;

  final PhoneTheme theme;
  final DateTime now;
  final VoidCallback onTap;

  static const _radius = BorderRadius.all(Radius.circular(20));

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      _card(context),
      Positioned(
        top: 6,
        right: 6,
        child: FavoriteButton(theme: theme, onImage: true),
      ),
    ],
  );

  Widget _card(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${theme.name} theme, ${theme.event.countdownLabel(now)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: _radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: _radius,
                  border: Border.all(color: AppColors.outline),
                ),
                child: ClipRRect(
                  borderRadius: _radius,
                  child: ThemePreview(theme: theme, now: now),
                ),
              ),
            ),
            SizedBox(
              height: labelHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      theme.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: theme.palette.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            theme.event.countdownLabel(now),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
