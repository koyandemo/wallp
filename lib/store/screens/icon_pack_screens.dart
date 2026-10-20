import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../catalog/catalog.dart';
import '../../core/store_palette.dart';
import '../../data/assets/download_manager.dart';
import '../../look/applied_look.dart';
import '../../look/look_controller.dart';
import '../../look/resolved_look.dart';
import '../../icons/themed_icon_painter.dart';
import '../../models/phone_theme.dart';
import '../../render/font_registry.dart';
import '../../launcher/launcher_icon.dart';
import '../../render/image_icons.dart';
import '../../services/icon_pack_service.dart';
import '../../services/launcher_service.dart';
import '../apply_flow.dart';
import '../logic/queries.dart';
import '../routes.dart';
import '../widgets/apply_button.dart';
import '../widgets/colour_field.dart';
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
    final shipped = shippedOf(context);
    final now = nowOf(context);
    final packs = iconPacksTab(catalog, filter: _filter, now: now);
    // Only a pack the user applied is "in use", not the suggested default.
    final looks = context.watch<LookController>();
    final inUse = looks.isApplied ? looks.look?.icons.pack.id : null;
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
                '${plural(packs.length, 'pack')} · your own app logos on each',
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
                final inApp = shipped.hasIconPack(p.id);
                return Semantics(
                  button: true,
                  label:
                      '${p.name.en} icon pack, $meta${inApp ? ', in the app' : ''}',
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
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name.en,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (inApp) ...[
                          const SizedBox(width: 8),
                          const BadgeChip(CardBadge.app),
                        ],
                      ],
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

/// Stand-ins for the phone's apps where there are none to show (the
/// store's cards, or a phone that isn't Android): one per kind of app, drawn
/// as its symbol on the pack's tile.
final sampleApps = [
  for (final key in GlyphKeys.all)
    InstalledApp(
      packageName: 'sample.$key',
      label: key[0].toUpperCase() + key.substring(1),
      symbol: _sampleSymbols[key],
    ),
];

const _sampleSymbols = <String, IconData>{
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

/// The sample app for [key] (`phone`, `messages`…).
InstalledApp sampleApp(String key) => sampleApps[GlyphKeys.all.indexOf(key)];

/// One pack, previewed on the phone's own apps: the tile shape, the app
/// name colour and font. Choices only preview; Apply puts them on wallp
/// Home.
class IconPackDetailScreen extends StatefulWidget {
  const IconPackDetailScreen({
    super.key,
    required this.packId,
    this.flow = const ApplyFlow(),
    this.apps = const IconPackService(),
    this.launcher = const LauncherService(),
  });

  final String packId;
  final ApplyFlow flow;

  /// Where the preview's apps come from.
  final IconPackService apps;

  /// Whether wallp is the home app: icons only show on wallp Home.
  final LauncherService launcher;

  @override
  State<IconPackDetailScreen> createState() => _IconPackDetailScreenState();
}

class _IconPackDetailScreenState extends State<IconPackDetailScreen> {
  IconShape? _shape;
  LabelColor? _labels;
  LabelFont? _labelFont;
  String _query = '';
  bool _applying = false;

  /// The phone's apps, or [sampleApps] if they can't be listed.
  List<InstalledApp> _apps = sampleApps;
  bool _started = false;

  /// Null until known, or off Android.
  bool? _isDefaultHome;

  /// The user may change the home app in Android's settings and come back.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Icon names redraw once the theme's downloaded font has loaded.
    FontRegistry.shared.addListener(_redraw);
    _lifecycle = AppLifecycleListener(onResume: _checkHome);
    _checkHome();
    _loadApps();
  }

  Future<void> _checkHome() async {
    if (!LauncherService.isSupported) return;
    final on = await widget.launcher.isDefaultHome();
    if (mounted) setState(() => _isDefaultHome = on);
  }

  static const _applyThemeFirst = 'Apply a theme first to use icon packs';

  void _redraw() {
    if (mounted) setState(() {});
  }

  Future<void> _loadApps() async {
    try {
      final apps = await widget.apps.installedApps();
      if (mounted && apps.isNotEmpty) setState(() => _apps = apps);
    } on Object {
      // Not Android, or the list failed: keep the sample apps.
    }
  }

  /// Fetches the pack's background tile for the preview (a few KB), so it
  /// shows without an Apply. Offline, the plain tile colour stands in.
  Future<void> _fetchBackground(IconPack pack) async {
    if (pack.assets.isEmpty) return;
    try {
      await context.read<DownloadManager>().ensure(
        pack.assets,
        label: pack.name.en,
      );
      _redraw();
    } on Object {
      // The tile colour stands in until it can download.
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    FontRegistry.shared.removeListener(_redraw);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pack = context.read<LookController>().look?.icons;
    if (_shape == null && pack?.pack.id == widget.packId) _shape = pack!.shape;
    _labels ??= pack?.labels ?? const LabelColor.theme();
    _labelFont ??= pack?.labelFont ?? LabelFont.theme;
  }

  /// Previews the user's change; [_apply] puts it on wallp Home.
  void _choose(
    IconPack pack, {
    IconShape? shape,
    LabelColor? labels,
    LabelFont? labelFont,
  }) {
    setState(() {
      _shape = shape ?? _shape;
      _labels = labels ?? _labels;
      _labelFont = labelFont ?? _labelFont;
    });
  }

  Future<void> _apply(IconPack pack) async {
    setState(() => _applying = true);
    await widget.flow.applyIconPack(
      context,
      pack,
      shape: _shape ?? pack.shape,
      labels: _labels,
      labelFont: _labelFont,
    );
    if (mounted) setState(() => _applying = false);
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
    if (!_started) {
      _started = true;
      _fetchBackground(pack);
    }
    final shape = _shape ?? pack.shape;
    // Icons only show on wallp Home, which a theme sets up: until one is
    // applied (and wallp is the home app), there's nothing to apply onto.
    final locked =
        !context.watch<LookController>().isApplied || _isDefaultHome == false;
    final inUse =
        context.watch<LookController>().isApplied &&
        context.read<LookController>().look?.icons.pack.id == pack.id;
    final applied = context.read<LookController>().look?.icons;
    // In use, and nothing picked here differs from what's on wallp Home.
    final upToDate =
        inUse &&
        applied!.shape == shape &&
        applied.labels == _labels &&
        applied.labelFont == _labelFont;
    final query = _query.trim().toLowerCase();
    final apps = [
      for (final a in _apps)
        if (a.label.toLowerCase().contains(query)) a,
    ];
    final look = context.watch<LookController>().look;
    final names = namesPreview(
      look,
      labelColourOf(_labels!, look),
      _labelFont!,
    );

    return Scaffold(
      appBar: AppBar(title: Text(pack.name.en)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
        children: [
          Text(
            '${catalog.festival(pack.festivalId)?.name.en ?? ''} · ${pack.style.en}',
            style: TextStyle(fontSize: 13, color: context.palette.muted),
          ),
          const SizedBox(height: 4),
          Text(
            locked
                ? '$_applyThemeFirst: they show on wallp Home, which a theme '
                      'sets up.'
                : inUse
                ? 'On wallp Home. Apply to update it with your changes.'
                : 'Pick a shape and name colour, then apply to wallp Home.',
            style: TextStyle(
              fontSize: 13,
              color: inUse ? context.palette.brand : context.palette.muted,
            ),
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
          Semantics(
            label: 'Tile shape',
            container: true,
            child: Row(
              children: [
                for (final (option, label) in const [
                  (IconShape.squircle, 'Squircle'),
                  (IconShape.circle, 'Circle'),
                  (IconShape.square, 'Square'),
                  (IconShape.leaf, 'Leaf'),
                ])
                  Expanded(
                    child: Opacity(
                      opacity: locked ? 0.45 : 1,
                      child: _ShapeOption(
                        label: label,
                        selected: shape == option,
                        onTap: locked
                            ? () => showToast(context, _applyThemeFirst)
                            : () => _choose(pack, shape: option),
                        child: PackIcon(
                          pack: pack,
                          app: _apps.first,
                          shape: option,
                          size: 56,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'App name colour',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.palette.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Everywhere on wallp Home: home screen, dock, app drawer and app lists',
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
          const SizedBox(height: 8),
          _LabelColours(
            pack: pack,
            shape: shape,
            apps: _apps,
            value: _labels!,
            onChanged: (l) => _choose(pack, labels: l),
            font: _labelFont!,
            onFont: (f) => _choose(pack, labelFont: f),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Find an app',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (q) => setState(() => _query = q),
          ),
          const SizedBox(height: 12),
          Text(
            apps.length == _apps.length
                ? plural(apps.length, 'app')
                : '${apps.length} of ${_apps.length}',
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
          if (apps.isEmpty)
            const EmptyMessage(
              icon: Icons.search_off_rounded,
              title: 'No app by that name',
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
                for (final app in apps)
                  Column(
                    children: [
                      PackIcon(pack: pack, app: app, shape: shape, size: 56),
                      const SizedBox(height: 4),
                      Text(
                        app.label,
                        // In the App name colour and font being picked.
                        style: names.appNameStyle(
                          const TextStyle(fontSize: 11),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
              ],
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: locked
          ? null
          : ApplyButton(
              onPressed: () => _apply(pack),
              state: _applying
                  ? ApplyState.applying
                  : upToDate
                  ? ApplyState.applied
                  : ApplyState.ready,
              label: _applying
                  ? 'Applying…'
                  : upToDate
                  ? 'Applied'
                  : inUse
                  ? 'Apply changes'
                  : 'Apply icons',
            ),
    );
  }
}

/// A pack's Phone icon, for list rows.
class PackSample extends StatelessWidget {
  const PackSample({super.key, required this.pack, required this.size});

  final IconPack pack;
  final double size;

  @override
  Widget build(BuildContext context) => PackIcon(
    pack: pack,
    app: sampleApp('phone'),
    shape: pack.shape,
    size: size,
  );
}

/// [app] in [pack], exactly as wallp Home draws it: a painted pack's themed
/// icon, or the app's own logo (a sample app: its symbol) on a downloaded
/// pack's tile, which shows its plain colour until the tile picture is on
/// the phone.
class PackIcon extends StatelessWidget {
  const PackIcon({
    super.key,
    required this.pack,
    required this.app,
    required this.shape,
    required this.size,
  });

  final IconPack pack;
  final InstalledApp app;
  final IconShape shape;
  final double size;

  @override
  Widget build(BuildContext context) {
    final painter = SceneKind.values.asNameMap()[pack.painter];
    if (pack.kind == IconPackKind.painted && painter != null) {
      return ThemedIcon(
        style: painter,
        accent: Color(pack.ring.argb),
        glyph: app.glyph ?? (app.icon == null ? Icons.apps_rounded : null),
        appIcon: app.icon,
        size: size,
        shape: shape,
      );
    }
    return PackTileIcon(
      pack: ImageIconPack.of(pack, shape),
      app: app,
      size: size,
    );
  }
}

/// One choice in the shape picker: a real icon in that shape, its name
/// under it, and a ring when selected.
class _ShapeOption extends StatelessWidget {
  const _ShapeOption({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: label,
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(4),
          // Scales down on narrow phones instead of overflowing.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            // The icon shows the shape; the name stays for screen readers.
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected ? p.brand : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks the colour of app names on wallp Home, over a strip that looks
/// like it: the theme's sky, four icons, their names.
class _LabelColours extends StatelessWidget {
  const _LabelColours({
    required this.pack,
    required this.shape,
    required this.apps,
    required this.value,
    required this.onChanged,
    required this.font,
    required this.onFont,
  });

  final IconPack pack;
  final IconShape shape;

  /// The first four make the preview strip.
  final List<InstalledApp> apps;
  final LabelColor value;
  final ValueChanged<LabelColor> onChanged;
  final LabelFont font;
  final ValueChanged<LabelFont> onFont;

  static const _white = HexColor('#FFFFFF');
  static const _dark = HexColor('#1B1B1F');

  /// Names readable on most wallpapers, plus the accent swatches.
  static const _swatches = ['#FFFFFF', '#1B1B1F', ...colourSwatches];

  Future<void> _custom(BuildContext context, HexColor start) async {
    var picked = start;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColourField(
                label: 'Name colour',
                value: picked,
                swatches: _swatches,
                onChanged: (c) => setSheet(() => picked = c),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Use this colour'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok ?? false) onChanged(LabelColor.fixed(picked));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Redraw the names once the theme's downloaded font has loaded.
    listenable: FontRegistry.shared,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final look = context.watch<LookController>().look;
    final themeColour = look?.theme.labelColor ?? _white;
    final accent = look?.accent.primary ?? HexColor(pack.ring.hex);
    final shown = value.isAccent ? accent : (value.hex ?? themeColour);
    final isCustom =
        value.hex != null && value.hex != _white && value.hex != _dark;
    final preview = namesPreview(look, Color(shown.argb), font);

    Widget dot(
      String label,
      Color colour,
      bool selected,
      VoidCallback onTap, {
      IconData? icon,
    }) => Semantics(
      label: label,
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? context.palette.brand
                        : context.palette.muted.withValues(alpha: 0.35),
                    width: selected ? 3 : 1,
                  ),
                ),
                child: icon == null
                    ? null
                    : Icon(
                        icon,
                        size: 18,
                        color: colour.computeLuminance() > 0.5
                            ? Colors.black87
                            : Colors.white,
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? context.palette.text
                      : context.palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'App names preview',
          container: true,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [preview.palette.deep, preview.palette.background],
              ),
            ),
            child: Row(
              children: [
                for (final app in apps.take(4))
                  Expanded(
                    child: Column(
                      children: [
                        PackIcon(pack: pack, app: app, shape: shape, size: 48),
                        const SizedBox(height: 6),
                        Text(
                          app.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: preview.labelStyle(
                            TextStyle(
                              fontSize: 12,
                              color: preview.labelColor,
                              shadows: preview.labelShadows,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<LabelFont>(
          // No tick on the selected option: its fill shows it.
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: LabelFont.theme,
              label: SegmentLabel('Theme font'),
            ),
            ButtonSegment(
              value: LabelFont.system,
              label: SegmentLabel('System font'),
            ),
          ],
          selected: {font},
          onSelectionChanged: (s) => onFont(s.single),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final d in [
              dot(
                'Theme',
                Color(themeColour.argb),
                value.isTheme,
                () => onChanged(const LabelColor.theme()),
                icon: Icons.auto_awesome_rounded,
              ),
              dot(
                'Accent',
                Color(accent.argb),
                value.isAccent,
                () => onChanged(const LabelColor.accent()),
              ),
              dot(
                'White',
                Color(_white.argb),
                value.hex == _white,
                () => onChanged(const LabelColor.fixed(_white)),
              ),
              dot(
                'Dark',
                Color(_dark.argb),
                value.hex == _dark,
                () => onChanged(const LabelColor.fixed(_dark)),
              ),
              dot(
                'Custom',
                isCustom ? Color(value.hex!.argb) : context.palette.surface,
                isCustom,
                () => _custom(context, isCustom ? value.hex! : shown),
                icon: Icons.colorize_rounded,
              ),
            ])
              Expanded(child: d),
          ],
        ),
      ],
    );
  }
}

/// App names as wallp Home would draw them with [colour] and [font], on
/// [look]'s theme colours: for previews on the icon pack page.
PhoneTheme namesPreview(AppliedLook? look, Color colour, LabelFont font) {
  final palette = look?.theme.palette;
  return PhoneTheme(
    id: 'labels',
    categoryId: '',
    name: '',
    scene: null,
    palette: ThemePalette(
      background: Color(
        (palette?.background ?? const HexColor('#20242C')).argb,
      ),
      deep: Color((palette?.deep ?? const HexColor('#11141A')).argb),
      surface: Colors.black,
      text: Colors.white,
      textMuted: Colors.white70,
      accentOptions: const [],
    ),
    displayFont: 'Space Grotesk',
    bodyFont: look == null
        ? 'Space Grotesk'
        : look.fonts[look.theme.fonts.labels]?.family ?? 'Space Grotesk',
    event: null,
    labelColor: colour,
    systemLabels: font == LabelFont.system,
  );
}

/// The colour [labels] stands for with [look] applied.
Color labelColourOf(LabelColor labels, AppliedLook? look) {
  final hex = labels.isAccent
      ? look?.accent.primary
      : labels.hex ?? look?.theme.labelColor;
  return hex == null ? Colors.white : Color(hex.argb);
}
