# Wireless ADB

A small macOS menu bar app for connecting Android devices to `adb` over Wi-Fi by scanning a QR code — the same flow Android Studio uses, without opening Android Studio.

## Features

- Pair a device by scanning a QR code (Android 11+ Wireless debugging)
- Lists connected devices with model name and USB / Wi-Fi transport
- Auto-connects previously paired devices when Wireless debugging is turned on
- Disconnect or copy a device serial from the menu

## Requirements

- macOS 14 or later
- Android SDK platform-tools (`adb`). The app looks in `$ANDROID_HOME`, `$ANDROID_SDK_ROOT`, `~/Library/Android/sdk/platform-tools`, `/opt/homebrew/bin` and `/usr/local/bin`.
- Mac and phone on the same Wi-Fi network

## Install

Download `WirelessADB.zip` from [Releases](../../releases), unzip and move `WirelessADB.app` to Applications.

The app is not notarized, so macOS will block the first launch. Either right-click the app and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/WirelessADB.app
```

## Build from source

```sh
git clone https://github.com/theGBguy/WirelessADB.git
cd WirelessADB
./build.sh            # builds build/WirelessADB.app
./build.sh --install  # also copies it to ~/Applications
```

You can also open `Package.swift` in Xcode.

## Usage

1. Click the menu bar icon and choose **Pair new device with QR code…**
2. On the phone: **Settings › Developer options › Wireless debugging › Pair device with QR code**, then scan.
3. The app pairs and connects. After that, the device reconnects automatically whenever Wireless debugging is on.

Allow **Local Network** access when macOS asks — it's needed to find the phone.

## How it works

The QR code encodes `WIFI:T:ADB;S:<name>;P:<password>;;`. After scanning, the phone advertises a `_adb-tls-pairing._tcp` Bonjour service with that name; the app resolves it and runs `adb pair`. It then finds the phone's `_adb-tls-connect._tcp` service and runs `adb connect` (unless adb's own mDNS auto-connect already did).

## License

[MIT](LICENSE)
