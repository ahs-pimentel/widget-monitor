#!/bin/zsh
# Gera build/oDois Monitor.app a partir do pacote Swift (release).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# UNIVERSAL=1 gera binário arm64 + x86_64 (para distribuir a outros Macs).
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ODoisMonitor"
else
  swift build -c release
  BIN=".build/release/ODoisMonitor"
fi
APP="build/oDois Monitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Ícone: gera o .icns a partir do PNG 1024 em assets/.
if [[ -f assets/AppIcon-1024.png ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size assets/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) assets/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi
cp "$BIN" "$APP/Contents/MacOS/ODoisMonitor"

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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Assinatura: Developer ID (SIGN_IDENTITY ou o primeiro do keychain) com hardened
# runtime, exigido pela notarização. Sem certificado, cai para assinatura ad-hoc.
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  SIGNED_WITH="$SIGN_IDENTITY"
else
  codesign --force --sign - "$APP" >/dev/null
  SIGNED_WITH="ad-hoc (sem Developer ID)"
fi
codesign --verify --strict "$APP"
echo "OK: $APP (v$VERSION, build $BUILD, assinatura: $SIGNED_WITH)"
