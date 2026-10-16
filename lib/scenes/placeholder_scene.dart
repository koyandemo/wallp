import 'package:flutter/material.dart';

import '../models/phone_theme.dart';

/// Gradient + glow stand-in for themes whose painted scene isn't built yet.
class PlaceholderScene extends StatelessWidget {
  const PlaceholderScene({super.key, required this.theme});

  final PhoneTheme theme;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p.background, p.deep],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 45,
            top: 400,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    p.accent.withValues(alpha: 0.45),
                    p.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 120,
            child: Column(
              children: [
                Text(
                  theme.name,
                  textAlign: TextAlign.center,
                  style: theme.displayStyle(
                    TextStyle(fontSize: 48, color: p.accent, height: 1.1),
                  ),
                ),
                if (theme.subtitle != null)
                  Text(
                    theme.subtitle!,
                    style: theme.bodyStyle(
                      TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
