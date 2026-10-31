#!/bin/zsh
# Gera build/oDois Monitor.app a partir do pacote Swift (release).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="build/oDois Monitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ODoisMonitor "$APP/Contents/MacOS/ODoisMonitor"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>oDois Monitor</string>
  <key>CFBundleDisplayName</key><string>oDois Monitor</string>
  <key>CFBundleIdentifier</key><string>me.o2d.odoismonitor</string>
  <key>CFBundleExecutable</key><string>ODoisMonitor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "OK: $APP"
