#!/usr/bin/env bash
# Re-renders the watch app icon (every size in AppIcon.appiconset), avatar.png
# and banner.png from their SVG sources. Requires resvg
# (https://github.com/linebender/resvg). Uses the bundled Roboto fonts, so the
# result does not depend on system fonts. icon.svg is the same artwork as the
# BalanceFlutter app icon (palette «Лес»).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
fonts=(
  --skip-system-fonts
  --use-font-file fonts/Roboto-Regular.ttf
  --use-font-file fonts/Roboto-Medium.ttf
  --use-font-file fonts/Roboto-Bold.ttf
)
icons=../BalanceWatch/Assets.xcassets/AppIcon.appiconset
for file in "$icons"/BalanceIcon-*.png; do
  size="${file##*-}"; size="${size%.png}"
  resvg -w "$size" -h "$size" icon.svg "$file"
done
resvg "${fonts[@]}" -w 512 -h 512 avatar.svg avatar.png
resvg "${fonts[@]}" banner.svg banner.png
