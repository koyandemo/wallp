import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

import '../models/phone_theme.dart';
import '../models/wallpaper_target.dart';
import 'wallpaper_renderer.dart';

/// What happened when a wallpaper was applied.
enum ApplyResult {
  /// Android: set directly as the wallpaper.
  applied,

  /// iOS: apps can't set wallpapers, so the image went to Photos.
  savedToPhotos,
}

/// How the live wallpaper picker ended.
enum LivePickerResult {
  /// wallp's live wallpaper is on.
  set,

  /// The user left without setting it.
  cancelled,

  /// No picker could be shown on this phone.
  unavailable,
}

/// Failure the UI can show as-is.
class WallpaperException implements Exception {
  const WallpaperException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Renders a theme and sets it as the wallpaper (Android) or saves it to
/// Photos (iOS). Talks to MainActivity.kt over the `wallp/wallpaper` channel.
class WallpaperService {
  const WallpaperService();

  static const _channel = MethodChannel('wallp/wallpaper');

  /// iOS apps can only save to Photos; the user sets it in Settings.
  static bool get canSetDirectly =>
      defaultTargetPlatform == TargetPlatform.android;

  Future<ApplyResult> apply({
    required PhoneTheme theme,
    required ui.Color accent,
    required WallpaperTarget target,
    required ui.Size fallbackPixelSize,
  }) async {
    final size = canSetDirectly ? await _androidScreenSize() : null;
    final png = await WallpaperRenderer.renderPng(
      theme: theme,
      accent: accent,
      pixelSize: size ?? fallbackPixelSize,
    );

    if (canSetDirectly) {
      try {
        await _channel.invokeMethod<bool>('setWallpaper', {
          'bytes': png,
          'target': target.name,
        });
        return ApplyResult.applied;
      } on PlatformException catch (e) {
        throw WallpaperException(e.message ?? "Couldn't set the wallpaper");
      }
    }

    try {
      if (!await Gal.hasAccess(toAlbum: false)) {
        if (!await Gal.requestAccess(toAlbum: false)) {
          throw const WallpaperException(
            'Allow photo access in Settings to save wallpapers',
          );
        }
      }
      await Gal.putImageBytes(png, name: 'wallp_${theme.id}');
      return ApplyResult.savedToPhotos;
    } on GalException catch (e) {
      throw WallpaperException(e.type.message);
    }
  }

  /// Opens Android's preview for wallp's live wallpaper; the user taps
  /// "Set wallpaper" there. Completes when the picker closes.
  Future<LivePickerResult> openLiveWallpaper() async {
    if (!canSetDirectly) return LivePickerResult.unavailable;
    try {
      final r = await _channel.invokeMethod<Object?>('openLiveWallpaper');
      return switch (r) {
        'set' => LivePickerResult.set,
        'cancelled' => LivePickerResult.cancelled,
        // Older native side: true = opened.
        true => LivePickerResult.cancelled,
        _ => LivePickerResult.unavailable,
      };
    } on PlatformException {
      return LivePickerResult.unavailable;
    } on MissingPluginException {
      return LivePickerResult.unavailable;
    }
  }

  /// Whether wallp's live wallpaper is the phone's wallpaper now.
  Future<bool> isLiveWallpaperActive() async {
    if (!canSetDirectly) return false;
    try {
      return await _channel.invokeMethod<bool>('isLiveWallpaperActive') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Real display size in pixels; null if the native side doesn't answer.
  Future<ui.Size?> _androidScreenSize() async {
    try {
      final size = await _channel.invokeListMethod<int>('screenSize');
      if (size == null || size.length != 2) return null;
      return ui.Size(size[0].toDouble(), size[1].toDouble());
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
