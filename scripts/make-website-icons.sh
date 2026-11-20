#!/bin/zsh
# Rebuilds the website's raster icons from docs/icon.svg. Run it after changing icon.svg.
#
#   docs/favicon.ico          16 and 32 px, for Safari tabs, bookmarks and link previews
#   docs/apple-touch-icon.png 180 px, full-bleed, for Apple devices (they round the corners)
#
# Needs Google Chrome, which draws the SVG exactly as browsers do, and ImageMagick
# (brew install imagemagick).
set -euo pipefail

ROOT="${0:A:h:h}"
DOCS="$ROOT/docs"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[[ -x "$CHROME" ]] || { echo "Google Chrome not found. Set CHROME to its binary." >&2; exit 1; }
command -v magick >/dev/null || { echo "ImageMagick not found. Run: brew install imagemagick" >&2; exit 1; }

cp "$DOCS/icon.svg" "$WORK/icon.svg"

# The web icon has transparent rounded corners. Apple devices add their own corners,
# so the touch icon's background fills the whole square instead.
ROUNDED='<rect x="2" y="2" width="96" height="96" rx="22" fill="url(#bg)"/>'
SQUARE='<rect width="100" height="100" fill="url(#bg)"/>'
grep -qF "$ROUNDED" "$WORK/icon.svg" || { echo "icon.svg's background shape changed. Update ROUNDED in this script." >&2; exit 1; }
sed "s|$ROUNDED|$SQUARE|" "$WORK/icon.svg" > "$WORK/icon-square.svg"

render() { # svg size output
  printf '<!doctype html><style>html,body{margin:0;background:transparent}img{display:block;width:%spx;height:%spx}</style><img src="%s">' \
    "$2" "$2" "$1" > "$WORK/page.html"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size="$2,$2" \
    --screenshot="$WORK/$3" "file://$WORK/page.html" >/dev/null 2>&1
  [[ -s "$WORK/$3" ]] || { echo "Chrome could not draw $3" >&2; exit 1; }
}

render icon.svg 32 icon-32.png
render icon.svg 512 icon-512.png
render icon-square.svg 180 touch.png

# Drawn directly at 16 px the coral ring smears, so shrink the large drawing and
# sharpen only the colour (sharpening transparency hardens the edges).
magick "$WORK/icon-512.png" -filter Mitchell -resize 16x16 -channel RGB -unsharp 0x0.5+0.6+0 +channel "$WORK/icon-16.png"

# TrueColorAlpha stops ImageMagick saving the 16 px image as a 256-colour palette with
# on/off transparency, which loses the soft rounded corners.
magick "$WORK/icon-16.png" "$WORK/icon-32.png" -type TrueColorAlpha "$DOCS/favicon.ico"
magick "$WORK/touch.png" -strip "$DOCS/apple-touch-icon.png"

echo "Updated docs/favicon.ico and docs/apple-touch-icon.png"
