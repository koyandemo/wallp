import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/date_format.dart';
import '../models/phone_theme.dart';
import '../scenes/scene_view.dart';

/// Wide hero card for the festival coming up next, over its animated scene.
class NextUpCard extends StatelessWidget {
  const NextUpCard({
    super.key,
    required this.theme,
    required this.now,
    required this.onTap,
  });

  final PhoneTheme theme;
  final DateTime now;
  final VoidCallback onTap;

  static const _radius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final eventDate = theme.event.nextDate(now);
    final labelStyle = Theme.of(context).textTheme.labelSmall;

    return Semantics(
      button: true,
      label: 'Next up: ${theme.name}, ${theme.event.countdownLabel(now)}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: _radius,
        child: SizedBox(
          height: 212,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SceneView(theme: theme, animate: true),
              // Fade the scene out behind the text on the left.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      p.background.withValues(alpha: 0.95),
                      p.background.withValues(alpha: 0.55),
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
                      'NEXT UP',
                      style: labelStyle?.copyWith(color: p.textMuted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      theme.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.displayStyle(
                        TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          color: p.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${theme.event.countdownValue(now)} · '
                      '${DateFormatX.shortDate(eventDate)}',
                      style: theme.bodyStyle(
                        TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Preview',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontSize: 14,
                                  color: AppColors.onColor(p.accent),
                                ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: AppColors.onColor(p.accent),
                          ),
                        ],
                      ),
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
