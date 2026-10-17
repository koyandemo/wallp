import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../catalog/catalog.dart';
import '../../core/store_palette.dart';
import '../../data/assets/asset_cache.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../look/accent_choices.dart';
import '../../look/accent_paint.dart';
import '../../look/applied_look.dart';
import '../../look/look_controller.dart';
import '../../widgets/theme_preview.dart';
import '../apply_flow.dart';
import '../logic/previews.dart';
import '../logic/queries.dart';
import '../routes.dart';
import '../state/user_store.dart';
import '../state/live_wallpaper_status.dart';
import '../widgets/common.dart';

/// One theme: a live preview of its lock and home screens, its colours and
/// accents, what it includes, and Apply.
class ThemeDetailScreen extends StatefulWidget {
  const ThemeDetailScreen({
    super.key,
    required this.themeId,
    this.flow = const ApplyFlow(),
  });

  final String themeId;
  final ApplyFlow flow;

  @override
  State<ThemeDetailScreen> createState() => _ThemeDetailScreenState();
}

class _ThemeDetailScreenState extends State<ThemeDetailScreen> {
  late Future<ThemeDetail> _loading = _load();
  PhoneScreen _screen = PhoneScreen.lock;
  String? _variant;
  Accent? _accent;
  int? _missingBytes;
  bool _applying = false;

  Future<ThemeDetail> _load() async {
    final detail = await context.read<CatalogRepository>().theme(
      widget.themeId,
    );
    // Start where the user left off if this theme is applied.
    final look = mounted ? context.read<LookController>() : null;
    final applied = look?.isApplied == true && look!.look!.theme.id == detail.id
        ? look.look
        : null;
    // The applied look's colours, else the theme's own; and the accent
    // last used or picked for this theme.
    _variant = applied?.variantId;
    _accent =
        applied?.accent ??
        (mounted ? context.read<UserStore>().accentFor(detail.id) : null);
    _refreshSize(detail);
    return detail;
  }

  Future<void> _refreshSize(ThemeDetail detail) async {
    final catalog = context.read<CatalogRepository>().catalog;
    final bytes = await context.read<AssetCache>().missingBytes(
      catalog.assetsFor(detail),
    );
    if (mounted) setState(() => _missingBytes = bytes);
  }

  /// Shows [a] and saves it as this theme's accent choice.
  void _pick(ThemeDetail d, Accent a) {
    setState(() => _accent = a);
    context.read<UserStore>().rememberAccent(d.id, a);
  }

  Accent _accentFor(ThemeDetail d) =>
      _accent ?? AppliedLook.defaultAccentFor(d, _variant);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ThemeDetail>(
      future: _loading,
      builder: (context, snap) {
        final summary = catalogOf(context).theme(widget.themeId);
        final title = summary?.name.en ?? 'Theme';
        if (snap.hasError) {
          final error = snap.error;
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: EmptyMessage(
              icon: Icons.cloud_off_rounded,
              title: error is ThemeUnavailableException && error.notListed
                  ? 'This theme is no longer in the store'
                  : "Couldn't open $title",
              message: error is ThemeUnavailableException && error.isOffline
                  ? 'Check your connection and try again.'
                  : 'Try again in a moment.',
            ),
            bottomNavigationBar:
                error is ThemeUnavailableException && error.notListed
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: OutlinedButton(
                        onPressed: () => setState(() => _loading = _load()),
                        child: const Text('Try again'),
                      ),
                    ),
                  ),
          );
        }
        final detail = snap.data;
        if (detail == null || summary == null) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: Center(
              child: CircularProgressIndicator(color: context.palette.brand),
            ),
          );
        }
        return _build(context, summary, detail);
      },
    );
  }

  Widget _build(
    BuildContext context,
    ThemeSummary summary,
    ThemeDetail detail,
  ) {
    final catalog = catalogOf(context);
    final now = nowOf(context);
    final user = context.watch<UserStore>();
    final looks = context.watch<LookController>();
    final accent = _accentFor(detail);
    // The icon shape and app names the user picked on the icon pack page.
    final preview = withUserIcons(
      previewOf(
        summary,
        catalog,
        now,
        detail: detail,
        variantId: _variant,
        accent: accent,
      ),
      looks.look,
      accent.color,
    );
    final fav = user.isFavouriteTheme(detail.id);
    final isApplied = looks.isApplied && looks.look?.theme.id == detail.id;
    final pack = catalog.iconPack(detail.iconPackId);
    final font = catalog.font(detail.fonts.display);
    final wallpaper = detail.wallpaperIds
        .map(catalog.wallpaper)
        .nonNulls
        .firstOrNull;
    final missing = _missingBytes;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail.name.en),
        actions: [
          IconButton(
            tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
            isSelected: fav,
            onPressed: () => user.toggleTheme(detail.id),
            icon: Icon(
              fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: fav ? accent.color : null,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 120),
        children: [
          Center(
            child: Container(
              width: 236,
              height: 440,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: context.palette.surface2, width: 6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: ThemePreview(
                  theme: preview,
                  now: now,
                  screen: _screen,
                  animate: previewsAnimate(context),
                  accent: accent.color,
                  accentGradient: accent.gradient,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Accent',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.palette.text,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final picked = await StoreRoutes.accentPicker(
                    context,
                    detail,
                    variantId: _variant,
                    current: accent,
                  );
                  if (picked != null) _pick(detail, picked);
                },
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.brand,
                  minimumSize: const Size(44, 44),
                ),
                icon: const Icon(Icons.palette_outlined, size: 18),
                label: const Text('Gradients & custom'),
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final a in detail.accents.take(6))
                _Swatch(
                  label: a.name.en,
                  selected: sameLook(a, accent),
                  fill: a.decoration(shape: BoxShape.circle),
                  onTap: () => _pick(detail, a),
                ),
              // A gradient or custom accent from "Gradients & custom".
              if (!detail.accents.any((a) => sameLook(a, accent)))
                _Swatch(
                  label: accent.name.en,
                  selected: true,
                  fill: accent.decoration(shape: BoxShape.circle),
                  onTap: () {},
                ),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            'This theme includes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.palette.text,
            ),
          ),
          const SizedBox(height: 10),
          // Material, not a coloured box: the rows' ink must show.
          Material(
            color: context.palette.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: context.palette.outline),
            ),
            child: Column(
              children: [
                _IncludesRow(
                  icon: Icons.wallpaper_rounded,
                  title: detail.isLive ? 'Live wallpaper' : 'Wallpaper',
                  subtitle: detail.isLive
                      ? 'Animated, on the lock and home screen'
                      : 'For the lock and home screen',
                  onTap: wallpaper == null
                      ? null
                      : () => StoreRoutes.wallpaper(context, wallpaper.id),
                ),
                if (pack != null)
                  _IncludesRow(
                    icon: Icons.apps_rounded,
                    title: '${pack.name.en} icons',
                    subtitle: 'Every app on wallp Home',
                    onTap: () => StoreRoutes.iconPack(context, pack.id),
                  ),
                if (font != null && font.listed)
                  _IncludesRow(
                    icon: Icons.text_fields_rounded,
                    title: '${font.family} clock font',
                    subtitle: 'Lock screen and home clock',
                    onTap: () => StoreRoutes.font(context, font.id),
                    last: true,
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _applying ? null : () => _openApplySheet(detail),
              child: Text(
                _applying
                    ? 'Applying…'
                    : isApplied
                    ? 'Applied · apply again'
                    : missing == null || missing == 0
                    ? 'Apply theme'
                    : 'Apply · ${formatBytes(missing)}',
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

  Future<void> _openApplySheet(ThemeDetail detail) async {
    final option = await showModalBottomSheet<ApplyOption>(
      context: context,
      backgroundColor: context.palette.surface,
      showDragHandle: true,
      builder: (_) => _ApplySheet(theme: detail),
    );
    if (option == null || !mounted) return;
    setState(() => _applying = true);
    await widget.flow.applyTheme(
      context,
      detail,
      option: option,
      variantId: _variant,
      accent: _accentFor(detail),
    );
    if (!mounted) return;
    setState(() => _applying = false);
    _refreshSize(detail);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.selected,
    required this.fill,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final BoxDecoration fill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? context.palette.text : Colors.transparent,
              width: 3,
            ),
          ),
          child: DecoratedBox(decoration: fill),
        ),
      ),
    );
  }
}

class _IncludesRow extends StatelessWidget {
  const _IncludesRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: context.palette.outline)),
      ),
      child: ListTile(
        minTileHeight: 64,
        onTap: onTap,
        leading: Icon(icon, color: context.palette.brand),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.palette.text,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        ),
        trailing: onTap == null
            ? null
            : Icon(Icons.chevron_right_rounded, color: context.palette.muted),
      ),
    );
  }
}

/// Whole theme / Wallpaper only / Clock font only.
class _ApplySheet extends StatefulWidget {
  const _ApplySheet({required this.theme});

  final ThemeDetail theme;

  @override
  State<_ApplySheet> createState() => _ApplySheetState();
}

class _ApplySheetState extends State<_ApplySheet> {
  ApplyOption _option = ApplyOption.wholeTheme;

  @override
  Widget build(BuildContext context) {
    final clockFont = catalogOf(context).font(widget.theme.fonts.display);
    final font = clockFont?.family ?? 'the clock font';
    final options = [
      (
        ApplyOption.wholeTheme,
        'Whole theme',
        'Wallpaper, icons and clock font',
      ),
      (ApplyOption.wallpaperOnly, 'Wallpaper only', 'Keep your icons and font'),
      // A hidden font can't be picked on its own.
      if (clockFont?.listed ?? true)
        (
          ApplyOption.clockFontOnly,
          'Clock font only',
          '$font on the lock and home clock',
        ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apply ${widget.theme.name.en}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.palette.text,
              ),
            ),
            const SizedBox(height: 10),
            RadioGroup<ApplyOption>(
              groupValue: _option,
              onChanged: (o) => setState(() => _option = o!),
              child: Column(
                children: [
                  for (final (option, title, sub) in options)
                    RadioListTile<ApplyOption>(
                      value: option,
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        sub,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.muted,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _option),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
