import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/store_palette.dart';
import '../../render/font_registry.dart';
import '../logic/queries.dart';
import '../routes.dart';
import '../state/user_store.dart';
import '../widgets/common.dart';

enum _Tab { all, themes, wallpapers, fonts }

/// Search across themes, wallpapers and fonts.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  _Tab _tab = _Tab.all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _use(String text) {
    _query.text = text;
    _query.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _tab = _Tab.all);
    context.read<UserStore>().rememberQuery(text);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final user = context.watch<UserStore>();
    final q = _query.text;
    final results = search(catalog, q);
    bool show(_Tab t, int count) =>
        count > 0 && (_tab == _Tab.all || _tab == t);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Themes, wallpapers, fonts',
            border: InputBorder.none,
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => setState(() => _query.clear()),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
          onChanged: (_) => setState(() => _tab = _Tab.all),
          onSubmitted: (v) => context.read<UserStore>().rememberQuery(v),
        ),
      ),
      body: q.trim().isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                if (user.recentSearches.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Recent',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.palette.text,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: user.clearSearches,
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in user.recentSearches)
                        ActionChip(label: Text(r), onPressed: () => _use(r)),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                Text(
                  'Popular',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.palette.text,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in catalog.searchSuggestions)
                      ActionChip(label: Text(s), onPressed: () => _use(s)),
                  ],
                ),
              ],
            )
          : results.isEmpty
          ? EmptyMessage(
              icon: Icons.search_off_rounded,
              title: 'Nothing for "$q"',
              message: 'Try a festival, a colour or "live".',
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ChipRow<_Tab>(
                      label: 'Show results',
                      value: _tab,
                      onChanged: (t) => setState(() => _tab = t),
                      options: [
                        (_Tab.all, 'All · ${results.total}'),
                        (_Tab.themes, 'Themes · ${results.themes.length}'),
                        (
                          _Tab.wallpapers,
                          'Wallpapers · ${results.wallpapers.length}',
                        ),
                        (_Tab.fonts, 'Fonts · ${results.fonts.length}'),
                      ],
                    ),
                  ),
                ),
                if (show(_Tab.themes, results.themes.length)) ...[
                  const SliverToBoxAdapter(
                    child: SectionHeader(title: 'Themes'),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                            mainAxisExtent: 286,
                          ),
                      itemCount: results.themes.length,
                      itemBuilder: (context, i) => ThemeCard(
                        theme: results.themes[i],
                        height: 240,
                        onTap: () {
                          user.rememberQuery(q);
                          StoreRoutes.theme(context, results.themes[i].id);
                        },
                      ),
                    ),
                  ),
                ],
                if (show(_Tab.wallpapers, results.wallpapers.length)) ...[
                  const SliverToBoxAdapter(
                    child: SectionHeader(title: 'Wallpapers'),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                            mainAxisExtent: 320,
                          ),
                      itemCount: results.wallpapers.length,
                      itemBuilder: (context, i) => WallpaperCard(
                        wallpaper: results.wallpapers[i],
                        onTap: () {
                          user.rememberQuery(q);
                          StoreRoutes.wallpaper(
                            context,
                            results.wallpapers[i].id,
                          );
                        },
                      ),
                    ),
                  ),
                ],
                if (show(_Tab.fonts, results.fonts.length)) ...[
                  const SliverToBoxAdapter(
                    child: SectionHeader(title: 'Fonts'),
                  ),
                  SliverList.builder(
                    itemCount: results.fonts.length,
                    itemBuilder: (context, i) {
                      final f = results.fonts[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                        ),
                        title: Text(
                          f.family,
                          style: FontRegistry.shared.style(
                            f.family,
                            const TextStyle(fontSize: 24),
                          ),
                        ),
                        subtitle: Text(
                          f.category.name[0].toUpperCase() +
                              f.category.name.substring(1),
                        ),
                        onTap: () {
                          user.rememberQuery(q);
                          StoreRoutes.font(context, f.id);
                        },
                      );
                    },
                  ),
                ],
              ],
            ),
    );
  }
}
