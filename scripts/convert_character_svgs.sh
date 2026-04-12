#!/usr/bin/env bash
# convert_character_svgs.sh
#
# Converts the 8 Lumi character SVGs from assets/characters/ into PNG image sets
# for the LumiWidget Xcode target.
#
# Requirements: rsvg-convert (brew install librsvg) OR cairosvg (pip install cairosvg)
#
# Usage:
#   cd /path/to/lumi_reading_tracker
#   chmod +x scripts/convert_character_svgs.sh
#   ./scripts/convert_character_svgs.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG_DIR="$REPO_ROOT/assets/characters"
XCASSETS="$REPO_ROOT/ios/LumiWidget/Assets.xcassets"

CHARACTERS=(
  "character_bear"
  "character_cat"
  "character_dog"
  "character_fox"
  "character_owl"
  "character_penguin"
  "character_rabbit"
  "character_turtle"
)

# Detect converter
if command -v rsvg-convert &>/dev/null; then
  CONVERTER="rsvg"
elif command -v cairosvg &>/dev/null; then
  CONVERTER="cairosvg"
else
  echo "Error: Install rsvg-convert (brew install librsvg) or cairosvg (pip install cairosvg)."
  exit 1
fi

convert_svg() {
  local svg="$1"
  local png="$2"
  local size="$3"
  if [ "$CONVERTER" = "rsvg" ]; then
    rsvg-convert -w "$size" -h "$size" -o "$png" "$svg"
  else
    cairosvg "$svg" -o "$png" -W "$size" -H "$size"
  fi
}

for char in "${CHARACTERS[@]}"; do
  SVG="$SVG_DIR/${char}.svg"
  if [ ! -f "$SVG" ]; then
    echo "Skipping $char — SVG not found at $SVG"
    continue
  fi

  IMAGESET="$XCASSETS/${char}.imageset"
  mkdir -p "$IMAGESET"

  echo "Converting $char..."
  convert_svg "$SVG" "$IMAGESET/${char}.png"      80
  convert_svg "$SVG" "$IMAGESET/${char}@2x.png"  160
  convert_svg "$SVG" "$IMAGESET/${char}@3x.png"  240

  cat > "$IMAGESET/Contents.json" <<CONTENTS
{
  "images" : [
    {
      "filename" : "${char}.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "${char}@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "${char}@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
CONTENTS

  echo "  → $IMAGESET"
done

echo ""
echo "Done. Add new image sets to the LumiWidget target in Xcode if prompted."
