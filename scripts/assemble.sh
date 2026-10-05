#!/bin/zsh
# Compile Plume et assemble l'app, sans la signer.
#   ./scripts/assemble.sh build/Plume.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?chemin de l'app à assembler}"
source scripts/sdk.sh

# Dossier de compilation. SwiftPM inscrit son chemin dans le binaire : une version publiée se
# compile donc hors du dossier personnel (PLUME_SCRATCH, réglé par release.sh).
SCRATCH="${PLUME_SCRATCH:-.build}"
swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Plume" "$APP/Contents/MacOS/Plume"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/LICENCES.md "$APP/Contents/Resources/LICENCES.md"
cp CHANGELOG.md "$APP/Contents/Resources/CHANGELOG.md"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
# Sparkle (mises à jour) : la bibliothèque et ses outils d'installation.
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
