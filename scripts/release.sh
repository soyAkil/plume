#!/bin/zsh
# Build a releasable version of Plume: signed and notarized app, disk image, update feed.
# Nothing is uploaded: that is the job of scripts/publish.sh.
#   ./scripts/release.sh 1.0.1
# Settings in scripts/release.env. Without a Developer ID certificate, the script runs in
# trial mode (local signature, no notarization) to check the whole chain.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/release.env

VERSION="${1:?version number, for example 1.0.1}"
# No release with a failing test: Sparkle would offer it to every install.
./scripts/test.sh
# Build number: the date, always increasing — it is what Sparkle compares.
BUILD="${PLUME_BUILD:-$(date +%Y%m%d%H%M)}"
REPO="${PLUME_REPO:-owner/plume}"
# The three variables PLUME_BUILD, PLUME_FEED_URL and PLUME_DOWNLOAD_PREFIX are only for
# trying an update end to end on this Mac (see docs/RELEASING.md).
FEED="${PLUME_FEED_URL:-https://github.com/$REPO/releases/latest/download/appcast.xml}"
PREFIX="${PLUME_DOWNLOAD_PREFIX:-https://github.com/$REPO/releases/download/v$VERSION/}"

DIST="${PLUME_DIST:-dist}"
APP="$DIST/Plume.app"
# Build outside the home folder: no path of this Mac in the released binary.
export PLUME_SCRATCH="${PLUME_SCRATCH:-/Users/Shared/plume-build}"
TOOLS="$PLUME_SCRATCH/artifacts/sparkle/Sparkle/bin"
# With no repo to release to, the app does not check for updates: it is a version for
# testers, kept apart so it never enters the feed of released versions.
UPDATES=1
[[ -z "${PLUME_REPO:-}" && -z "${PLUME_FEED_URL:-}" ]] && UPDATES=0
OUT="$DIST/mises-a-jour"
[[ $UPDATES == 0 ]] && OUT="$DIST/trial"
DMG="$OUT/Plume-$VERSION.dmg"
mkdir -p "$OUT"

./scripts/assemble.sh "$APP"

# Public update key: created on the first run, kept in the keychain.
if [[ -z "$PLUME_ED_PUBLIC_KEY" ]]; then
  if ! PLUME_ED_PUBLIC_KEY="$("$TOOLS/generate_keys" -p 2>/dev/null)"; then
    "$TOOLS/generate_keys" >/dev/null
    PLUME_ED_PUBLIC_KEY="$("$TOOLS/generate_keys" -p)"
  fi
  /usr/bin/sed -i '' "s|^PLUME_ED_PUBLIC_KEY=.*|PLUME_ED_PUBLIC_KEY=\"$PLUME_ED_PUBLIC_KEY\"|" scripts/release.env
  echo "Public update key written to scripts/release.env."
fi

PLIST="$APP/Contents/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }
plist "Set :CFBundleShortVersionString $VERSION"
plist "Set :CFBundleVersion $BUILD"
if [[ $UPDATES == 1 ]]; then
  plist "Add :SUFeedURL string $FEED"
  plist "Add :SUPublicEDKey string $PLUME_ED_PUBLIC_KEY"
  plist "Add :SUEnableAutomaticChecks bool true"
fi
# Feed served by this Mac during a trial run: the system only allows http locally.
if [[ "$FEED" == http://127.0.0.1* ]]; then
  plist "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true"
  plist "Add :SUAutomaticallyUpdate bool true"
fi

# --- Signing
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ENTITLEMENTS="Resources/Plume.entitlements"
if [[ -n "$PLUME_IDENTITY" ]]; then
  TRIAL=0
  SIGN=(codesign --force --timestamp --options runtime --sign "$PLUME_IDENTITY")
else
  TRIAL=1
  echo "Trial mode: local signature, no notarization."
  ./scripts/signing-identity.sh
  SIGN=(codesign --force --options runtime --sign "Plume Local Signing"
    --keychain "$HOME/Library/Keychains/plume-signing.keychain-db")
  # A local certificate has no team ID: without this exception, the system would
  # refuse to load Sparkle under the hardened runtime.
  ENTITLEMENTS="$DIST/trial.entitlements"
  cp Resources/Plume.entitlements "$ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS"
fi
# From the inside out: Sparkle's tools, the library, then the app.
"${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" "$APP/Contents/Frameworks/llama.framework"
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$PLUME_NOTARY_PROFILE" --wait
}

# --- Notarize the app, so it opens even offline
if [[ $TRIAL == 0 ]]; then
  ditto -c -k --keepParent "$APP" "$DIST/Plume.zip"
  notarize "$DIST/Plume.zip"
  xcrun stapler staple "$APP"
  rm "$DIST/Plume.zip"
fi

# --- Disk image: the app and a shortcut to Applications
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Plume.app"
ln -s /Applications "$STAGE/Applications"
# An unnotarized version is blocked on first launch: we say how to get past that.
if [[ $TRIAL == 1 ]]; then
  cp Resources/README-testers.txt "$STAGE/Read-me.txt"
  if [[ $UPDATES == 1 ]]; then
    print "\nNew versions arrive on their own: Plume offers them to you as soon as they are out." >>"$STAGE/Read-me.txt"
  else
    print "\nThis version does not update itself: a new one will be sent to you." >>"$STAGE/Read-me.txt"
  fi
fi
rm -f "$DMG"
hdiutil create -volname "Plume" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
if [[ $TRIAL == 0 ]]; then
  codesign --force --timestamp --sign "$PLUME_IDENTITY" "$DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
fi

# --- Update feed: signed with the keychain key. The release notes, if they exist
# (notes/1.0.1.md), are attached.
if [[ $UPDATES == 1 ]]; then
  [[ -f "notes/$VERSION.md" ]] && cp "notes/$VERSION.md" "$OUT/Plume-$VERSION.md"
  "$TOOLS/generate_appcast" "$OUT" --download-url-prefix "$PREFIX" --embed-release-notes \
    --link "https://github.com/$REPO" -o "$OUT/appcast.xml"
fi

echo
echo "Version $VERSION ($BUILD) ready in $OUT:"
ls -lh "$OUT" | tail -n +2
[[ $TRIAL == 1 ]] && echo "Not notarized: macOS blocks it on first launch (see Read-me.txt in the disk image)."
exit 0
