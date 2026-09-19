#!/usr/bin/env bash
# Builds standalone Linux, Windows and macOS binaries from export_presets.cfg
# and zips each one for distribution into dist/. Run from the project root:
#   tools/export_all.sh
#
# One-time setup this machine needed (not part of this script, since it's a
# ~2GB download you only do once): install the export templates matching
# your Godot version from
#   https://github.com/godotengine/godot/releases/tag/<version>-stable
#   (asset named Godot_v<version>-stable_export_templates.tpz)
# into ~/.local/share/godot/export_templates/<version>.stable/ - or, if
# you're running the Flatpak build of Godot (`flatpak info org.godotengine.Godot`
# succeeds), into the sandboxed path instead:
#   ~/.var/app/org.godotengine.Godot/data/godot/export_templates/<version>.stable/
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf build dist
mkdir -p build/linux build/windows build/macos dist

godot --headless --export-release "Linux" build/linux/SlideWalker.x86_64
godot --headless --export-release "Windows" build/windows/SlideWalker.exe
godot --headless --export-release "macOS" build/macos/SlideWalker.zip

( cd build/linux && zip -qr ../../dist/SlideWalker-linux-x86_64.zip . )
( cd build/windows && zip -qr ../../dist/SlideWalker-windows-x86_64.zip . )
cp build/macos/SlideWalker.zip dist/SlideWalker-macos.zip

echo "--- dist/ ---"
ls -la dist/
