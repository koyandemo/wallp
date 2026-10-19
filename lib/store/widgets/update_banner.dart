import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/store_palette.dart';
import '../../data/catalog/catalog_repository.dart';

/// "A newer wallp is out", when the server asks for a newer app or hides
/// themes this build can't show (docs/app-client.md §2 steps 3 and 10).
/// Soft: everything keeps working, and Later hides it until the next
/// launch.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  /// Later was tapped this run.
  static final dismissed = ValueNotifier(false);

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<CatalogRepository>();
    final hidden = repo.hiddenForUpdate;
    return ValueListenableBuilder(
      valueListenable: dismissed,
      builder: (context, isDismissed, _) {
        if (isDismissed || !(repo.updateRecommended || hidden > 0)) {
          return const SizedBox.shrink();
        }
        final palette = context.palette;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.outline),
            ),
            child: Row(
              children: [
                Icon(Icons.system_update_rounded, color: palette.brand),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A newer wallp is out',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hidden > 0
                            ? 'Update to see $hidden more '
                                  '${hidden == 1 ? 'theme' : 'themes'}.'
                            : 'Update to get the newest themes.',
                        style: TextStyle(fontSize: 13, color: palette.muted),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => dismissed.value = true,
                  child: const Text('Later'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
