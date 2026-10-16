import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/date_format.dart';
import '../scenes/scene_view.dart';
import '../services/my_themes.dart';

/// Wide card for the applied theme, over its animated scene.
class CurrentThemeCard extends StatelessWidget {
  const CurrentThemeCard({
    super.key,
    required this.entry,
    required this.now,
    required this.onTap,
  });

  final AppliedEntry entry;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = entry.theme;
    final p = theme.palette;
    final label = Theme.of(context).textTheme.labelSmall;
    return Semantics(
      button: true,
      label: 'Applied: ${theme.name}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 180,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SceneView(theme: theme, animate: true, accent: entry.accent),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      p.background.withValues(alpha: 0.95),
                      p.background.withValues(alpha: 0.5),
                      p.background.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ON YOUR PHONE',
                      style: label?.copyWith(color: p.textMuted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      theme.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.displayStyle(
                        TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          color: entry.accent,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        AccentDot(color: entry.accent),
                        const SizedBox(width: 8),
                        Text(
                          'Applied ${DateFormatX.ago(entry.appliedAt, now).toLowerCase()}',
                          style: theme.bodyStyle(
                            TextStyle(fontSize: 14, color: p.text),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small circle in a theme's accent color.
class AccentDot extends StatelessWidget {
  const AccentDot({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.outline, width: 2),
    ),
  );
}
