#!/bin/zsh
# Build Plume and assemble the app, unsigned.
#   ./scripts/assemble.sh build/Plume.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?path of the app to assemble}"
source scripts/sdk.sh

# Build folder. SwiftPM writes its path into the binary, so a released version is built
# outside the home folder (PLUME_SCRATCH, set by release.sh).
SCRATCH="${PLUME_SCRATCH:-.build}"
swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Plume" "$APP/Contents/MacOS/Plume"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/fr.lproj "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/LICENSES.md "$APP/Contents/Resources/LICENSES.md"
cp CHANGELOG.md "$APP/Contents/Resources/CHANGELOG.md"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
# Sparkle (updates): the library and its installer tools.
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# llama.cpp (local summaries). The release ships x86_64 too: keep Apple Silicon only, half the size.
LLAMA="$APP/Contents/Frameworks/llama.framework"
ditto "$BIN/llama.framework" "$LLAMA"
LLAMA_BIN="$LLAMA/Versions/A/llama"
lipo -thin arm64 "$LLAMA_BIN" -output "$LLAMA_BIN.arm64"
mv "$LLAMA_BIN.arm64" "$LLAMA_BIN"
