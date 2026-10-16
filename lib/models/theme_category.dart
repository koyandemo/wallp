/// A tab on the main screen ("Halloween", "Christmas", ...).
class ThemeCategory {
  const ThemeCategory({
    required this.id,
    required this.name,
    this.comingSoon = false,
  });

  final String id;
  final String name;

  /// No themes designed yet; the tab shows a "coming soon" message.
  final bool comingSoon;
}
