import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/date_format.dart';
import '../models/phone_theme.dart';
import '../services/my_themes.dart';
import '../widgets/current_theme_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/theme_card.dart';
import '../widgets/theme_preview.dart';
import 'theme_detail_screen.dart';

/// My Themes tab: the applied theme, favourites, and earlier applies.
class MyThemesScreen extends StatelessWidget {
  const MyThemesScreen({super.key});

  void _open(BuildContext context, PhoneTheme theme, [Color? accent]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThemeDetailScreen(theme: theme, accent: accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final my = context.watch<MyThemes>();
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final current = my.current;
    final favorites = my.favorites;
    final earlier = my.history.skip(1).toList();

    Widget heading(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Text(title, style: text.titleMedium?.copyWith(fontSize: 18)),
    );

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Text('My Themes', style: text.headlineLarge),
            ),
          ),
          if (current == null && favorites.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.favorite_rounded,
                title: 'Nothing here yet',
                message:
                    'Tap ♡ on a theme to save it, or apply one. '
                    'They will show up here.',
              ),
            )
          else ...[
            if (current != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: CurrentThemeCard(
                    entry: current,
                    now: now,
                    onTap: () => _open(context, current.theme, current.accent),
                  ),
                ),
              ),
            SliverToBoxAdapter(child: heading('Favourites')),
            if (favorites.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Tap ♡ on any theme to keep it here.',
                    style: text.bodyMedium,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 14.0;
                    final tileWidth = (constraints.crossAxisExtent - gap) / 2;
                    return SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: gap,
                        mainAxisSpacing: 20,
                        mainAxisExtent:
                            tileWidth * kSceneSize.height / kSceneSize.width +
                            ThemeCard.labelHeight,
                      ),
                      itemCount: favorites.length,
                      itemBuilder: (context, i) => ThemeCard(
                        theme: favorites[i],
                        now: now,
                        onTap: () => _open(context, favorites[i]),
                      ),
                    );
                  },
                ),
              ),
            if (earlier.isNotEmpty) ...[
              SliverToBoxAdapter(child: heading('Applied before')),
              SliverList.builder(
                itemCount: earlier.length,
                itemBuilder: (context, i) => _HistoryRow(
                  entry: earlier[i],
                  now: now,
                  onTap: () =>
                      _open(context, earlier[i].theme, earlier[i].accent),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.now,
    required this.onTap,
  });

  final AppliedEntry entry;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36 * kSceneSize.height / kSceneSize.width,
          child: ThemePreview(
            theme: entry.theme,
            now: now,
            accent: entry.accent,
          ),
        ),
      ),
      title: Text(entry.theme.name, style: text.titleMedium),
      subtitle: Text(
        DateFormatX.ago(entry.appliedAt, now),
        style: text.bodyMedium,
      ),
      trailing: AccentDot(color: entry.accent),
    );
  }
}
