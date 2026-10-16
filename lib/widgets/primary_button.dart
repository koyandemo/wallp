import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Full-width pill button filled with [color] (a theme's accent, or the
/// app's brand amber), with text that stays readable on it.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.brand,
    this.icon,
    this.height = 56,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;
  final double height;

  /// Shows a spinner and ignores taps (without dimming).
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final foreground = AppColors.onColor(color);
    final radius = BorderRadius.circular(height / 2);
    return Opacity(
      opacity: onPressed != null || loading ? 1 : 0.5,
      child: Material(
        color: color,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: loading ? null : onPressed,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading) ...[
                  SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else if (icon != null) ...[
                  Icon(icon, color: foreground, size: 22),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: foreground, fontSize: 17),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
