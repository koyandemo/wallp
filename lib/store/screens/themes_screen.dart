import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../catalog/catalog.dart';
import '../../core/store_palette.dart';
import '../logic/previews.dart';
import '../logic/queries.dart';
import '../routes.dart';
import '../state/user_store.dart';
import '../widgets/common.dart';

/// The Themes tab: every theme, filtered and sorted; "Festivals" shows
/// one card per festival instead.
class ThemesScreen extends StatefulWidget {
  const ThemesScreen({super.key});

  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  ThemesFilter _filter = ThemesFilter.all;
  ThemesSort _sort = ThemesSort.soonest;

  static const _filters = [
    (ThemesFilter.all, 'All'),
    (ThemesFilter.festivals, 'Festivals'),
    (ThemesFilter.myanmar, 'Myanmar'),
    (ThemesFilter.minimal, 'Minimal'),
    (ThemesFilter.favourites, 'Favourites'),
  ];

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final now = nowOf(context);
    final favourites = context.watch<UserStore>().favouriteThemes.toSet();
    final byFestival = _filter == ThemesFilter.festivals;
    final festivals = festivalsBySoonest(
      catalog,
      now,
    ).where((f) => catalog.themesIn(f.id).isNotEmpty).toList();
    // Only filters that find something (All, Festivals and Favourites stay).
    final filters = [
      for (final f in _filters)
        if (f.$1 == ThemesFilter.all ||
            f.$1 == ThemesFilter.festivals ||
            f.$1 == ThemesFilter.favourites ||
            themesTab(
              catalog,
              filter: f.$1,
              sort: _sort,
              favourites: favourites,
              now: now,
            ).isNotEmpty)
          f,
    ];
    final themes = themesTab(
      catalog,
      filter: _filter,
      sort: _sort,
      favourites: favourites,
      now: now,
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: TabHeader(
            title: 'Themes',
            subtitle: byFestival
                ? plural(festivals.length, 'festival')
                : plural(themes.length, 'theme'),
            actions: [
              RoundIconButton(
                icon: Icons.search_rounded,
                label: 'Search',
                onPressed: () => StoreRoutes.search(context),
              ),
              if (!byFestival)
                RoundIconButton(
                  icon: Icons.swap_vert_rounded,
                  text: _sort == ThemesSort.soonest ? 'Soonest' : 'A–Z',
                  label: _sort == ThemesSort.soonest
                      ? 'Sorted by soonest festival, switch to A to Z'
                      : 'Sorted A to Z, switch to soonest festival',
                  onPressed: () => setState(
                    () => _sort = _sort == ThemesSort.soonest
                        ? ThemesSort.az
                        : ThemesSort.soonest,
                  ),
                ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ChipRow(
              options: filters,
              value: _filter,
              label: 'Filter themes',
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
        ),
        if (byFestival)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            sliver: SliverList.separated(
              itemCount: festivals.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) =>
                  _FestivalCard(festival: festivals[i]),
            ),
          )
        else if (themes.isEmpty)
          SliverToBoxAdapter(
            child: _filter == ThemesFilter.favourites
                ? const EmptyMessage(
                    icon: Icons.favorite_border_rounded,
                    title: 'No favourites yet',
                    message: 'Tap the heart on a theme to keep it here.',
                  )
                : const EmptyMessage(
                    icon: Icons.search_off_rounded,
                    title: 'No themes here yet',
                  ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                mainAxisExtent: 336,
              ),
              itemCount: themes.length,
              itemBuilder: (context, i) => ThemeCard(
                theme: themes[i],
                onTap: () => StoreRoutes.theme(context, themes[i].id),
              ),
            ),
          ),
      ],
    );
  }
}

class _FestivalCard extends StatelessWidget {
  const _FestivalCard({required this.festival});

  final Festival festival;

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final now = nowOf(context);
    final themes = festivalThemes(catalog, festival.id);
    final countdown = festival.countdown(now).label();
    final font = catalog.font(festival.look.displayFont)?.family ?? 'Sora';
    final sample = previewOf(
      themes.first,
      catalog,
      now,
    ).copyWith(displayFont: font);
    return Semantics(
      button: true,
      label:
          '${festival.name.en}, $countdown, ${plural(themes.length, 'theme')}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => StoreRoutes.festival(context, festival.id),
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: Color(festival.look.background.argb),
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      festival.name.en,
                      style: sample.displayStyle(
                        TextStyle(
                          fontSize: 30,
                          height: 1.05,
                          color: Color(festival.look.brand.argb),
                        ),
                      ),
                    ),
                    Text(
                      countdown,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.text,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: context.palette.background,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${plural(themes.length, 'theme')}  ›',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final t in themes.take(3))
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: SizedBox(
                    width: 38,
                    height: 104,
                    child: SceneThumb(
                      theme: previewOf(t, catalog, now),
                      radius: 12,
                      showClock: false,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
