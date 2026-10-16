/// The store's lists, as the design defines them: filters, sorts, badges
/// and search over the catalog. Pure Dart, so every rule is unit tested.
library;

import '../../catalog/catalog.dart';

// ---------------------------------------------------------------------------
// Badges

enum CardBadge { applied, inUse, isNew, live }

extension BadgeText on CardBadge {
  String get label => switch (this) {
    CardBadge.applied => 'APPLIED',
    CardBadge.inUse => 'IN USE',
    CardBadge.isNew => 'NEW',
    CardBadge.live => 'LIVE',
  };
}

/// One badge per card: APPLIED beats NEW beats LIVE.
CardBadge? themeBadge(
  ThemeBase theme, {
  String? appliedId,
  required DateTime now,
}) {
  if (theme.id == appliedId) return CardBadge.applied;
  if (theme.isNew(now)) return CardBadge.isNew;
  if (theme.isLive) return CardBadge.live;
  return null;
}

/// IN USE beats LIVE (wallpapers have no NEW badge in the design).
CardBadge? wallpaperBadge(Wallpaper w, {String? inUseId}) {
  if (w.id == inUseId) return CardBadge.inUse;
  if (w.isLive) return CardBadge.live;
  return null;
}

// ---------------------------------------------------------------------------
// Festivals

/// Dated festivals soonest first (one running today comes first); undated
/// collections after, by their `sort`. Coming-soon ones are left out.
List<Festival> festivalsBySoonest(Catalog catalog, DateTime now) =>
    [
      for (final f in catalog.festivals)
        if (!f.comingSoon) f,
    ]..sort((a, b) {
      final d = a.countdown(now).sortKey.compareTo(b.countdown(now).sortKey);
      return d != 0 ? d : a.sort.compareTo(b.sort);
    });

int _byCountdown(
  Catalog catalog,
  ThemeSummary a,
  ThemeSummary b,
  DateTime now,
) {
  int key(ThemeSummary t) =>
      catalog.festival(t.festivalId)?.countdown(now).sortKey ?? 1 << 31;
  final d = key(a).compareTo(key(b));
  return d != 0 ? d : a.popularityRank.compareTo(b.popularityRank);
}

int _byName(ThemeBase a, ThemeBase b) =>
    a.name.en.toLowerCase().compareTo(b.name.en.toLowerCase());

// ---------------------------------------------------------------------------
// Themes tab

enum ThemesFilter { all, festivals, myanmar, minimal, favourites }

enum ThemesSort { soonest, az }

/// The Themes tab's grid. ("Festivals" shows festival cards instead: see
/// [festivalsBySoonest].)
List<ThemeSummary> themesTab(
  Catalog catalog, {
  required ThemesFilter filter,
  required ThemesSort sort,
  required Set<String> favourites,
  required DateTime now,
}) {
  bool keep(ThemeSummary t) {
    final f = catalog.festival(t.festivalId);
    return switch (filter) {
      ThemesFilter.all || ThemesFilter.festivals => true,
      ThemesFilter.myanmar => f?.tags.contains('myanmar') ?? false,
      ThemesFilter.minimal => f?.kind == FestivalKind.collection,
      ThemesFilter.favourites => favourites.contains(t.id),
    };
  }

  return [
    for (final t in catalog.themes)
      if (keep(t)) t,
  ]..sort(
    sort == ThemesSort.az
        ? _byName
        : (a, b) => _byCountdown(catalog, a, b, now),
  );
}

// ---------------------------------------------------------------------------
// A festival's page

/// The style chips: All, Cozy, Classic, Minimal, Cute, Live.
sealed class StyleFilter {
  const StyleFilter();
}

class AllStyles extends StyleFilter {
  const AllStyles();
}

class LiveOnly extends StyleFilter {
  const LiveOnly();
}

class OneStyle extends StyleFilter {
  const OneStyle(this.style);
  final ThemeStyle style;
}

enum FestivalSort { popular, newest, az }

List<ThemeSummary> festivalThemes(
  Catalog catalog,
  String festivalId, {
  StyleFilter style = const AllStyles(),
  FestivalSort sort = FestivalSort.popular,
}) =>
    [
      for (final t in catalog.themesIn(festivalId))
        if (switch (style) {
          AllStyles() => true,
          LiveOnly() => t.isLive,
          OneStyle(:final style) => t.style == style,
        })
          t,
    ]..sort(switch (sort) {
      FestivalSort.popular => (a, b) => a.popularityRank.compareTo(
        b.popularityRank,
      ),
      FestivalSort.newest => (a, b) => b.publishedAt.compareTo(a.publishedAt),
      FestivalSort.az => _byName,
    });

/// The quick look's previous / next, wrapping around [list].
ThemeSummary stepThrough(List<ThemeSummary> list, ThemeSummary from, int step) {
  final i = list.indexWhere((t) => t.id == from.id);
  return list[((i < 0 ? 0 : i) + step) % list.length];
}

// ---------------------------------------------------------------------------
// Wallpapers, fonts, icon packs

/// "live", or a festival ID; null = all.
List<Wallpaper> wallpapersTab(Catalog catalog, {String? filter}) =>
    [
      for (final w in catalog.wallpapers)
        if (filter == null ||
            (filter == 'live' ? w.isLive : w.festivalId == filter))
          w,
    ]..sort((a, b) {
      // In the festivals' own order (Halloween, Christmas, Thingyan…), then
      // most popular first.
      int order(Wallpaper w) => catalog.festival(w.festivalId)?.sort ?? 1 << 30;
      final f = order(a).compareTo(order(b));
      return f != 0 ? f : a.popularity.compareTo(b.popularity);
    });

/// Festival IDs that have wallpapers, for the filter chips, soonest first.
List<Festival> wallpaperFestivals(Catalog catalog, DateTime now) {
  final used = {for (final w in catalog.wallpapers) w.festivalId};
  return [
    for (final f in festivalsBySoonest(catalog, now))
      if (used.contains(f.id)) f,
  ];
}

List<CatalogFont> fontsTab(Catalog catalog, {FontCategory? category}) => [
  for (final f in catalog.fonts)
    if (category == null || f.category == category) f,
];

/// "new", or a festival ID; null = all.
List<IconPack> iconPacksTab(
  Catalog catalog, {
  String? filter,
  required DateTime now,
}) => [
  for (final p in catalog.iconPacks)
    if (filter == null ||
        (filter == 'new' ? p.isNew(now) : p.festivalId == filter))
      p,
];

// ---------------------------------------------------------------------------
// Search

class SearchResults {
  const SearchResults({
    required this.themes,
    required this.wallpapers,
    required this.fonts,
  });

  static const empty = SearchResults(themes: [], wallpapers: [], fonts: []);

  final List<ThemeSummary> themes;
  final List<Wallpaper> wallpapers;
  final List<CatalogFont> fonts;

  int get total => themes.length + wallpapers.length + fonts.length;
  bool get isEmpty => total == 0;
}

/// Matches a name (any language) or a tag, ignoring case; a theme also
/// matches its festival's name, a font its category, and "live" matches
/// everything that animates. A blank query finds nothing.
SearchResults search(Catalog catalog, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return SearchResults.empty;
  bool text(LocalizedText name) =>
      name.values.values.any((v) => v.toLowerCase().contains(q));
  bool tags(List<String> tags) => tags.any((t) => t.toLowerCase().contains(q));
  final live = q == 'live';
  bool festival(String id) {
    final f = catalog.festival(id);
    return f != null && text(f.name);
  }

  return SearchResults(
    themes: [
      for (final t in catalog.themes)
        if (text(t.name) ||
            tags(t.tags) ||
            (t.subtitle != null && text(t.subtitle!)) ||
            festival(t.festivalId) ||
            (live && t.isLive))
          t,
    ],
    wallpapers: [
      for (final w in catalog.wallpapers)
        if (text(w.name) ||
            tags(w.tags) ||
            festival(w.festivalId) ||
            (live && w.isLive))
          w,
    ],
    fonts: [
      for (final f in catalog.fonts)
        if (f.family.toLowerCase().contains(q) ||
            tags(f.tags) ||
            f.category.name == q)
          f,
    ],
  );
}

/// Recent searches: newest first, no repeats (ignoring case), at most 5.
List<String> rememberSearch(List<String> recent, String query, {int keep = 5}) {
  final q = query.trim();
  if (q.isEmpty) return recent;
  return [
    q,
    for (final r in recent)
      if (r.toLowerCase() != q.toLowerCase()) r,
  ].take(keep).toList();
}

// ---------------------------------------------------------------------------
// Text

/// "0.8 MB", "450 KB".
String formatBytes(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).ceil()} KB';

String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';
