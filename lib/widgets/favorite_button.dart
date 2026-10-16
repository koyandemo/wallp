import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/phone_theme.dart';
import '../services/my_themes.dart';

/// ♡ toggle for a theme. [onImage] adds a dark backdrop so it reads on top
/// of a wallpaper preview.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.theme, this.onImage = false});

  final PhoneTheme theme;
  final bool onImage;

  static const _on = Color(0xFFFF6B81);

  @override
  Widget build(BuildContext context) {
    final favorite = context.select<MyThemes, bool>((m) => m.isFavorite(theme));
    return IconButton(
      tooltip: favorite
          ? 'Remove ${theme.name} from favourites'
          : 'Add ${theme.name} to favourites',
      onPressed: () => context.read<MyThemes>().toggleFavorite(theme),
      style: onImage
          ? IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.45),
            )
          : null,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: Icon(
          favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(favorite),
          color: favorite ? _on : Colors.white,
        ),
      ),
    );
  }
}
