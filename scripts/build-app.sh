#!/usr/bin/env bash
# Baut EventMonitor.app in ./build – ohne Xcode-Projekt, nur mit dem Swift-Compiler.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/EventMonitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EventMonitor" "$APP/Contents/MacOS/EventMonitor"

# Logo (neu erzeugen mit: swift scripts/make-icon.swift)
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Event Monitor</string>
    <key>CFBundleDisplayName</key><string>Event Monitor</string>
    <key>CFBundleIdentifier</key><string>io.github.event-monitor</string>
    <key>CFBundleExecutable</key><string>EventMonitor</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>de</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.lifestyle</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc-Signatur (kein Apple-Entwicklerkonto nötig).
codesign --force --sign - "$APP" >/dev/null
echo "Fertig: $APP"
echo "Starten mit: open $APP"
