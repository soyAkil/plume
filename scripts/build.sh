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
codesign --force --sign "Plume Local Signing" --keychain "$KEYCHAIN" "$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Plume 2>/dev/null && sleep 0.6 || true
  rm -rf /Applications/Plume.app
  cp -R "$APP" /Applications/Plume.app
  mkdir -p "$HOME/.local/bin"
  ln -sf /Applications/Plume.app/Contents/MacOS/Plume "$HOME/.local/bin/plume"
  # Each build is a new signature for macOS: the Accessibility switch stays on but the new
  # binary is not trusted, and its key events are silently dropped. Reset, so Plume asks again.
  tccutil reset Accessibility studio.brigode.plume >/dev/null 2>&1 || true
  tccutil reset ListenEvent studio.brigode.plume >/dev/null 2>&1 || true
  open /Applications/Plume.app
  echo "Installed: /Applications/Plume.app (command: plume)"
  echo "Re-grant Accessibility when Plume asks (the permission does not follow a new build)."
else
  echo "Assembled: $APP"
fi
