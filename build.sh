#!/bin/sh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/WirelessADB.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/WirelessADB "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP"
if [ "$1" = "--install" ]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/WirelessADB.app
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/WirelessADB.app"
fi
