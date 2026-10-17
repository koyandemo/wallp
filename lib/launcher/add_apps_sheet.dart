import 'package:flutter/material.dart';

import '../models/phone_theme.dart';
import '../services/icon_pack_service.dart';
import 'launcher_icon.dart';

/// Pick several apps to put on the home screen. Returns their packages,
/// or null if dismissed.
Future<List<String>?> showAddAppsSheet(
  BuildContext context, {
  required List<InstalledApp> apps,
  required PhoneTheme theme,
  required Color accent,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        _AddAppsSheet(apps: apps, theme: theme, accent: accent),
  );
}

class _AddAppsSheet extends StatefulWidget {
  const _AddAppsSheet({
    required this.apps,
    required this.theme,
    required this.accent,
  });

  final List<InstalledApp> apps;
  final PhoneTheme theme;
  final Color accent;

  @override
  State<_AddAppsSheet> createState() => _AddAppsSheetState();
}

class _AddAppsSheetState extends State<_AddAppsSheet> {
  final _picked = <String>[];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Add to home screen', style: text.titleMedium),
                ),
                FilledButton(
                  onPressed: _picked.isEmpty
                      ? null
                      : () => Navigator.pop(context, _picked),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor:
                        ThemeData.estimateBrightnessForColor(widget.accent) ==
                            Brightness.light
                        ? Colors.black
                        : Colors.white,
                  ),
                  child: Text(
                    _picked.isEmpty ? 'Add' : 'Add ${_picked.length}',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.apps.isEmpty
                ? Center(
                    child: Text(
                      'Every app is already on your home screen',
                      style: text.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    itemCount: widget.apps.length,
                    itemBuilder: (context, i) {
                      final app = widget.apps[i];
                      final picked = _picked.contains(app.packageName);
                      return CheckboxListTile(
                        value: picked,
                        activeColor: widget.accent,
                        onChanged: (_) => setState(
                          () => picked
                              ? _picked.remove(app.packageName)
                              : _picked.add(app.packageName),
                        ),
                        secondary: LauncherIcon(
                          app: app,
                          theme: widget.theme,
                          accent: widget.accent,
                          size: 44,
                        ),
                        title: Text(
                          app.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: widget.theme.appNameStyle(
                            const TextStyle(fontSize: 16),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
