import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../catalog/catalog.dart';
import '../../core/store_palette.dart';
import '../../core/date_format.dart';
import '../../look/accent_choices.dart';
import '../../look/accent_contrast.dart';
import '../../look/accent_paint.dart';
import '../../look/my_accents.dart';
import '../../scenes/scene_view.dart';
import '../logic/previews.dart';
import '../widgets/colour_field.dart';
import '../widgets/common.dart';

/// Pick a theme's accent: solid colours, gradients, or one the user makes.
/// Pops with the picked [Accent]; the detail page applies it.
class AccentPickerScreen extends StatefulWidget {
  const AccentPickerScreen({
    super.key,
    required this.theme,
    this.variantId,
    this.current,
  });

  final ThemeDetail theme;
  final String? variantId;
  final Accent? current;

  @override
  State<AccentPickerScreen> createState() => _AccentPickerScreenState();
}

enum _Tab { solid, gradient, custom }

class _AccentPickerScreenState extends State<AccentPickerScreen> {
  late _Tab _tab = widget.current?.type == AccentType.gradient
      ? _Tab.gradient
      : _Tab.solid;
  late Accent? _picked = widget.current;

  // Custom builder.
  bool _gradient = true;
  HexColor _start = const HexColor('#FF7A1A');
  HexColor _end = const HexColor('#E0245E');
  int _angle = 135;

  Accent get _custom => customAccent(
    id: 'custom',
    name: 'Custom',
    start: _start,
    end: _gradient ? _end : null,
    angle: _angle,
  );

  Accent get _current =>
      _tab == _Tab.custom ? _custom : (_picked ?? widget.theme.defaultAccent);

  @override
  Widget build(BuildContext context) {
    final catalog = catalogOf(context);
    final mine = context.watch<MyAccents>().accents;
    final choices = AccentChoices.forTheme(
      widget.theme,
      catalog.accentPresets,
      mine,
      variantId: widget.variantId,
    );
    final accent = _current;
    final readable = choices.isReadable(accent);
    final summary = catalog.theme(widget.theme.id)!;
    final preview = previewOf(
      summary,
      catalog,
      nowOf(context),
      detail: widget.theme,
      variantId: widget.variantId,
      accent: accent,
    );

    return Scaffold(
      appBar: AppBar(title: Text('${widget.theme.name.en} accent')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
        children: [
          // The clock on the wallpaper's sky, in the accent.
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 170,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SceneView(theme: preview, accent: accent.color),
                  Center(
                    child: GradientText(
                      gradient: accent.gradient,
                      child: Text(
                        DateFormatX.clock(
                          nowOf(context),
                          use24h: MediaQuery.alwaysUse24HourFormatOf(context),
                        ),
                        style: preview.displayStyle(
                          TextStyle(fontSize: 72, color: accent.color),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: context.palette.background,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        readable ? 'Easy to read' : 'Hard to read here',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: readable
                              ? const Color(0xFF7BD44A)
                              : context.palette.brand,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<_Tab>(
            // No tick on the selected option: its fill shows it.
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Tab.solid, label: SegmentLabel('Solid')),
              ButtonSegment(
                value: _Tab.gradient,
                label: SegmentLabel('Gradient'),
              ),
              ButtonSegment(value: _Tab.custom, label: SegmentLabel('Custom')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.single),
          ),
          const SizedBox(height: 16),
          switch (_tab) {
            _Tab.solid => _Grid(
              accents: [
                ...choices.theme.where((a) => a.type == AccentType.solid),
                ...choices.solids,
              ],
              picked: _picked,
              onPick: (a) => setState(() => _picked = a),
            ),
            _Tab.gradient => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Grid(
                  accents: [
                    ...choices.theme.where(
                      (a) => a.type == AccentType.gradient,
                    ),
                    ...choices.gradients,
                  ],
                  picked: _picked,
                  onPick: (a) => setState(() => _picked = a),
                ),
                if (choices.mine.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'My accents',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.palette.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Grid(
                    accents: choices.mine,
                    picked: _picked,
                    onPick: (a) => setState(() => _picked = a),
                  ),
                ],
              ],
            ),
            _Tab.custom => _customBuilder(context),
          },
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent.color,
                foregroundColor: Color(labelOn(accent).argb),
              ),
              onPressed: () => Navigator.pop(context, accent),
              child: Text(
                'Use ${accent.name.en == 'Custom' ? 'this accent' : accent.name.en}',
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

  Widget _customBuilder(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          // No tick on the selected option: its fill shows it.
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: SegmentLabel('One colour')),
            ButtonSegment(value: true, label: SegmentLabel('Gradient')),
          ],
          selected: {_gradient},
          onSelectionChanged: (s) => setState(() => _gradient = s.single),
        ),
        const SizedBox(height: 16),
        ColourField(
          label: _gradient ? 'Start colour' : 'Colour',
          value: _start,
          onChanged: (c) => setState(() => _start = c),
        ),
        if (_gradient) ...[
          const SizedBox(height: 12),
          ColourField(
            label: 'End colour',
            value: _end,
            onChanged: (c) => setState(() => _end = c),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                final start = _start;
                _start = _end;
                _end = start;
              }),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Swap colours'),
            ),
          ),
          Text(
            'Direction',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.palette.text,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (deg, label) in const [
                (90, 'Left to right'),
                (135, 'Diagonal, top left to bottom right'),
                (180, 'Top to bottom'),
                (45, 'Diagonal, bottom left to top right'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    tooltip: label,
                    isSelected: _angle == deg,
                    style: IconButton.styleFrom(
                      backgroundColor: _angle == deg
                          ? context.palette.text
                          : context.palette.surface,
                      foregroundColor: _angle == deg
                          ? context.palette.background
                          : context.palette.text,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => setState(() => _angle = deg),
                    // The arrow points right at 90°.
                    icon: Transform.rotate(
                      angle: (deg - 90) * 3.14159265 / 180,
                      child: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final saved = await context.read<MyAccents>().add(
              start: _start,
              end: _gradient ? _end : null,
              angle: _angle,
            );
            if (!context.mounted) return;
            setState(() {
              _picked = saved;
              _tab = _Tab.gradient;
            });
            showToast(context, 'Saved to My accents');
          },
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('Save to My accents'),
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.accents,
    required this.picked,
    required this.onPick,
  });

  final List<Accent> accents;
  final Accent? picked;
  final ValueChanged<Accent> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final a in accents)
          Semantics(
            label: a.name.en,
            inMutuallyExclusiveGroup: true,
            checked: picked != null && sameLook(a, picked!),
            button: true,
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onPick(a),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: picked != null && sameLook(a, picked!)
                        ? context.palette.text
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: DecoratedBox(
                  decoration: a.decoration(radius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
