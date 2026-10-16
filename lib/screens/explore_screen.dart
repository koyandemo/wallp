import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../data/theme_catalog.dart';
import '../models/phone_theme.dart';
import '../widgets/category_chips.dart';
import '../widgets/empty_state.dart';
import '../widgets/next_up_card.dart';
import '../widgets/theme_card.dart';
import '../widgets/theme_preview.dart';
import 'theme_detail_screen.dart';

/// Explore tab: "Next up" hero, category chips and a grid of themes.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  /// Starts on the category of the festival coming up next.
  late String _categoryId = ThemeCatalog.nextUp(DateTime.now()).categoryId;

  void _open(PhoneTheme theme) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ThemeDetailScreen(theme: theme)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final text = Theme.of(context).textTheme;
    final category = ThemeCatalog.categories.firstWhere(
      (c) => c.id == _categoryId,
    );
    final themes = ThemeCatalog.themesIn(category.id);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'wallp',
                    style: text.titleMedium?.copyWith(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Seasonal themes', style: text.headlineLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Live wallpapers for every festival',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  NextUpCard(
                    theme: ThemeCatalog.nextUp(now),
                    now: now,
                    onTap: () => _open(ThemeCatalog.nextUp(now)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: CategoryChips(
              categories: ThemeCatalog.categories,
              selectedId: _categoryId,
              onSelected: (id) => setState(() => _categoryId = id),
            ),
          ),
          if (category.comingSoon)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.auto_awesome_rounded,
                title: '${category.name} themes',
                message: 'Coming soon',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
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
                    itemCount: themes.length,
                    itemBuilder: (context, i) => ThemeCard(
                      theme: themes[i],
                      now: now,
                      onTap: () => _open(themes[i]),
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
