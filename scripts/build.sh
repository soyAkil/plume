#!/bin/zsh
# Build Plume and assemble build/Plume.app, signed with the local identity.
#   ./scripts/build.sh            build and assemble
#   ./scripts/build.sh --install  ... then install into /Applications and relaunch the app
# To release a version for other Macs: ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Plume.app"
./scripts/assemble.sh "$APP"

./scripts/signing-identity.sh
KEYCHAIN="$HOME/Library/Keychains/plume-signing.keychain-db"
codesign --force --deep --sign "Plume Local Signing" --keychain "$KEYCHAIN" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "Plume Local Signing" --keychain "$KEYCHAIN" "$APP/Contents/Frameworks/llama.framework"
codesign --force --sign "Plume Local Signing" --keychain "$KEYCHAIN" "$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Plume 2>/dev/null && sleep 0.6 || true
  rm -rf /Applications/Plume.app
  cp -R "$APP" /Applications/Plume.app
  mkdir -p "$HOME/.local/bin"
  ln -sf /Applications/Plume.app/Contents/MacOS/Plume "$HOME/.local/bin/plume"
  open /Applications/Plume.app
  echo "Installed: /Applications/Plume.app (command: plume)"
else
  echo "Assembled: $APP"
fi
