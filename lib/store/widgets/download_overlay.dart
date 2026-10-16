import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../data/assets/download_manager.dart';
import '../logic/queries.dart';

/// The download progress card, above every screen while a download runs:
/// "Downloading Cozy Cabin · 0.4 of 0.8 MB", a bar, and Cancel. Failures
/// and cancels are reported by the apply flow's toast instead.
class DownloadOverlay extends StatelessWidget {
  const DownloadOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final task = context.watch<DownloadManager>().current;
    return Stack(
      children: [
        child,
        if (task != null)
          ListenableBuilder(
            listenable: task,
            builder: (context, _) => !task.isActive
                ? const SizedBox.shrink()
                : Positioned(
                    left: 16,
                    right: 16,
                    bottom: 96,
                    child: SafeArea(child: _Card(task: task)),
                  ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final label =
        'Downloading ${task.label} · ${formatBytes(task.receivedBytes)} of ${formatBytes(task.totalBytes)}';
    return Material(
      color: AppColors.surfaceHigh,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      child: Semantics(
        liveRegion: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: task.progress,
                        minHeight: 6,
                        backgroundColor: AppColors.outline,
                        color: AppColors.brand,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: task.cancel,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  minimumSize: const Size(64, 44),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
