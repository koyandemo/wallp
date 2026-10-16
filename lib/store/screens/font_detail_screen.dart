import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../catalog/catalog.dart';
import '../../core/app_colors.dart';
import '../../core/date_format.dart';
import '../../look/applied_look.dart';
import '../../look/look_controller.dart';
import '../../render/font_registry.dart';
import '../apply_flow.dart';
import '../widgets/common.dart';

/// One clock font: size, colour, where it shows, and Apply.
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
  ClockColor _color = const ClockColor.accent();
  bool _lock = true, _home = true, _labels = false;
  bool _applying = false;

  static const _colours = [
    ('Cream', HexColor('#F3E6C4')),
    ('White', HexColor('#F5F1EA')),
    ('Purple', HexColor('#A970FF')),
  ];

  @override
  void initState() {
    super.initState();
    // Start from the clock the user has now.
    final clock = context.read<LookController>().look?.clock;
    if (clock != null) {
      _size = clock.size;
      _color = clock.color;
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
    final accent = look == null
        ? AppColors.brand
        : Color(look.accent.primary.argb);
    final clockColor = _color.isAccent
        ? accent
        : _color.isText
        ? AppColors.textPrimary
        : Color(_color.hex!.argb);
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
          Container(
            height: 200,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              DateFormatX.clock(
                nowOf(context),
                use24h: MediaQuery.alwaysUse24HourFormatOf(context),
              ),
              style: FontRegistry.shared.style(
                font.family,
                TextStyle(fontSize: 96 * _size.scale, color: clockColor),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Size',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ClockSize>(
            segments: const [
              ButtonSegment(value: ClockSize.small, label: Text('Small')),
              ButtonSegment(value: ClockSize.medium, label: Text('Medium')),
              ButtonSegment(value: ClockSize.large, label: Text('Large')),
            ],
            selected: {_size},
            onSelectionChanged: (s) => setState(() => _size = s.single),
          ),
          const SizedBox(height: 20),
          const Text(
            'Colour',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: [
              _ColourDot(
                label: 'Theme accent',
                color: accent,
                selected: _color.isAccent,
                onTap: () => setState(() => _color = const ClockColor.accent()),
              ),
              for (final (name, hex) in _colours)
                _ColourDot(
                  label: name,
                  color: Color(hex.argb),
                  selected: _color.hex == hex,
                  onTap: () => setState(() => _color = ClockColor.fixed(hex)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Use it on',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lock screen clock'),
            subtitle: const Text('With the live wallpaper on'),
            value: _lock,
            onChanged: (v) => setState(() => _lock = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('wallp Home clock'),
            subtitle: const Text('The clock above your icons'),
            value: _home,
            onChanged: (v) => setState(() => _home = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('App labels'),
            subtitle: const Text('Names under icons on wallp Home'),
            value: _labels,
            onChanged: (v) => setState(() => _labels = v),
          ),
          if (font.fallbackFor.containsKey('my'))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Burmese app names use Padauk: this font has no Myanmar letters.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                        color: _color,
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

class _ColourDot extends StatelessWidget {
  const _ColourDot({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
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
            color: selected ? AppColors.textPrimary : Colors.transparent,
            width: 3,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    ),
  );
}
