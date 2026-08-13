#!/bin/bash
# WipeDisk.app paketini olusturur.
#
# SwiftUI arayuzunun dogru calismasi (pencere, menu cubugu, kimlik dogrulama
# penceresinin uygulama adiyla gorunmesi) icin ciplak ikili degil, bir .app
# paketi gerekir. wipe-helper de arayuzun yaninda, ayni MacOS dizininde durur —
# PrivilegedRunner onu orada arar.
#
# Kullanim:
#   Scripts/make-app.sh                 # yerel mimari, release
#   Scripts/make-app.sh --universal     # arm64 + x86_64
#   Scripts/make-app.sh --debug         # debug yapilandirmasi
#   Scripts/make-app.sh --open          # bitince Finder'da goster

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
BUILD_FLAGS=()
REVEAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --universal) BUILD_FLAGS+=(--arch arm64 --arch x86_64) ;;
        --debug)     CONFIG="debug" ;;
        --open)      REVEAL=1 ;;
        -h|--help)   sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           echo "Bilinmeyen secenek: $1" >&2; exit 2 ;;
    esac
    shift
done

APP="$ROOT/build/WipeDisk.app"
MACOS_DIR="$APP/Contents/MacOS"
RESOURCES_DIR="$APP/Contents/Resources"

echo "==> Derleniyor ($CONFIG)…"
swift build -c "$CONFIG" ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"}

BIN_DIR="$(swift build -c "$CONFIG" ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"} --show-bin-path)"

for binary in WipeDisk wipe-helper; do
    if [[ ! -x "$BIN_DIR/$binary" ]]; then
        echo "Hata: $BIN_DIR/$binary bulunamadi." >&2
        exit 1
    fi
done

echo "==> Paket olusturuluyor: $APP"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/WipeDisk"    "$MACOS_DIR/WipeDisk"
cp "$BIN_DIR/wipe-helper" "$MACOS_DIR/wipe-helper"
chmod +x "$MACOS_DIR/WipeDisk" "$MACOS_DIR/wipe-helper"

# Ikon kodla uretiliyor; deponun icinde hazir yoksa simdi uret.
if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
    echo "==> Ikon uretiliyor…"
    mkdir -p "$ROOT/Resources"
    swift "$ROOT/Scripts/make-icon.swift" "$ROOT/Resources"
fi
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>WipeDisk</string>
    <key>CFBundleDisplayName</key>          <string>WipeDisk</string>
    <key>CFBundleIdentifier</key>           <string>com.wipedisk.app</string>
    <key>CFBundleExecutable</key>           <string>WipeDisk</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>1.0</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>LSApplicationCategoryType</key>    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key> <true/>
    <!-- Yonetici yetkisi penceresi osascript uzerinden aciliyor. -->
    <key>NSAppleEventsUsageDescription</key>
    <string>WipeDisk, secilen diski silmek icin yonetici yetkisi ister.</string>
</dict>
</plist>
PLIST

# Ad-hoc imza: imzasiz paketler Gatekeeper tarafindan aninda oldurulebiliyor.
# Helper once imzalanmali; paket disaridan iceriye dogru imzalanir.
echo "==> Imzalaniyor (ad-hoc)…"
codesign --force --sign - "$MACOS_DIR/wipe-helper"
codesign --force --sign - "$APP"

echo "==> Hazir: $APP"
echo "    Calistir:  open '$APP'"
echo "    Helper:    sudo '$MACOS_DIR/wipe-helper' --list"

if [[ $REVEAL -eq 1 ]]; then
    open -R "$APP"
fi
