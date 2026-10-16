import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../catalog/catalog.dart';
import '../../core/store_palette.dart';
import '../../data/assets/asset_cache.dart';
import '../../look/look_controller.dart';
import '../../look/resolved_look.dart';
import '../../render/scene_assets.dart';
import '../../services/launcher_service.dart';
import '../apply_flow.dart';
import '../logic/queries.dart';
import '../routes.dart';
import '../widgets/common.dart';
import 'pin_shortcuts_screen.dart';

/// Every icon pack, by New or festival.
class IconPacksScreen extends StatefulWidget {
  const IconPacksScreen({super.key, this.initialFilter});

  final String? initialFilter;

  @override
  State<IconPacksScreen> createState() => _IconPacksScreenState();
}

class _IconPacksScreenState extends State<IconPacksScreen> {
  late String? _filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final now = nowOf(context);
    final packs = iconPacksTab(catalog, filter: _filter, now: now);
    final inUse = context.watch<LookController>().look?.icons.pack.id;
    final filters = <(String?, String)>[
      (null, 'All'),
      ('new', 'New'),
      for (final f in festivalsBySoonest(catalog, now))
        if (catalog.iconPacks.any((p) => p.festivalId == f.id))
          (f.id, f.name.en),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Icon packs')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                '${plural(packs.length, 'pack')} · ${GlyphKeys.all.length} icons in each',
                style: TextStyle(fontSize: 13, color: context.palette.muted),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ChipRow<String?>(
                options: filters,
                value: _filter,
                label: 'Filter icon packs',
                onChanged: (f) => setState(() => _filter = f),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            sliver: SliverList.separated(
              itemCount: packs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = packs[i];
                final festival = catalog.festival(p.festivalId)?.name.en ?? '';
                final meta = p.id == inUse
                    ? 'In use'
                    : '${p.isNew(now) ? 'New · ' : ''}$festival · ${p.style.en}';
                return Semantics(
                  button: true,
                  label: '${p.name.en} icon pack, $meta',
                  excludeSemantics: true,
                  child: ListTile(
                    minTileHeight: 72,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: p.id == inUse
                            ? context.palette.brand
                            : context.palette.outline,
                      ),
                    ),
                    tileColor: context.palette.surface,
                    leading: PackSample(pack: p, size: 44),
                    title: Text(
                      p.name.en,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      meta,
                      style: TextStyle(
                        color: p.id == inUse
                            ? context.palette.brand
                            : context.palette.muted,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => StoreRoutes.iconPack(context, p.id),
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

/// One pack: every icon (searchable), the tile shape, and Apply.
class IconPackDetailScreen extends StatefulWidget {
  const IconPackDetailScreen({
    super.key,
    required this.packId,
    this.flow = const ApplyFlow(),
  });

  final String packId;
  final ApplyFlow flow;

  @override
  State<IconPackDetailScreen> createState() => _IconPackDetailScreenState();
}

class _IconPackDetailScreenState extends State<IconPackDetailScreen> {
  IconShape? _shape;
  String _query = '';
  bool _applying = false;
  int? _missing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pack = context.read<LookController>().look?.icons;
    if (_shape == null && pack?.pack.id == widget.packId) _shape = pack!.shape;
  }

  Future<void> _refreshSize(IconPack pack) async {
    final bytes = await context.read<AssetCache>().missingBytes(
      pack.glyphs.values,
    );
    if (mounted && bytes != _missing) setState(() => _missing = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final pack = catalog.iconPack(widget.packId);
    if (pack == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyMessage(
          icon: Icons.apps_outage_rounded,
          title: 'This icon pack is no longer in the store',
        ),
      );
    }
    if (_missing == null) _refreshSize(pack);
    final shape = _shape ?? pack.shape;
    final inUse =
        context.watch<LookController>().look?.icons.pack.id == pack.id;
    final keys = [
      for (final k in GlyphKeys.all)
        if (k.contains(_query.trim().toLowerCase())) k,
    ];
    final missing = _missing ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(pack.name.en)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
        children: [
          Text(
            '${GlyphKeys.all.length} icons · ${catalog.festival(pack.festivalId)?.name.en ?? ''} · ${pack.style.en}',
            style: TextStyle(fontSize: 13, color: context.palette.muted),
          ),
          const SizedBox(height: 16),
          Text(
            'Tile shape',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.palette.text,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<IconShape>(
            segments: const [
              ButtonSegment(value: IconShape.squircle, label: Text('Squircle')),
              ButtonSegment(value: IconShape.circle, label: Text('Circle')),
              ButtonSegment(value: IconShape.square, label: Text('Square')),
              ButtonSegment(value: IconShape.leaf, label: Text('Leaf')),
            ],
            selected: {shape},
            onSelectionChanged: (s) => setState(() => _shape = s.single),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Find an icon',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (q) => setState(() => _query = q),
          ),
          const SizedBox(height: 12),
          Text(
            keys.length == GlyphKeys.all.length
                ? '${keys.length} icons'
                : '${keys.length} of ${GlyphKeys.all.length}',
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
          const SizedBox(height: 8),
          if (inUse && LauncherService.isSupported) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              // For people who keep another home screen app.
              onPressed: () {
                final looks = context.read<LookController>();
                final r = ResolvedLook.of(looks.look!, nowOf(context));
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PinShortcutsScreen(
                      theme: r.homeTheme,
                      accent: r.accent,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.add_to_home_screen_rounded),
              label: const Text('Add icons to your home screen'),
            ),
            const SizedBox(height: 12),
          ],
          if (keys.isEmpty)
            const EmptyMessage(
              icon: Icons.search_off_rounded,
              title: 'No icon by that name',
            )
          else
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 8,
              childAspectRatio: 0.8,
              children: [
                for (final key in keys)
                  Column(
                    children: [
                      PackIcon(
                        pack: pack,
                        glyphKey: key,
                        shape: shape,
                        size: 56,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        key[0].toUpperCase() + key.substring(1),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.palette.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
                      await widget.flow.applyIconPack(
                        context,
                        pack,
                        shape: shape,
                      );
                      if (!mounted) return;
                      setState(() => _applying = false);
                      _refreshSize(pack);
                    },
              child: Text(
                _applying
                    ? 'Applying…'
                    : inUse
                    ? 'In use · apply again'
                    : missing > 0
                    ? 'Apply icon pack · ${formatBytes(missing)}'
                    : 'Apply icon pack',
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

/// Three icons of [pack], for list rows.
class PackSample extends StatelessWidget {
  const PackSample({super.key, required this.pack, required this.size});

  final IconPack pack;
  final double size;

  @override
  Widget build(BuildContext context) =>
      PackIcon(pack: pack, glyphKey: 'phone', shape: pack.shape, size: size);
}

/// One icon of a pack: the downloaded picture if it's on the phone, else
/// the pack's colours around a stand-in symbol (not downloaded yet).
class PackIcon extends StatelessWidget {
  const PackIcon({
    super.key,
    required this.pack,
    required this.glyphKey,
    required this.shape,
    required this.size,
  });

  final IconPack pack;
  final String glyphKey;
  final IconShape shape;
  final double size;

  static const _symbols = <String, IconData>{
    'phone': Icons.phone_rounded,
    'messages': Icons.chat_bubble_rounded,
    'camera': Icons.photo_camera_rounded,
    'maps': Icons.place_rounded,
    'music': Icons.music_note_rounded,
    'mail': Icons.mail_rounded,
    'photos': Icons.photo_rounded,
    'clock': Icons.schedule_rounded,
    'calendar': Icons.calendar_month_rounded,
    'settings': Icons.settings_rounded,
    'browser': Icons.public_rounded,
    'weather': Icons.cloud_rounded,
    'notes': Icons.sticky_note_2_rounded,
    'calculator': Icons.calculate_rounded,
    'wallet': Icons.account_balance_wallet_rounded,
    'store': Icons.shopping_bag_rounded,
    'video': Icons.videocam_rounded,
    'contacts': Icons.contacts_rounded,
    'files': Icons.folder_rounded,
    'health': Icons.favorite_rounded,
  };

  BorderRadius get _radius => switch (shape) {
    IconShape.circle => BorderRadius.circular(size / 2),
    IconShape.square => BorderRadius.circular(size * 0.12),
    IconShape.squircle => BorderRadius.circular(size * 0.3),
    IconShape.leaf => BorderRadius.only(
      topLeft: Radius.circular(size / 2),
      topRight: Radius.circular(size / 2),
      bottomRight: Radius.circular(size / 2),
      bottomLeft: Radius.circular(size * 0.12),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final picture = pack.glyphs[glyphKey];
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: pack.tile == null ? Colors.transparent : Color(pack.tile!.argb),
        borderRadius: _radius,
        border: Border.all(color: Color(pack.ring.argb), width: 2),
      ),
      child: Icon(
        _symbols[glyphKey] ?? Icons.apps_rounded,
        color: Color(pack.glyph.argb),
        size: size * 0.5,
      ),
    );
    if (picture == null) return fallback;
    return FutureBuilder(
      future: SceneAssets.of(context).image(picture),
      builder: (context, snap) => snap.data == null
          ? fallback
          : ClipRRect(
              borderRadius: _radius,
              child: SizedBox.square(
                dimension: size,
                child: RawImage(
                  image: snap.data,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
    );
  }
}
