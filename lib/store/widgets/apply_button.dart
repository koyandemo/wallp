import 'package:flutter/material.dart';

import '../../core/store_palette.dart';

/// What an [ApplyButton] shows, and so which icon it carries.
enum ApplyState { ready, download, applying, applied }

/// The full-width floating Apply, in the brand colour, like Set wallpaper. Its icon follows
/// [state]: download when assets are missing, a spinner while applying, a
/// tick once applied.
class ApplyButton extends StatelessWidget {
  const ApplyButton({
    super.key,
    required this.state,
    required this.label,
    required this.onPressed,
  });

  final ApplyState state;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = context.palette.brand;
    final foreground = context.palette.onBrand;
    final Widget icon = state == ApplyState.applying
        ? SizedBox.square(
            key: const ValueKey(ApplyState.applying),
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: foreground,
            ),
          )
        : Icon(switch (state) {
            ApplyState.applied => Icons.check_circle_rounded,
            ApplyState.download => Icons.download_rounded,
            _ => Icons.auto_awesome_rounded,
          }, key: ValueKey(state));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          onPressed: state == ApplyState.applying ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: foreground,
            // Stays in the brand colour while applying, so it doesn't flash grey.
            disabledBackgroundColor: accent,
            disabledForegroundColor: foreground,
            elevation: 6,
            shadowColor: accent.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: icon,
          ),
          label: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
