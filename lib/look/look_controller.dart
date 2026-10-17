import 'dart:async';

import 'package:flutter/foundation.dart';

import '../catalog/catalog.dart';
import '../core/clock.dart';
import '../data/catalog/catalog_repository.dart';
import 'applied_look.dart';
import 'look_store.dart';

/// Gets everything [next] needs onto the phone before it's applied, e.g.
/// downloads its files, showing [label] ("Spider Night") while it works.
typedef PrepareLook = Future<void> Function(AppliedLook next, String label);

/// Keeps [files] on the phone for [owner] (`applied` or `pending`),
/// releasing whatever that owner kept before.
typedef PinFiles = Future<void> Function(String owner, Set<AssetRef> files);

/// Every way the store changes what the phone looks like: apply a theme
/// (whole, wallpaper only or clock font only, with its accent and colour
/// variant), a wallpaper, a clock font or an icon pack.
///
/// Each change builds the next [AppliedLook] from the current one, so the
/// parts the user didn't touch stay as they were. Changes run one at a
/// time, in order, so two quick taps can't overwrite each other.
///
/// A change is all or nothing: [prepare] (the downloads) must finish
/// before anything is saved; if it fails or is cancelled, the old look
/// stays. Once saved, the look's files are pinned so they're never
/// cleaned up while wallp Home or the live wallpaper need them.
class LookController extends ChangeNotifier {
  LookController({
    required this._catalog,
    LookStore? store,
    this.clock = const SystemClock(),
    this.prepare,
    this.pin,
  }) : _store = store ?? LookStore();

  final CatalogRepository _catalog;
  final LookStore _store;
  final Clock clock;
  final PrepareLook? prepare;
  final PinFiles? pin;

  static const appliedOwner = 'applied';
  static const pendingOwner = 'pending';
  static const incomingOwner = 'incoming';

  AppliedLook? _look;
  bool _isSaved = false;
  Future<void> _queue = Future.value();

  /// The look on the phone; null until [load] finishes.
  AppliedLook? get look => _look;

  /// False while the phone shows the default (nothing applied yet).
  bool get isApplied => _isSaved;

  /// Reads the saved look. Call again when the app resumes: wallp Home may
  /// have finished a pending apply meanwhile.
  Future<void> load() => _enqueue(() async {
    final saved = await _store.saved();
    _isSaved = saved != null;
    _look = saved ?? await _store.defaultLook(clock.now());
    notifyListeners();
  });

  /// Makes sure the applied look's files are pinned and on the phone, e.g.
  /// after the user cleared storage. Runs in the background on launch;
  /// failing is fine (offline): wallp Home keeps what it has.
  Future<void> repair() => _enqueue(() async {
    final look = _look;
    if (look == null || !_isSaved) return;
    try {
      await pin?.call(appliedOwner, look.assets);
      await prepare?.call(look, look.theme.name.en);
    } on Object catch (e) {
      debugPrint("Couldn't repair the applied look: $e");
    }
  });

  /// Drops a pending apply (the user came back without Android making
  /// wallp the home app, or this screen is finishing it itself).
  Future<void> clearPending() => _enqueue(() async {
    await _store.clearPending();
    await pin?.call(pendingOwner, const {});
  });

  /// Applies [option] of the theme [themeId] (the detail page's sheet).
  ///
  /// With [asPending], the look is kept for wallp Home to finish instead:
  /// used while Android switches the home app, which can end this app.
  Future<AppliedLook> applyTheme(
    String themeId, {
    ApplyOption option = ApplyOption.wholeTheme,
    String? variantId,
    Accent? accent,
    bool asPending = false,
  }) => _change(asPending: asPending, (current, catalog, at) async {
    final theme = await _catalog.theme(themeId);
    final next = current.apply(
      catalog,
      theme,
      option,
      at: at,
      variantId: variantId,
      accent: accent,
    );
    final label = option == ApplyOption.clockFontOnly
        ? next.clockFont.family
        : theme.name.en;
    return (next, label);
  });

  /// Puts a stand-alone wallpaper on; theme, icons and font stay.
  Future<AppliedLook> applyWallpaper(String wallpaperId) =>
      _change((current, catalog, at) async {
        final w =
            catalog.wallpaper(wallpaperId) ??
            (throw NotInCatalogException('wallpaper', wallpaperId));
        return (
          current.withWallpaper(WallpaperChoice.standalone(w), at: at),
          w.name.en,
        );
      });

  /// A clock font from the Fonts screen, with the Font detail page's
  /// options (unchanged ones keep their current value).
  Future<AppliedLook> applyClockFont(
    String fontId, {
    ClockSize? size,
    ClockColor? color,
    ClockPlaces? places,
  }) => _change((current, catalog, at) async {
    final font =
        catalog.font(fontId) ?? (throw NotInCatalogException('font', fontId));
    return (
      current.withClockFont(
        font,
        at: at,
        size: size,
        color: color,
        places: places,
      ),
      font.family,
    );
  });

  Future<AppliedLook> applyIconPack(
    String packId, {
    IconShape? shape,
    LabelColor? labels,
    LabelFont? labelFont,
  }) => _change((current, catalog, at) async {
    final pack =
        catalog.iconPack(packId) ??
        (throw NotInCatalogException('icon pack', packId));
    return (
      current.withIconPack(
        pack,
        at: at,
        shape: shape,
        labels: labels,
        labelFont: labelFont,
      ),
      pack.name.en,
    );
  });

  Future<AppliedLook> _change(
    Future<(AppliedLook, String)> Function(
      AppliedLook current,
      Catalog catalog,
      DateTime at,
    )
    build, {
    bool asPending = false,
  }) {
    final done = Completer<AppliedLook>();
    _enqueue(() async {
      try {
        final current = _look ?? await _store.load(now: clock.now());
        final (next, label) = await build(
          current,
          _catalog.catalog,
          clock.now(),
        );
        // Hold the new files from the moment they arrive until the look
        // is saved and pins them for good.
        await pin?.call(incomingOwner, next.assets);
        await prepare?.call(next, label);
        if (asPending) {
          await _store.savePending(next, at: clock.now());
          await pin?.call(pendingOwner, next.assets);
        } else {
          await _store.save(next);
          _look = next;
          _isSaved = true;
          notifyListeners();
          await pin?.call(appliedOwner, next.assets);
          // Applied now: a pending apply's files no longer need keeping.
          await pin?.call(pendingOwner, const {});
        }
        await pin?.call(incomingOwner, const {});
        done.complete(next);
      } on Object catch (e, s) {
        // The files that did arrive stay as normal cache, so trying again
        // continues where this stopped.
        try {
          await pin?.call(incomingOwner, const {});
        } on Object {
          // Releasing a pin can't make a failed apply worse.
        }
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  Future<void> _enqueue(Future<void> Function() task) =>
      _queue = _queue.then((_) => task());
}

/// The catalog on screen doesn't list what the user tried to apply.
class NotInCatalogException implements Exception {
  const NotInCatalogException(this.kind, this.id);

  final String kind;
  final String id;

  @override
  String toString() => 'NotInCatalogException: no $kind "$id"';
}
