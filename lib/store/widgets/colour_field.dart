import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../catalog/catalog.dart';
import '../../core/store_palette.dart';

/// Colours offered for a custom accent (no colour wheel package: a picked
/// palette plus a "#RRGGBB" field covers it).
const colourSwatches = [
  '#FF7A1A',
  '#FF4D2E',
  '#D7263D',
  '#E0245E',
  '#FF5FA2',
  '#FF8FC0',
  '#A970FF',
  '#7CC6FF',
  '#2EC4B6',
  '#7BD44A',
  '#FFC21A',
  '#F2B33D',
  '#FFE08A',
  '#F3E6C4',
  '#F5F1EA',
  '#9FB3C6',
];

/// A colour as "#RRGGBB" text, plus swatches to tap.
class ColourField extends StatefulWidget {
  const ColourField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.swatches = colourSwatches,
  });

  final String label;
  final HexColor value;
  final ValueChanged<HexColor> onChanged;

  /// "#RRGGBB" colours to tap, upper case.
  final List<String> swatches;

  @override
  State<ColourField> createState() => _ColourFieldState();
}

class _ColourFieldState extends State<ColourField> {
  late final _text = TextEditingController(text: widget.value.hex);

  @override
  void didUpdateWidget(ColourField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value &&
        _text.text.toUpperCase() != widget.value.hex.toUpperCase()) {
      _text.text = widget.value.hex;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.palette.text,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _text,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: '${widget.label} hex',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Color(widget.value.argb),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
                  LengthLimitingTextInputFormatter(7),
                ],
                onChanged: (v) {
                  final hex = v.startsWith('#') ? v : '#$v';
                  if (HexColor.isValid(hex)) {
                    widget.onChanged(HexColor(hex.toUpperCase()));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hex in widget.swatches)
              Semantics(
                label: hex,
                button: true,
                checked: widget.value.hex.toUpperCase() == hex,
                excludeSemantics: true,
                child: InkResponse(
                  onTap: () => widget.onChanged(HexColor(hex)),
                  radius: 22,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(HexColor(hex).argb),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.value.hex.toUpperCase() == hex
                            ? context.palette.text
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
