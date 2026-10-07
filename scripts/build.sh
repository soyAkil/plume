#!/bin/zsh
# Build Plume and assemble build/Plume.app, signed with the local identity.
#   ./scripts/build.sh            build and assemble
#   ./scripts/build.sh --install  ... then install into /Applications and relaunch the app
# Every build is a dev build, labelled <version>-dev+<commit>; a release built after it is
# offered over it, never installed silently. PLUME_DEV_BUILD overrides its build number.
# To release a version for other Macs: ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Plume.app"
# Dev build: a build number that only releases built after it exceed, a label naming the
# commit, and the release feed with automatic install off, so a newer release is offered,
# never installed silently. Released builds are stamped by release.sh instead.
BUILD="${PLUME_DEV_BUILD:-$(date +%Y%m%d%H%M)}"
BASE="$(awk '/^## /{print $2; exit}' CHANGELOG.md)"
LABEL="${BASE:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}-dev"
if SHA="$(git rev-parse --short=7 HEAD 2>/dev/null)"; then
  [[ -z "$(git status --porcelain)" ]] || SHA+=".dirty"
  LABEL+="+$SHA"
fi

./scripts/assemble.sh "$APP"

PLIST="$APP/Contents/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }
plist "Set :CFBundleShortVersionString $LABEL"
plist "Set :CFBundleVersion $BUILD"
# Same feed and key as releases (release.sh); release.env is only read.
if [[ -f scripts/release.env ]]; then source scripts/release.env; fi
if [[ -n "${PLUME_REPO:-}" && -n "${PLUME_ED_PUBLIC_KEY:-}" ]]; then
  plist "Add :SUFeedURL string https://github.com/$PLUME_REPO/releases/latest/download/appcast.xml"
  plist "Add :SUPublicEDKey string $PLUME_ED_PUBLIC_KEY"
  plist "Add :SUEnableAutomaticChecks bool true"
  plist "Add :SUAllowsAutomaticUpdates bool false"
else
  echo "No update feed: scripts/release.env has no repo or key."
fi

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
  open /Applications/Plume.app
  echo "Installed: /Applications/Plume.app, $LABEL ($BUILD) (command: plume)"
else
  echo "Assembled: $APP, $LABEL ($BUILD)"
fi
