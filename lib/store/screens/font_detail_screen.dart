import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/store_palette.dart';
import '../../look/applied_look.dart';
import '../../look/look_controller.dart';
import '../../look/resolved_look.dart';
import '../../render/font_registry.dart';
import '../../widgets/theme_preview.dart';
import '../apply_flow.dart';
import '../widgets/common.dart';

/// One clock font: a lock and home preview, size, where it shows, Apply.
class FontDetailScreen extends StatefulWidget {
  const FontDetailScreen({
    super.key,
    required this.fontId,
    this.flow = const ApplyFlow(),
  });

  final String fontId;
  final ApplyFlow flow;

  @override
  State<FontDetailScreen> createState() => _FontDetailScreenState();
}

class _FontDetailScreenState extends State<FontDetailScreen> {
  ClockSize _size = ClockSize.medium;
  bool _lock = true, _home = true, _labels = false;
  bool _applying = false;
  PhoneScreen _screen = PhoneScreen.lock;

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FontRegistry.shared.removeListener(_redraw);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Redraw in the font once it has loaded.
    FontRegistry.shared.addListener(_redraw);
    // Start from the clock the user has now.
    final clock = context.read<LookController>().look?.clock;
    if (clock != null) {
      _size = clock.size;
      _lock = clock.places.lockScreen;
      _home = clock.places.homeClock;
      _labels = clock.places.appLabels;
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final font = catalog.font(widget.fontId);
    if (font == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyMessage(
          icon: Icons.font_download_off_outlined,
          title: 'This font is no longer in the store',
        ),
      );
    }
    final look = context.watch<LookController>().look;
    final now = nowOf(context);
    // The user's look with this font where the switches put it: what Apply
    // would give. With every switch off, the look as it is.
    final candidate = look == null || !(_lock || _home || _labels)
        ? look
        : look.withClockFont(
            font,
            at: now,
            size: _size,
            places: ClockPlaces(
              lockScreen: _lock,
              homeClock: _home,
              appLabels: _labels,
            ),
          );
    final r = candidate == null ? null : ResolvedLook.of(candidate, now);
    final places = [
      if (_lock) 'lock screen clock',
      if (_home) 'wallp Home clock',
      if (_labels) 'app labels',
    ];

    return Scaffold(
      appBar: AppBar(title: Text(font.family)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
        children: [
          if (r != null) ...[
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
                    theme: _screen == PhoneScreen.lock
                        ? r.lockTheme
                        : r.homeTheme,
                    now: now,
                    screen: _screen,
                    accent: r.accent,
                    accentGradient: r.accentGradient,
                    clockColor: r.clockColor,
                    clockScale: r.clockScale,
                    clockGradient: r.clockGradient,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final (s, label, icon) in const [
                  (PhoneScreen.lock, 'Lock screen', Icons.lock_outline_rounded),
                  (PhoneScreen.home, 'Home screen', Icons.home_outlined),
                ])
                  ChoiceChip(
                    avatar: Icon(icon, size: 18),
                    label: Text(label),
                    showCheckmark: false,
                    selected: _screen == s,
                    onSelected: (_) => setState(() => _screen = s),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Size',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.palette.text,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ClockSize>(
            // The size shows on the lock clock.
            // No tick on the selected option: its fill shows it.
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ClockSize.small,
                label: SegmentLabel('Small'),
              ),
              ButtonSegment(
                value: ClockSize.medium,
                label: SegmentLabel('Medium'),
              ),
              ButtonSegment(
                value: ClockSize.large,
                label: SegmentLabel('Large'),
              ),
            ],
            selected: {_size},
            onSelectionChanged: (s) => setState(() {
              _size = s.single;
              _screen = PhoneScreen.lock;
            }),
          ),
          const SizedBox(height: 20),
          Text(
            'Use it on',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.palette.text,
            ),
          ),
          // Each switch shows its screen in the preview above.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_outline_rounded),
            title: const Text('Lock screen clock'),
            subtitle: const Text('With the live wallpaper on'),
            value: _lock,
            onChanged: (v) => setState(() {
              _lock = v;
              _screen = PhoneScreen.lock;
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.home_outlined),
            title: const Text('wallp Home clock'),
            subtitle: const Text('The clock above your icons'),
            value: _home,
            onChanged: (v) => setState(() {
              _home = v;
              _screen = PhoneScreen.home;
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.label_outline_rounded),
            title: const Text('App labels'),
            subtitle: const Text('Names under icons on wallp Home'),
            value: _labels,
            onChanged: (v) => setState(() {
              _labels = v;
              _screen = PhoneScreen.home;
            }),
          ),
          if (font.fallbackFor.containsKey('my'))
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Burmese app names use Padauk: this font has no Myanmar letters.',
                style: TextStyle(fontSize: 12, color: context.palette.muted),
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
              onPressed: _applying
                  ? null
                  : () async {
                      if (places.isEmpty) {
                        showToast(
                          context,
                          'Turn on at least one place to use ${font.family}',
                        );
                        return;
                      }
                      setState(() => _applying = true);
                      await widget.flow.applyFont(
                        context,
                        font,
                        size: _size,
                        places: ClockPlaces(
                          lockScreen: _lock,
                          homeClock: _home,
                          appLabels: _labels,
                        ),
                      );
                      if (mounted) setState(() => _applying = false);
                    },
              child: Text(
                _applying ? 'Applying…' : 'Apply ${font.family}',
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
