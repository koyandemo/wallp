import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../catalog/catalog.dart';
import '../../core/app_colors.dart';
import '../../data/catalog/catalog_repository.dart';
import '../logic/previews.dart';
import '../logic/queries.dart';
import '../routes.dart';
import '../widgets/common.dart';

/// One festival's themes (the "Festival page: Christmas" design): style
/// chips, Popular / New / A–Z, and a quick look with colour variants.
class FestivalScreen extends StatefulWidget {
  const FestivalScreen({super.key, required this.festivalId});

  final String festivalId;

  @override
  State<FestivalScreen> createState() => _FestivalScreenState();
}

class _FestivalScreenState extends State<FestivalScreen> {
  StyleFilter _style = const AllStyles();
  FestivalSort _sort = FestivalSort.popular;

  static final _styles = <(StyleFilter, String)>[
    (const AllStyles(), 'All'),
    (const OneStyle(ThemeStyle.cozy), 'Cozy'),
    (const OneStyle(ThemeStyle.classic), 'Classic'),
    (const OneStyle(ThemeStyle.minimal), 'Minimal'),
    (const OneStyle(ThemeStyle.cute), 'Cute'),
    (const LiveOnly(), 'Live'),
  ];

  bool _same(StyleFilter a, StyleFilter b) => switch ((a, b)) {
    (AllStyles(), AllStyles()) || (LiveOnly(), LiveOnly()) => true,
    (OneStyle(style: final x), OneStyle(style: final y)) => x == y,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final festival = catalog.festival(widget.festivalId);
    if (festival == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyMessage(
          icon: Icons.event_busy_rounded,
          title: 'This festival is no longer in the store',
        ),
      );
    }
    final now = nowOf(context);
    final all = catalog.themesIn(festival.id);
    final list = festivalThemes(
      catalog,
      festival.id,
      style: _style,
      sort: _sort,
    );
    final selected = _styles.firstWhere((s) => _same(s.$1, _style));
    final countdown = festival.countdown(now);

    return Scaffold(
      appBar: AppBar(title: Text(festival.name.en)),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                [
                  if (!countdown.isAnyTime) countdown.label(),
                  plural(all.length, 'theme'),
                ].join(' · '),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ChipRow<StyleFilter>(
              options: _styles,
              value: selected.$1,
              label: 'Filter by style',
              onChanged: (s) => setState(() => _style = s),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  // The count gives way (ellipsis) before the sort buttons.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        plural(list.length, 'theme'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  for (final (key, label) in const [
                    (FestivalSort.popular, 'Popular'),
                    (FestivalSort.newest, 'New'),
                    (FestivalSort.az, 'A–Z'),
                  ])
                    Semantics(
                      inMutuallyExclusiveGroup: true,
                      checked: key == _sort,
                      child: TextButton(
                        onPressed: () => setState(() => _sort = key),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          foregroundColor: key == _sort
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            decoration: key == _sort
                                ? TextDecoration.underline
                                : null,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (list.isEmpty)
            SliverToBoxAdapter(
              child: EmptyMessage(
                icon: Icons.filter_alt_off_rounded,
                title: _style is LiveOnly
                    ? 'No live ${festival.name.en} themes yet'
                    : 'No ${selected.$2.toLowerCase()} ${festival.name.en} themes yet',
                message: 'Try another style.',
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
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final t = list[i];
                  return Stack(
                    children: [
                      ThemeCard(
                        theme: t,
                        subtitle:
                            '${t.style.name[0].toUpperCase()}${t.style.name.substring(1)}'
                            '${t.isLive ? ' · Live' : ''}'
                            '${t.variantSwatches.length > 1 ? ' · ${plural(t.variantSwatches.length, 'colour')}' : ''}',
                        onTap: () => StoreRoutes.theme(context, t.id),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 44,
                        child: IconButton(
                          tooltip: 'Quick look at ${t.name.en}',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.background.withValues(
                              alpha: 0.8,
                            ),
                          ),
                          icon: const Icon(
                            Icons.visibility_outlined,
                            size: 18,
                            color: AppColors.textPrimary,
                          ),
                          onPressed: () => showQuickLook(context, list, t),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// A big preview of [start] with its colour variants, stepping through
/// [list] with previous / next.
Future<void> showQuickLook(
  BuildContext context,
  List<ThemeSummary> list,
  ThemeSummary start,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.surface,
  showDragHandle: true,
  builder: (_) => _QuickLook(list: list, start: start),
);

class _QuickLook extends StatefulWidget {
  const _QuickLook({required this.list, required this.start});

  final List<ThemeSummary> list;
  final ThemeSummary start;

  @override
  State<_QuickLook> createState() => _QuickLookState();
}

class _QuickLookState extends State<_QuickLook> {
  late ThemeSummary _theme = widget.start;
  ThemeDetail? _detail;
  String? _variant;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  /// Variants need the full file; until it's here the summary's colours show.
  void _loadDetail() {
    final wanted = _theme;
    _detail = null;
    context.read<CatalogRepository>().theme(wanted.id).then((d) {
      if (mounted && _theme.id == wanted.id) setState(() => _detail = d);
    }, onError: (Object _) {});
  }

  void _step(int by) => setState(() {
    _theme = stepThrough(widget.list, _theme, by);
    _variant = null;
    _loadDetail();
  });

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final now = nowOf(context);
    final detail = _detail;
    final preview = previewOf(
      _theme,
      catalog,
      now,
      detail: detail,
      variantId: _variant,
    );
    final i = widget.list.indexWhere((t) => t.id == _theme.id);
    return Semantics(
      label: 'Quick look: ${_theme.name.en}',
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous theme',
                    onPressed: () => _step(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _theme.name.en,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${i + 1} of ${widget.list.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next theme',
                    onPressed: () => _step(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 360,
                width: 200,
                child: SceneThumb(theme: preview, animate: true),
              ),
              const SizedBox(height: 14),
              if (detail != null && detail.variants.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final v in detail.variants)
                      Semantics(
                        inMutuallyExclusiveGroup: true,
                        checked: (_variant ?? detail.variants.first.id) == v.id,
                        label: v.name.en,
                        child: InkResponse(
                          onTap: () => setState(() => _variant = v.id),
                          radius: 26,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 44,
                            height: 44,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    (_variant ?? detail.variants.first.id) ==
                                        v.id
                                    ? AppColors.textPrimary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(
                                  detail.paletteFor(v.id).background.argb,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    StoreRoutes.theme(context, _theme.id);
                  },
                  child: const Text('Open theme'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
