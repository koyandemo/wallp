import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../data/theme_catalog.dart';
import '../models/theme_category.dart';

/// Horizontal row of category pills, each with a dot in its festival color.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<ThemeCategory> categories;
  final String selectedId;
  final ValueChanged<String> onSelected;

  Color _dotColor(ThemeCategory category) {
    final themes = ThemeCatalog.themesIn(category.id);
    return themes.isEmpty ? AppColors.outline : themes.first.palette.accent;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium!
        .copyWith(fontSize: 14);
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final category = categories[i];
          final selected = category.id == selectedId;
          final shape = StadiumBorder(
            side: BorderSide(
              color: selected ? Colors.transparent : AppColors.outline,
            ),
          );
          return Semantics(
            selected: selected,
            child: Material(
              key: ValueKey('chip-${category.id}'),
              color: selected ? AppColors.textPrimary : AppColors.surface,
              shape: shape,
              child: InkWell(
                customBorder: shape,
                onTap: () => onSelected(category.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _dotColor(category),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        category.name,
                        style: style.copyWith(
                          color: selected
                              ? AppColors.background
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
