#!/usr/bin/env bash
# Builds the Spider Night kit (tool/seed/spider_night.dart) end to end:
#
#   1. --external only: imports generated pictures from
#      tool/seed/incoming/spider-night/ (docs/spiderman-script.md)
#   2. draws the pictures that weren't imported: Web Slinger icons, skyline
#      and web layers
#   3. writes the catalogs, hashing the pictures into assets/mock/
#   4. draws previews of the wallpaper and icons into build/spider-night-preview/
#
#   tool/seed/spider_night.sh              drawn art (or earlier imports)
#   tool/seed/spider_night.sh --external   import new generated art first
#   tool/seed/spider_night.sh --drawn      forget imports, back to drawn art
#
# Change the art in spider_night_art.dart / art.dart, or the scene and
# colours in spider_night.dart, then run this again.
set -euo pipefail
cd "$(dirname "$0")/../.."

case "${1:-}" in
  --external) flutter test tool/seed/import_spider_art_test.dart ;;
  --drawn) rm -f tool/seed/source/external-art.txt ;;
  "") ;;
  *) echo "Unknown option: $1 (use --external or --drawn)" >&2; exit 64 ;;
esac

flutter test tool/seed/render_art_test.dart
dart run tool/seed/generate.dart
flutter test tool/seed/spider_night_preview_test.dart

echo "Previews: build/spider-night-preview/"
