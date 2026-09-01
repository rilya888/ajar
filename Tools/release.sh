#!/bin/bash
#
# Ajar release: sources -> signed, notarized, stapled DMG + appcast, one command.
#
#   Tools/release.sh
#
# Everything lands in build/release/ (gitignored). Nothing here is interactive except
# two keychain prompts on the very first run of a fresh machine — see docs/release/submission.md.
#
# Credentials this needs, none of them in the repo:
#   - "Developer ID Application: ... (D89KDAZ648)" in the login keychain
#   - a notarytool profile named "ajar" (xcrun notarytool store-credentials ajar ...)
#   - Sparkle's EdDSA private key in the login keychain (Sparkle's generate_keys)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/release"
STAGE="$OUT/dmg-stage"
DIST="$OUT/dist"                       # what actually gets uploaded
ARCHIVE="$OUT/Ajar.xcarchive"

SCHEME="Ajar"
TEAM="D89KDAZ648"
NOTARY_PROFILE="ajar"
SIGN_ID="Developer ID Application"
FEED_PREFIX="https://quietunit.com/ajar/"

VOLNAME="Ajar"
DMG_W=600; DMG_H=400                   # must match Tools/make_dmg_background.py
ICON_LEFT_X=150; ICON_RIGHT_X=450; ICON_Y=190

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- build settings
VERSION="$(xcodebuild -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')"
BUILD_DIR="$(xcodebuild -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILD_DIR = /{print $2; exit}')"
# Sparkle's command line tools ship inside the resolved SPM artifact, next to the build dir.
SPARKLE_BIN="$BUILD_DIR/../../SourcePackages/artifacts/sparkle/Sparkle/bin"
[ -x "$SPARKLE_BIN/generate_appcast" ] || {
    echo "generate_appcast not found under $SPARKLE_BIN — run xcodebuild -resolvePackageDependencies first" >&2
    exit 1
}

APP="$DIST/Ajar.app"
DMG="$DIST/Ajar-$VERSION.dmg"
echo "Ajar $VERSION"

rm -rf "$OUT"
mkdir -p "$DIST"

# ---------------------------------------------------------------- archive + export
step "Archive (Release, Developer ID)"
xcodebuild archive \
    -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    | tail -3

cat > "$OUT/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>method</key><string>developer-id</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>manual</string>
	<key>signingCertificate</key><string>$SIGN_ID</string>
	<key>destination</key><string>export</string>
</dict></plist>
PLIST

step "Export"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/export.plist" \
    -exportPath "$DIST" \
    | tail -3

# ---------------------------------------------------------------- verify before paying for a notarization round trip
step "Verify signature and entitlements"
codesign --verify --deep --strict --verbose=2 "$APP"
# Captured first, not piped into grep -q: under `set -o pipefail` the early exit of
# grep SIGPIPEs codesign and the check fails on a perfectly good signature.
SIGINFO="$(codesign -d -vv "$APP" 2>&1)"
case "$SIGINFO" in *"flags="*"runtime"*) ;; *) echo "Hardened Runtime missing" >&2; exit 1;; esac
ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
case "$ENTS" in *app-sandbox*) echo "App Sandbox is on — it must not be, the lid sensor lives outside it" >&2; exit 1;; esac

# ---------------------------------------------------------------- notarize the app
step "Notarize app"
ditto -c -k --keepParent "$APP" "$OUT/Ajar.zip"
xcrun notarytool submit "$OUT/Ajar.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

# ---------------------------------------------------------------- DMG
step "Build DMG"
rm -rf "$STAGE"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/docs/release/dmg-background.png" "$STAGE/.background/background.png"

hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
    -format UDRW -ov "$OUT/rw.dmg" >/dev/null

# `... | grep -o ... | head -1` SIGPIPEs grep the moment head closes the pipe, and
# under `set -o pipefail` that non-zero exit kills the script on a good mount. Capture
# first, then match with grep -m1 (it stops itself, nothing downstream to close on it).
ATTACH_OUT="$(hdiutil attach "$OUT/rw.dmg" -readwrite -noverify -noautoopen)"
MOUNT="$(printf '%s\n' "$ATTACH_OUT" | grep -o -m1 '/Volumes/.*')"
# Finder is the only thing that writes the window layout a DMG shows on open, and
# driving it needs Automation -> Finder for whatever runs this script. When that is
# denied osascript exits non-zero (macOS 26: error -1743), so `set -e` is lifted around
# it — otherwise the whole release dies on a denial the DMG itself survives. The error
# text is still captured and reported below; the DMG is valid without the layout.
set +e
LAYOUT_ERR="$(osascript 2>&1 >/dev/null <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 150, ${DMG_W} + 200, ${DMG_H} + 150}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "Ajar.app" of container window to {$ICON_LEFT_X, $ICON_Y}
        set position of item "Applications" of container window to {$ICON_RIGHT_X, $ICON_Y}
        update without registering applications
        close
    end tell
end tell
APPLESCRIPT
)"
set -e
if [ -n "$LAYOUT_ERR" ]; then
    echo "  !! DMG opens as a plain file list, without the background hint."
    echo "  !! $LAYOUT_ERR"
    echo "  !! Grant Automation -> Finder to whatever runs this script"
    echo "  !! (System Settings > Privacy & Security > Automation) and run it again."
fi
sync
hdiutil detach "$MOUNT" >/dev/null

hdiutil convert "$OUT/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$OUT/rw.dmg"

# ---------------------------------------------------------------- notarize the DMG separately
step "Sign and notarize DMG"
codesign --sign "$SIGN_ID" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# ---------------------------------------------------------------- appcast
step "Appcast"
# generate_appcast mounts the DMG, reads the version out of the app, signs the file with
# the EdDSA key from the keychain and writes the enclosure. It is the only thing that
# touches the private key, and it never prints it.
rm -rf "$DIST/Ajar.app"                # the appcast is built from the DMG, not the loose app
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "$FEED_PREFIX" -o "$OUT/appcast.xml" "$DIST"
cp "$OUT/appcast.xml" "$DIST/appcast.xml"

step "Done"
spctl -a -vvv -t install "$DMG" || true
echo
echo "Upload the contents of $DIST to ${FEED_PREFIX}:"
ls -1 "$DIST"
