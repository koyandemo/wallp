import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../look/look_controller.dart';
import '../logic/queries.dart';
import '../routes.dart';
import '../widgets/common.dart';

/// The Wallpapers tab: every wallpaper, filtered by Live or festival.
class WallpapersScreen extends StatefulWidget {
  const WallpapersScreen({super.key, this.initialFilter});

  /// A festival ID a banner asked for, or null for All.
  final String? initialFilter;

  @override
  State<WallpapersScreen> createState() => _WallpapersScreenState();
}

class _WallpapersScreenState extends State<WallpapersScreen> {
  late String? _filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final now = nowOf(context);
    final walls = wallpapersTab(catalog, filter: _filter);
    final look = context.watch<LookController>().look;
    final inUse = look?.wallpaper.wallpaper?.id;
    final filters = <(String?, String)>[
      (null, 'All'),
      ('live', 'Live'),
      for (final f in wallpaperFestivals(catalog, now)) (f.id, f.name.en),
    ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: TabHeader(
            title: 'Wallpapers',
            subtitle: plural(walls.length, 'wallpaper'),
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
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ChipRow<String?>(
              options: filters,
              value: _filter,
              label: 'Filter wallpapers',
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
        ),
        if (walls.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyMessage(
              icon: Icons.image_not_supported_outlined,
              title: 'No wallpapers here yet',
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
                mainAxisExtent: 320,
              ),
              itemCount: walls.length,
              itemBuilder: (context, i) => WallpaperCard(
                wallpaper: walls[i],
                inUseId: inUse,
                onTap: () => StoreRoutes.wallpaper(context, walls[i].id),
              ),
            ),
          ),
      ],
    );
  }
}
