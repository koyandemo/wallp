import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'home_layout.dart';

/// A place on the home screen: slot [index] on page [page], or in the dock.
class SlotRef {
  const SlotRef.page(this.page, this.index) : dock = false;
  const SlotRef.dock(this.index) : dock = true, page = -1;

  final bool dock;
  final int page;
  final int index;
}

/// The user's home screen: package names per page, plus the dock.
///
/// Immutable: every change returns a new arrangement. Pages are packed
/// (no gaps); a page that overflows pushes its last apps onto the next page.
class HomeArrangement {
  HomeArrangement({
    required List<List<String>> pages,
    required List<String> dock,
  }) : pages = [
         for (final page in pages) [...page],
         if (pages.isEmpty) <String>[],
       ],
       dock = [...dock];

  factory HomeArrangement.fromLayout(HomeLayout layout) => HomeArrangement(
    pages: [
      [for (final app in layout.home) app.packageName],
    ],
    dock: [for (final app in layout.dock) app.packageName],
  );

  factory HomeArrangement.fromJson(Map<String, dynamic> json) =>
      HomeArrangement(
        pages: [
          for (final page in json['pages'] as List)
            [...(page as List).cast<String>()],
        ],
        dock: [...(json['dock'] as List).cast<String>()],
      );

  static const pageSlots = 16;
  static const dockSlots = 4;

  final List<List<String>> pages;
  final List<String> dock;

  Map<String, Object> toJson() => {'pages': pages, 'dock': dock};

  bool contains(String package) =>
      dock.contains(package) || pages.any((p) => p.contains(package));

  HomeArrangement _copy() => HomeArrangement(pages: pages, dock: dock);

  HomeArrangement remove(String package) {
    final next = _copy();
    next.dock.remove(package);
    for (final page in next.pages) {
      page.remove(package);
    }
    return next;
  }

  /// Moves (or places) [package] at [to]. Dropping on a full dock is ignored.
  HomeArrangement move(String package, SlotRef to) {
    final next = remove(package);
    if (to.dock) {
      if (next.dock.length >= dockSlots) return this;
      next.dock.insert(to.index.clamp(0, next.dock.length), package);
      return next;
    }
    while (next.pages.length <= to.page) {
      next.pages.add([]);
    }
    final page = next.pages[to.page];
    page.insert(to.index.clamp(0, page.length), package);
    next._spillFrom(to.page);
    return next;
  }

  /// Adds [package] to the first page from [page] on that has room.
  HomeArrangement add(String package, {int page = 0}) {
    if (contains(package)) return this;
    final next = _copy();
    for (var i = page.clamp(0, next.pages.length); i < next.pages.length; i++) {
      if (next.pages[i].length < pageSlots) {
        next.pages[i].add(package);
        return next;
      }
    }
    next.pages.add([package]);
    return next;
  }

  HomeArrangement addPage() => _copy()..pages.add([]);

  /// Drops empty pages, keeping at least one.
  HomeArrangement withoutEmptyPages() {
    final next = _copy()..pages.removeWhere((p) => p.isEmpty);
    if (next.pages.isEmpty) next.pages.add([]);
    return next;
  }

  /// Forgets apps that are no longer installed.
  HomeArrangement retainInstalled(Set<String> installed) {
    final next = _copy()..dock.removeWhere((p) => !installed.contains(p));
    for (final page in next.pages) {
      page.removeWhere((p) => !installed.contains(p));
    }
    return next;
  }

  void _spillFrom(int start) {
    for (var i = start; i < pages.length; i++) {
      while (pages[i].length > pageSlots) {
        if (i + 1 == pages.length) pages.add([]);
        pages[i + 1].insert(0, pages[i].removeLast());
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is HomeArrangement &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Saves the arrangement on the phone.
class HomeStore {
  HomeStore({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;
  static const _key = 'home_arrangement';

  Future<HomeArrangement?> load() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return HomeArrangement.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(HomeArrangement arrangement) =>
      _prefs.setString(_key, jsonEncode(arrangement.toJson()));
}
