import 'package:flutter/widgets.dart';

import '../catalog/catalog.dart';

/// The corners of an icon tile of [size] in [shape]. One definition for
/// every icon: wallp Home, previews and the shape picker.
BorderRadius iconShapeRadius(IconShape shape, double size) => switch (shape) {
  IconShape.circle => BorderRadius.circular(size / 2),
  IconShape.square => BorderRadius.circular(size * 0.12),
  IconShape.squircle => BorderRadius.circular(size * 0.3),
  // CSS "50% 50% 50% 12%": round everywhere but the bottom-left corner.
  IconShape.leaf => BorderRadius.only(
    topLeft: Radius.circular(size / 2),
    topRight: Radius.circular(size / 2),
    bottomRight: Radius.circular(size / 2),
    bottomLeft: Radius.circular(size * 0.12),
  ),
};

/// Clips [child] to an icon tile of [size] in [shape].
class IconShapeClip extends StatelessWidget {
  const IconShapeClip({
    super.key,
    required this.shape,
    required this.size,
    required this.child,
  });

  final IconShape shape;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: iconShapeRadius(shape, size),
    child: SizedBox.square(dimension: size, child: child),
  );
}
