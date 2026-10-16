import 'package:flutter/material.dart';

import '../../catalog/catalog.dart';
import '../../core/store_palette.dart';
import '../../render/font_registry.dart';
import '../logic/queries.dart';
import '../routes.dart';
import '../widgets/common.dart';

/// The Fonts tab: every clock font, previewing text the user types.
class FontsScreen extends StatefulWidget {
  const FontsScreen({super.key});

  @override
  State<FontsScreen> createState() => _FontsScreenState();
}

class _FontsScreenState extends State<FontsScreen> {
  FontCategory? _category;
  final _sample = TextEditingController(text: '19:47');

  static const _filters = <(FontCategory?, String)>[
    (null, 'All'),
    (FontCategory.display, 'Display'),
    (FontCategory.handwritten, 'Handwritten'),
    (FontCategory.clean, 'Clean'),
    (FontCategory.myanmar, 'Myanmar'),
  ];

  @override
  void dispose() {
    _sample.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final fonts = fontsTab(catalog, category: _category);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: TabHeader(
            title: 'Fonts',
            subtitle:
                '${plural(fonts.length, 'font')} for the lock and home clock',
            actions: [
              RoundIconButton(
                icon: Icons.search_rounded,
                label: 'Search',
                onPressed: () => StoreRoutes.search(context),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: TextField(
              controller: _sample,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Preview text',
                prefixIcon: Icon(Icons.edit_outlined),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ChipRow<FontCategory?>(
              options: _filters,
              value: _category,
              label: 'Filter fonts',
              onChanged: (c) => setState(() => _category = c),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          sliver: SliverList.separated(
            itemCount: fonts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) =>
                _FontCard(font: fonts[i], sample: _sample.text),
          ),
        ),
      ],
    );
  }
}

class _FontCard extends StatelessWidget {
  const _FontCard({required this.font, required this.sample});

  final CatalogFont font;
  final String sample;

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final usedBy = [
      for (final t in catalog.themes)
        if (t.displayFont == font.id) t.name.en,
    ];
    // Burmese fonts show Burmese until the user types something else.
    final text =
        sample.trim().isEmpty || (sample == '19:47' && font.sampleText != null)
        ? (font.sampleText?.en ?? '19:47')
        : sample;
    final tag = usedBy.isEmpty ? 'Free' : 'In ${usedBy.first}';
    return Semantics(
      button: true,
      label: '${font.family}, $tag',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => StoreRoutes.font(context, font.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.palette.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FontRegistry.shared.style(
                  font.family,
                  TextStyle(
                    fontSize: 40,
                    height: 1.1,
                    color: context.palette.text,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      font.family,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.palette.text,
                      ),
                    ),
                  ),
                  Text(
                    tag,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
