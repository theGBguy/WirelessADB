#!/bin/sh
# Usage: ./build.sh [--install]
#
# Optional environment:
#   SIGN_IDENTITY     e.g. "Developer ID Application: Your Name (TEAMID)". Default: ad-hoc.
#   Notarization (requires SIGN_IDENTITY), either:
#     NOTARY_PROFILE  a profile saved with `xcrun notarytool store-credentials`
#   or an App Store Connect API key:
#     NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
set -e
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

APP=build/WirelessADB.app
ZIP=build/WirelessADB.zip
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/WirelessADB" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

IDENTITY="${SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ "$IDENTITY" != "-" ] && { [ -n "$NOTARY_PROFILE" ] || [ -n "$NOTARY_KEY_PATH" ]; }; then
  if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$ZIP" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
  fi
  xcrun stapler staple "$APP"          # fails if notarization was rejected
  rm "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
fi

echo "Built $APP ($ZIP)"
if [ "$1" = "--install" ]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/WirelessADB.app
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/WirelessADB.app"
fi
