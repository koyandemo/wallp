import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'dart:ui' as ui;

import '../models/phone_theme.dart';
import '../render/layers_painter.dart';
import '../render/scene_assets.dart';
import 'christmas_scene.dart';
import 'halloween_scene.dart';
import 'placeholder_scene.dart';
import 'scene_painter.dart';
import 'thingyan_scene.dart';

/// The painter that draws [theme]'s scene, or null if it has none.
/// A layered scene's [images] are its decoded pictures (by sha256).
ScenePainter? scenePainterFor(
  PhoneTheme theme,
  ValueListenable<double> time,
  Color accent, {
  Map<String, ui.Image> images = const {},
}) {
  if (theme.layered case final layered?) {
    return LayersPainter(
      time: time,
      accent: accent,
      scene: layered,
      images: images,
    );
  }
  return switch (theme.scene) {
    SceneKind.halloween => HalloweenPainter(time: time, accent: accent),
    SceneKind.christmas => ChristmasPainter(time: time, accent: accent),
    SceneKind.thingyan => ThingyanPainter(time: time, accent: accent),
    null => null,
  };
}

/// A theme's painted wallpaper, animated when [animate] is true.
///
/// Stops animating when the system asks for reduced motion.
class SceneView extends StatefulWidget {
  const SceneView({
    super.key,
    required this.theme,
    this.animate = false,
    this.accent,
    this.maxFps,
  });

  final PhoneTheme theme;
  final bool animate;

  /// Caps the frame rate (live wallpaper: 30) by driving the animation from
  /// a timer instead of every display frame. The timer stops while the app
  /// is paused, e.g. when the wallpaper is hidden.
  final int? maxFps;

  /// Overrides the theme's default accent (user pick, Step 5).
  final Color? accent;

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _time = ValueNotifier<double>(kSceneStillTime);
  late final Ticker _ticker = createTicker(
    (elapsed) => _time.value = kSceneStillTime + elapsed.inMicroseconds / 1e6,
  );

  /// Capped-rate driver (when [SceneView.maxFps] is set).
  Timer? _timer;
  final _clock = Stopwatch();
  bool _appVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(SceneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final run = widget.animate && !reduceMotion;
    final fps = widget.maxFps;
    if (fps == null) {
      _stopTimer();
      if (run && !_ticker.isActive) _ticker.start();
      if (!run && _ticker.isActive) _ticker.stop();
      return;
    }
    if (_ticker.isActive) _ticker.stop();
    if (run && _appVisible) {
      _timer ??= Timer.periodic(
        Duration(microseconds: 1000000 ~/ fps),
        (_) => _time.value = kSceneStillTime + _clock.elapsedMicroseconds / 1e6,
      );
      _clock.start();
    } else {
      _stopTimer();
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  /// A layered scene's pictures, once loaded from the phone.
  Map<String, ui.Image> _images = const {};
  Object? _imagesFor;

  void _loadImages() {
    final layered = widget.theme.layered;
    if (layered == null || identical(_imagesFor, layered)) return;
    _imagesFor = layered;
    final refs = layered.images.toList();
    if (refs.isEmpty) return;
    SceneAssets.of(context).images(refs).then((images) {
      if (mounted && identical(_imagesFor, layered)) {
        setState(() => _images = images);
      }
    });
  }

  ScenePainter? _painter() => scenePainterFor(
    widget.theme,
    _time,
    widget.accent ?? widget.theme.palette.accent,
    images: _images,
  );

  @override
  Widget build(BuildContext context) {
    _loadImages();
    final painter = _painter();
    if (painter == null) return PlaceholderScene(theme: widget.theme);
    return RepaintBoundary(
      child: CustomPaint(painter: painter, size: Size.infinite),
    );
  }
}
