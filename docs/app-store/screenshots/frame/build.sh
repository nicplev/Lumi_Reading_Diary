#!/usr/bin/env bash
# Renders the framed App Store panels from raw simulator captures.
#
# Usage: ./build.sh
# Output: ../framed/iphone69/*.png (1320x2868) and ../framed/ipad13/*.png (2752x2064)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Chrome not found at $CHROME" >&2; exit 1; }

urlencode() { python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$1"; }

render() { # device raw out title tint size
  local device="$1" raw="$2" out="$3" title="$4" tint="$5" size="$6"
  local url="file://$PWD/panel.html?device=$device&img=$(urlencode "../raw/$raw")&title=$(urlencode "$title")&tint=$(urlencode "$tint")"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size="$size" --screenshot="$PWD/../framed/$out" "$url" >/dev/null 2>&1
  echo "✓ framed/$out — $title"
}

# Lumi tints (from lib/theme/lumi_tokens.dart)
RED='#F4B5B7'; YELLOW='#FBE89F'; GREEN='#B5DAB8'; BLUE='#C8E8F1'

# ── iPhone 6.9" (1320x2868) — parent story ──────────────────────────
render iphone iphone69/01.png iphone69/01.png "Tonight's reading, ready to go" "$RED"    1320,2868
render iphone iphone69/02.png iphone69/02.png "Every child, one place"         "$BLUE"   1320,2868
render iphone iphone69/03.png iphone69/03.png "Every night is a win"           "$GREEN"  1320,2868
render iphone iphone69/04.png iphone69/04.png "Badges worth earning"           "$YELLOW" 1320,2868
render iphone iphone69/05.png iphone69/05.png "Every book, remembered"         "$RED"    1320,2868
render iphone iphone69/06.png iphone69/06.png "Your teacher, in the loop"      "$BLUE"   1320,2868
render iphone iphone69/08.png iphone69/07.png "Meet Lumi"                      "$YELLOW" 1320,2868

# ── iPad 13" (2752x2064 landscape) — teacher story ──────────────────
render ipad ipad13/01.png ipad13/01.png "Your class at a glance"      "$BLUE"   2752,2064
render ipad ipad13/02.png ipad13/02.png "Momentum you can see"        "$YELLOW" 2752,2064
render ipad ipad13/03.png ipad13/03.png "Made for the classroom iPad" "$GREEN"  2752,2064
render ipad ipad13/04.png ipad13/04.png "Reading groups, organised"   "$RED"    2752,2064
render ipad ipad13/05.png ipad13/05.png "Your class library"          "$YELLOW" 2752,2064
render ipad ipad13/06.png ipad13/06.png "Celebrate your top readers"  "$GREEN"  2752,2064

echo "Done. Verify dimensions:"
for f in ../framed/iphone69/*.png ../framed/ipad13/*.png; do
  printf "%s: %s\n" "$f" "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%sx", $2}' | sed 's/x$//')"
done
