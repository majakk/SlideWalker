#!/usr/bin/env bash
# Regenerates assets/icons/stickman_icon.png from the actual in-game stick
# figure (player/stick_figure.gd), for use as a menu/app icon.
#
# Renders the figure on solid white on the root viewport (via
# make_stick_icon.tscn - SubViewport capture blurred these vector strokes
# badly at this scale, and --headless has no real renderer), then in post:
# trims to the render's bounding box, resizes to exactly 512x512, and
# converts white-on-black luminance to an alpha channel against a solid ink
# color. That avoids the green-fringe problem a chroma-key background gives
# flat black line art. Needs ImageMagick (`magick`).
#
# Run from the project root: tools/make_stick_icon.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="assets/icons"
RAW="$OUT_DIR/_stickman_icon_raw.png"
TRIM="$OUT_DIR/_trim.png"
OUT="$OUT_DIR/stickman_icon.png"

mkdir -p "$OUT_DIR"
godot --path . res://tools/make_stick_icon.tscn

magick "$RAW" -fuzz 2% -trim +repage "$TRIM"
magick "$TRIM" -resize 512x512! "$TRIM"
magick -size 512x512 xc:"#141414" \( "$TRIM" -colorspace Gray -negate \) \
	-alpha off -compose CopyOpacity -composite "$OUT"

rm -f "$RAW" "$TRIM"
echo "wrote $OUT"
