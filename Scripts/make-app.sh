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
#   Scripts/make-app.sh --install     # /Applications altina kur

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
BUILD_FLAGS=()
REVEAL=0
INSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --universal) BUILD_FLAGS+=(--arch arm64 --arch x86_64) ;;
        --debug)     CONFIG="debug" ;;
        --open)      REVEAL=1 ;;
        --install)   INSTALL=1 ;;
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

# NTFS bicimlendirme araclari. macOS NTFS olusturamadigi icin mkntfs paketle
# birlikte tasiniyor; kutuphaneyi @loader_path uzerinden yaninda buluyor.
if [[ ! -x "$ROOT/Vendor/ntfsprogs/bin/mkntfs" ]]; then
    echo "==> NTFS araclari derleniyor…"
    "$ROOT/Scripts/build-ntfsprogs.sh"
fi
cp "$ROOT/Vendor/ntfsprogs/bin/mkntfs" "$MACOS_DIR/mkntfs"
cp "$ROOT"/Vendor/ntfsprogs/bin/libntfs-3g.*.dylib "$MACOS_DIR/"
chmod +x "$MACOS_DIR/mkntfs"

# GPL-2.0 kosulu: ikili dagitiliyorsa lisans metni ve kaynak bilgisi yaninda olmali.
mkdir -p "$RESOURCES_DIR/Licenses"
cp "$ROOT/Vendor/ntfsprogs/COPYING"    "$RESOURCES_DIR/Licenses/ntfs-3g-COPYING"
cp "$ROOT/Vendor/ntfsprogs/COPYING.LIB" "$RESOURCES_DIR/Licenses/ntfs-3g-COPYING.LIB" 2>/dev/null || true
cp "$ROOT/Vendor/ntfsprogs/KAYNAK.txt" "$RESOURCES_DIR/Licenses/ntfs-3g-KAYNAK.txt"

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

# --- NTFS yazma modulu (FSKit uzantisi) -------------------------------------
#
# ExtensionKit uzantilari uygulama paketinin Contents/Extensions/ dizininde
# durur. Modulun yuklenebilmesi com.apple.developer.fskit.fsmodule yetkisine
# baglidir; bu yetki yalnizca ucretli bir gelistirici hesabina bagli
# provisioning profile ile gecerlidir. SIGN_IDENTITY verilmezse paket yine
# uretilir ama sistem yuklemez.
if [[ -x "$BIN_DIR/NTFSFSModule" ]]; then
    APPEX="$APP/Contents/Extensions/NTFSFSModule.appex"
    echo "==> NTFS modulu paketleniyor…"
    mkdir -p "$APPEX/Contents/MacOS"
    cp "$BIN_DIR/NTFSFSModule" "$APPEX/Contents/MacOS/NTFSFSModule"

    cat > "$APPEX/Contents/Info.plist" <<'APPEXPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>NTFSFSModule</string>
    <key>CFBundleDisplayName</key>        <string>NTFS</string>
    <key>CFBundleIdentifier</key>         <string>com.wipedisk.app.ntfs</string>
    <key>CFBundleExecutable</key>         <string>NTFSFSModule</string>
    <!-- Uzantilar XPC paketi olarak isaretlenir; Apple'in FSKit modulleri de boyle. -->
    <key>CFBundlePackageType</key>        <string>XPC!</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>LSMinimumSystemVersion</key>     <string>15.4</string>
    <key>EXAppExtensionAttributes</key>
    <dict>
        <key>EXExtensionPointIdentifier</key> <string>com.apple.fskit.fsmodule</string>
        <key>EXExtensionPrincipalClass</key>  <string>NTFSFileSystem</string>
        <!-- Hangi ortamlarda taninma denenecegi. Tanima isini modulun
             probeResource'u yapiyor, ayri bir probe ikilisi yok. -->
        <key>FSMediaTypes</key>
        <dict>
            <key>EBD0A0A2-B9E5-4433-87C0-68B6B72699C7</key>
            <dict>
                <key>FSMediaProperties</key>
                <dict>
                    <key>Content Hint</key> <string>EBD0A0A2-B9E5-4433-87C0-68B6B72699C7</string>
                    <key>Leaf</key>         <true/>
                </dict>
                <key>FSProbeOrder</key>     <integer>1000</integer>
            </dict>
            <key>Windows_NTFS</key>
            <dict>
                <key>FSMediaProperties</key>
                <dict>
                    <key>Content Hint</key> <string>Windows_NTFS</string>
                    <key>Leaf</key>         <true/>
                </dict>
                <key>FSProbeOrder</key>     <integer>1000</integer>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
APPEXPLIST

    # Uzanti kendi yetkileriyle, paketten once imzalanir.
    if [[ -n "${SIGN_IDENTITY:-}" ]]; then
        codesign --force --timestamp --options runtime \
                 --entitlements "$ROOT/Resources/NTFSFSModule.entitlements" \
                 --sign "$SIGN_IDENTITY" "$APPEX"
        echo "    Modul imzalandi: $SIGN_IDENTITY"
    else
        codesign --force --entitlements "$ROOT/Resources/NTFSFSModule.entitlements" \
                 --sign - "$APPEX"
        echo "    UYARI: ad-hoc imza — sistem bu modulu YUKLEMEZ."
        echo "    Gercek kurulum icin: SIGN_IDENTITY=\"Developer ID Application: …\" Scripts/make-app.sh"
    fi
fi

# Ad-hoc imza: imzasiz paketler Gatekeeper tarafindan aninda oldurulebiliyor.
# Helper once imzalanmali; paket disaridan iceriye dogru imzalanir.
echo "==> Imzalaniyor (ad-hoc)…"
# Ic ikililer once imzalanir; paket disaridan iceriye dogru imzalanir.
codesign --force --sign - "$MACOS_DIR"/libntfs-3g.*.dylib
codesign --force --sign - "$MACOS_DIR/mkntfs"
codesign --force --sign - "$MACOS_DIR/wipe-helper"
codesign --force --sign - "$APP"

echo "==> Hazir: $APP"

if [[ $INSTALL -eq 1 ]]; then
    TARGET="/Applications/WipeDisk.app"
    echo "==> Kuruluyor: $TARGET"

    # Uzerine yazmadan once calisan ornegi kapat; acik ikili degistirilemez.
    osascript -e 'tell application "WipeDisk" to quit' 2>/dev/null || true
    pkill -f "WipeDisk.app/Contents/MacOS/WipeDisk" 2>/dev/null || true
    sleep 1

    if [[ ! -w /Applications ]]; then
        echo "Hata: /Applications yazilabilir degil. sudo ile calistirin." >&2
        exit 1
    fi

    rm -rf "$TARGET"
    cp -R "$APP" "$TARGET"
    codesign --verify --strict "$TARGET" || {
        echo "Hata: kurulan paketin imzasi dogrulanamadi." >&2
        exit 1
    }
    echo "==> Kuruldu: $TARGET"
    APP="$TARGET"
fi

echo "    Calistir:  open '$APP'"
echo "    Helper:    sudo '$APP/Contents/MacOS/wipe-helper' --list"
echo
echo "    Not: paket ad-hoc imzali oldugundan her derlemede imza ozeti degisir."
echo "    Silme islemi icin Tam Disk Erisimi iznini bu kuruluma yeniden verin."

if [[ $REVEAL -eq 1 ]]; then
    open -R "$APP"
fi
