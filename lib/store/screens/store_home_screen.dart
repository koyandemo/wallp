import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../catalog/catalog.dart' hide Banner;
import '../../catalog/catalog.dart' as cat show Banner;
import '../../core/store_palette.dart';
import '../../look/look_controller.dart';
import '../logic/previews.dart';
import '../logic/queries.dart';
import '../routes.dart';
import '../store_shell.dart';
import '../widgets/common.dart';
import 'icon_pack_screens.dart';

/// Store home: the banner carousel, then one row per festival (soonest
/// first) and the icon packs.
class StoreHomeScreen extends StatelessWidget {
  const StoreHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final now = nowOf(context);
    final banners = [
      for (final b in catalog.banners)
        if (b.isShowing(now)) b,
    ]..sort((a, b) => a.sort.compareTo(b.sort));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        TabHeader(
          title: 'wallp',
          subtitle: 'Themes, wallpapers and clock fonts',
          actions: [
            RoundIconButton(
              icon: Icons.search_rounded,
              label: 'Search',
              onPressed: () => StoreRoutes.search(context),
            ),
          ],
        ),
        if (banners.isNotEmpty) BannerCarousel(banners: banners),
        const SizedBox(height: 24),
        for (final f in festivalsBySoonest(catalog, now))
          if (catalog.themesIn(f.id).isNotEmpty) _FestivalRow(festival: f),
        _IconPacksRow(),
      ],
    );
  }
}

class _FestivalRow extends StatelessWidget {
  const _FestivalRow({required this.festival});

  final Festival festival;

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final now = nowOf(context);
    final themes = festivalThemes(catalog, festival.id);
    final countdown = festival.countdown(now);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: festival.name.en,
            subtitle: [
              if (!countdown.isAnyTime) countdown.label(),
              plural(themes.length, 'theme'),
            ].join(' · '),
            action: 'See all ${themes.length}',
            onAction: () => StoreRoutes.festival(context, festival.id),
          ),
          SizedBox(
            height: 268,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: themes.take(6).length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => SizedBox(
                width: 140,
                child: ThemeCard(
                  theme: themes[i],
                  height: 220,
                  subtitle:
                      themes[i].style.name[0].toUpperCase() +
                      themes[i].style.name.substring(1),
                  onTap: () => StoreRoutes.theme(context, themes[i].id),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconPacksRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final packs = catalog.iconPacks;
    if (packs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Icon packs',
          subtitle: '${plural(packs.length, 'pack')} for wallp Home',
          action: 'See all',
          onAction: () => StoreRoutes.iconPacks(context),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: packs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _PackChip(pack: packs[i]),
          ),
        ),
      ],
    );
  }
}

class _PackChip extends StatelessWidget {
  const _PackChip({required this.pack});

  final IconPack pack;

  @override
  Widget build(BuildContext context) {
    // The real icons; for the pack in use, in the user's tile shape.
    final looks = context.watch<LookController>();
    final applied = looks.isApplied ? looks.look?.icons : null;
    final shape = applied?.pack.id == pack.id ? applied!.shape : pack.shape;
    return Semantics(
      button: true,
      label: '${pack.name.en} icon pack',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => StoreRoutes.iconPack(context, pack.id),
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.palette.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final key in const ['phone', 'messages', 'camera'])
                    PackIcon(
                      pack: pack,
                      app: sampleApp(key),
                      shape: shape,
                      size: 36,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                pack.name.en,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.palette.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The store home's carousel: one banner at a time, moving on every
/// [interval], with dots and previous / next buttons.
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({
    super.key,
    required this.banners,
    this.interval = const Duration(milliseconds: 4500),
  });

  final List<cat.Banner> banners;
  final Duration interval;

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final _pages = PageController(viewportFraction: 0.88);
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) => _go(1));
  }

  void _go(int step) {
    final n = widget.banners.length;
    if (n < 2 || !_pages.hasClients) return;
    _pages.animateToPage(
      (_index + step + n) % n,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _pages,
            itemCount: banners.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _BannerCard(
                banner: banners[i],
                position: '${i + 1} of ${banners.length}',
              ),
            ),
          ),
        ),
        if (banners.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous banner',
                onPressed: () {
                  _go(-1);
                  _restart();
                },
                icon: Icon(
                  Icons.chevron_left_rounded,
                  color: context.palette.muted,
                ),
              ),
              for (var i = 0; i < banners.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _index
                        ? context.palette.brand
                        : context.palette.outline,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              IconButton(
                tooltip: 'Next banner',
                onPressed: () {
                  _go(1);
                  _restart();
                },
                icon: Icon(
                  Icons.chevron_right_rounded,
                  color: context.palette.muted,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner, required this.position});

  final cat.Banner banner;
  final String position;

  void _open(BuildContext context) {
    final a = banner.action;
    switch (a.type) {
      case BannerActionType.theme:
        StoreRoutes.theme(context, a.id!);
      case BannerActionType.festival:
        StoreRoutes.festival(context, a.id!);
      case BannerActionType.wallpapers:
        showWallpapersTab(context, festivalId: a.id);
      case BannerActionType.fonts:
        StoreShell.showTab(context, StoreTab.fonts);
      case BannerActionType.iconPacks:
        StoreRoutes.iconPacks(context, filter: a.id);
      case BannerActionType.url:
        // No browser hand-off yet; links are for later campaigns.
        showToast(context, 'Opens ${a.url} in a later version');
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final look = banner.look;
    final font = catalog.font(look.font)?.family ?? 'Sora';
    final art = look.artThemeId == null
        ? null
        : catalog.theme(look.artThemeId!);
    final accent = Color(look.accent.argb);
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.light
        ? context.palette.background
        : context.palette.text;
    final style = previewOf(
      art ?? catalog.themes.first,
      catalog,
      nowOf(context),
    );
    return Semantics(
      label: '${banner.title.en}, banner $position',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: Color(look.background.argb),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        banner.tag.en,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: context.palette.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        banner.title.en,
                        maxLines: 2,
                        style: style
                            .copyWith(displayFont: font)
                            .displayStyle(
                              TextStyle(
                                fontSize: 28,
                                height: 1.05,
                                color: Color(look.titleColor.argb),
                              ),
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        banner.subtitle.en,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.text,
                          height: 1.3,
                        ),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => _open(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: onAccent,
                          minimumSize: const Size(44, 44),
                        ),
                        child: Text(banner.cta.en),
                      ),
                    ],
                  ),
                ),
              ),
              if (art != null)
                SizedBox(
                  width: 110,
                  child: SceneThumb(
                    theme: previewOf(art, catalog, nowOf(context)),
                    radius: 0,
                    showClock: false,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
