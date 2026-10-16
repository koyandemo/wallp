import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../look/look_controller.dart';
import '../../widgets/theme_preview.dart';
import '../apply_flow.dart';
import '../logic/previews.dart';
import '../state/user_store.dart';
import '../widgets/common.dart';

/// One wallpaper, full screen, with the lock or home screen on top, and
/// "Set wallpaper".
class WallpaperDetailScreen extends StatefulWidget {
  const WallpaperDetailScreen({
    super.key,
    required this.wallpaperId,
    this.flow = const ApplyFlow(),
  });

  final String wallpaperId;
  final ApplyFlow flow;

  @override
  State<WallpaperDetailScreen> createState() => _WallpaperDetailScreenState();
}

class _WallpaperDetailScreenState extends State<WallpaperDetailScreen> {
  PhoneScreen _screen = PhoneScreen.lock;
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final wallpaper = catalog.wallpaper(widget.wallpaperId);
    if (wallpaper == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyMessage(
          icon: Icons.image_not_supported_outlined,
          title: 'This wallpaper is no longer in the store',
        ),
      );
    }
    final user = context.watch<UserStore>();
    final fav = user.isFavouriteWallpaper(wallpaper.id);
    final inUse =
        context.watch<LookController>().look?.wallpaper.wallpaper?.id ==
        wallpaper.id;
    final preview = wallpaperPreviewOf(wallpaper, catalog, nowOf(context));
    final festival = catalog.festival(wallpaper.festivalId)?.name.en;

    return Scaffold(
      appBar: AppBar(
        title: Text(wallpaper.name.en),
        actions: [
          IconButton(
            tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
            isSelected: fav,
            onPressed: () => user.toggleWallpaper(wallpaper.id),
            icon: Icon(
              fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 390 / 844,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: ThemePreview(
                      theme: preview,
                      now: nowOf(context),
                      screen: _screen,
                      animate: wallpaper.isLive,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text(
            [
              ?festival,
              if (wallpaper.isLive) 'Live wallpaper' else 'Still wallpaper',
            ].join(' · '),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          // Wraps rather than overflows with large text.
          Wrap(
            alignment: WrapAlignment.center,
            runSpacing: 6,
            children: [
              for (final s in const [PhoneScreen.lock, PhoneScreen.home])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Text(
                      s == PhoneScreen.lock ? 'Lock screen' : 'Home screen',
                    ),
                    selected: _screen == s,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _screen = s),
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _applying
                  ? null
                  : () async {
                      setState(() => _applying = true);
                      await widget.flow.applyWallpaper(context, wallpaper);
                      if (mounted) setState(() => _applying = false);
                    },
              child: Text(
                _applying
                    ? 'Setting…'
                    : inUse
                    ? 'In use · set again'
                    : 'Set wallpaper',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
