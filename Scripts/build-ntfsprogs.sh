#!/bin/bash
# NTFS bicimlendirme araclarini (mkntfs + libntfs-3g) kaynaktan derler.
#
# macOS NTFS olusturamaz: `diskutil listFilesystems` ciktisinda NTFS yoktur ve
# ntfs.fs paketinde bir bicimlendirici tanimli degildir. Bu bosluk, ntfs-3g
# projesinin `mkntfs` araciyla kapatiliyor.
#
# FUSE surucusu (`--disable-ntfs-3g`) kasten derlenmiyor: macFUSE kapali kaynak
# bir cekirdek eklentisi gerektiriyor ve Apple Silicon'da kullanicinin Guvenli
# Acilisi dusurmesini sart kosuyor. Bize yalnizca kullanici alaninda calisan,
# blok aygitina yazan `mkntfs` gerekiyor.
#
# Uretilenler:
#   Vendor/ntfsprogs/bin/mkntfs
#   Vendor/ntfsprogs/lib/libntfs-3g.*.dylib
#   Vendor/ntfsprogs/COPYING          (GPL-2.0 metni)
#
# Kullanim: Scripts/build-ntfsprogs.sh [--force]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Vendor/ntfsprogs"
VERSION="2026.7.7"
TARBALL="ntfs-3g_ntfsprogs-${VERSION}.tgz"
URL="https://tuxera.com/opensource/${TARBALL}"
# Homebrew formulunun kullandigi surumle ayni kaynak.
EXPECTED_SHA="d67b769025d32860549d35c2147e45024d172f81c540d750390ce3602c059dab"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

if [[ $FORCE -eq 0 && -x "$VENDOR/bin/mkntfs" ]]; then
    echo "==> mkntfs zaten var: $VENDOR/bin/mkntfs"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Kaynak indiriliyor ($VERSION)…"
curl -sL --max-time 180 -o "$WORK/$TARBALL" "$URL"

echo "==> Butunluk dogrulaniyor…"
ACTUAL_SHA="$(shasum -a 256 "$WORK/$TARBALL" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
    echo "Hata: SHA-256 uyusmadi." >&2
    echo "  beklenen: $EXPECTED_SHA" >&2
    echo "  gelen   : $ACTUAL_SHA" >&2
    exit 1
fi

tar xzf "$WORK/$TARBALL" -C "$WORK"
SRC="$WORK/ntfs-3g-${VERSION}"

# configure yalnizca varligini arayip surumunu sordugu icin sahte bir pkg-config
# yeterli: FUSE kapali oldugundan gercek modul sorgusu yapilmiyor.
mkdir -p "$WORK/stub"
cat > "$WORK/stub/pkg-config" <<'STUB'
#!/bin/sh
case "$1" in
  --version) echo "0.29.2"; exit 0 ;;
  --atleast-pkgconfig-version) exit 0 ;;
esac
exit 1
STUB
chmod +x "$WORK/stub/pkg-config"

echo "==> Yapilandiriliyor…"
cd "$SRC"
PATH="$WORK/stub:$PATH" ./configure \
    --prefix="$VENDOR" \
    --disable-ntfs-3g \
    --disable-mount-helper \
    --without-uuid \
    --disable-dependency-tracking \
    > "$WORK/configure.log" 2>&1 || { tail -25 "$WORK/configure.log" >&2; exit 1; }

echo "==> Derleniyor…"
make -j"$(sysctl -n hw.ncpu)" > "$WORK/build.log" 2>&1 || { tail -25 "$WORK/build.log" >&2; exit 1; }

# `make install` kullanilmiyor: install-exec-hook Linux'a ozgu, libntfs-3g.so
# dosyalarini /lib altina tasimaya calisip macOS'ta basarisiz oluyor. Uretilen
# iki dosyayi elle almak hem yeterli hem daha ongorulebilir.
echo "==> Kuruluyor: $VENDOR"
rm -rf "$VENDOR"
mkdir -p "$VENDOR/bin"

DYLIB="$(find "$SRC/libntfs-3g/.libs" -name "libntfs-3g.*.dylib" -type f | head -1)"
[[ -n "$DYLIB" ]] || { echo "Hata: libntfs-3g dylib bulunamadi." >&2; exit 1; }

cp "$SRC/ntfsprogs/.libs/mkntfs" "$VENDOR/bin/mkntfs"
cp "$DYLIB" "$VENDOR/bin/$(basename "$DYLIB")"

# FSKit modulu libntfs-3g'ye dogrudan baglanacak: basliklar ve statik kutuphane.
# Uzanti icinde statik baglamak, paket ici dylib yolu derdini tamamen kaldiriyor.
mkdir -p "$VENDOR/include/ntfs-3g" "$VENDOR/lib"
cp "$SRC"/include/ntfs-3g/*.h "$VENDOR/include/ntfs-3g/"
# config.h ureti sirasinda olusuyor ve basliklar onu bekliyor.
cp "$SRC/config.h" "$VENDOR/include/config.h"
if [[ -f "$SRC/libntfs-3g/.libs/libntfs-3g.a" ]]; then
    cp "$SRC/libntfs-3g/.libs/libntfs-3g.a" "$VENDOR/lib/libntfs-3g.a"
fi

# Kutuphane yolu derleme dizinine mutlak olarak gomulu geliyor; uygulama
# paketinin icinde de calisabilmesi icin ikilinin yanini gosterecek sekilde
# yeniden yaziliyor.
install_name_tool -id "@loader_path/$(basename "$DYLIB")" "$VENDOR/bin/$(basename "$DYLIB")"
OLD_REF="$(otool -L "$VENDOR/bin/mkntfs" | awk '/libntfs-3g/{print $1}')"
install_name_tool -change "$OLD_REF" "@loader_path/$(basename "$DYLIB")" "$VENDOR/bin/mkntfs"
chmod +x "$VENDOR/bin/mkntfs"

# GPL-2.0 kosulu: ikili dagitiliyorsa lisans metni de yaninda bulunmali.
cp "$SRC/COPYING" "$VENDOR/COPYING"
cp "$SRC/COPYING.LIB" "$VENDOR/COPYING.LIB" 2>/dev/null || true
cat > "$VENDOR/KAYNAK.txt" <<EOF
ntfs-3g / ntfsprogs $VERSION
Kaynak: $URL
SHA-256: $EXPECTED_SHA
Lisans: GPL-2.0-or-later (mkntfs), LGPL-2.0-or-later (libntfs-3g)

Bu ikililer degistirilmeden, yukaridaki kaynaktan derlenmistir.
Derleme secenekleri: --disable-ntfs-3g --disable-mount-helper --without-uuid
EOF

echo "==> Hazir:"
"$VENDOR/bin/mkntfs" --version 2>&1 | head -1
