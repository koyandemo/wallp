import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../services/wallpaper_service.dart';

/// Whether wallp's live wallpaper is the phone's wallpaper. Previews only
/// animate when it is: a still wallpaper doesn't move, so neither does its
/// preview.
///
/// Rechecks when the store comes back to the front (the user may have set
/// or replaced the wallpaper elsewhere) and after the live picker closes.
class LiveWallpaperStatus extends ChangeNotifier {
  LiveWallpaperStatus({this._wallpapers = const WallpaperService()}) {
    _lifecycle = AppLifecycleListener(onResume: refresh);
    refresh();
  }

  final WallpaperService _wallpapers;
  late final AppLifecycleListener _lifecycle;
  bool _active = false;
  bool _disposed = false;

  bool get isActive => _active;

  Future<void> refresh() async {
    final active = await _wallpapers.isLiveWallpaperActive();
    if (_disposed || active == _active) return;
    _active = active;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle.dispose();
    super.dispose();
  }
}

/// True when previews should animate (wallp's live wallpaper is on).
/// False without a [LiveWallpaperStatus] above [context].
bool previewsAnimate(BuildContext context) =>
    context.watch<LiveWallpaperStatus?>()?.isActive ?? false;
