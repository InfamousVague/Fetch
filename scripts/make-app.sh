#!/usr/bin/env bash
# Phase 3+4: assemble a self-contained, Developer-ID-signed Fetch.app.
# Vendors libtorrent + openssl into Contents/Frameworks, rewrites all
# install names to @rpath, signs inside-out (hardened runtime). Does NOT
# notarize (needs Apple creds — run notarize separately).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/Fetch.app"
SRC_ICON="$ROOT/art/AppIcon-source.png"
VERSION="0.1.0"
SIGN_IDENTITY="${SIGN_IDENTITY:-0948896DC970503ADEF5B5070E0BB3E9D9047757}"
real() { python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"; }

echo "› swift build -c release"
swift build -c release --product Fetch
BIN="$(swift build -c release --show-bin-path)/Fetch"

echo "› assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Fetch"
FW="$APP/Contents/Frameworks"

# 1. Vendor the three non-system dylibs (copy the real files).
cp "$(real /opt/homebrew/opt/libtorrent-rasterbar/lib/libtorrent-rasterbar.2.0.dylib)" "$FW/libtorrent-rasterbar.2.0.dylib"
cp "$(real /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib)"    "$FW/libssl.3.dylib"
cp "$(real /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib)" "$FW/libcrypto.3.dylib"
chmod u+w "$FW"/*.dylib

# 2. Rewrite a Mach-O's /opt/homebrew deps → @rpath/<basename>, mapping
#    libtorrent's versioned basename to our canonical name.
relink() {
  local f="$1"
  otool -L "$f" | awk 'NR>1{print $1}' | grep -E '^/opt/homebrew' | while read -r dep; do
    local base; base="$(basename "$dep")"
    case "$base" in
      libtorrent-rasterbar*.dylib) base="libtorrent-rasterbar.2.0.dylib" ;;
      libssl*.dylib)               base="libssl.3.dylib" ;;
      libcrypto*.dylib)            base="libcrypto.3.dylib" ;;
    esac
    install_name_tool -change "$dep" "@rpath/$base" "$f"
  done
}

install_name_tool -id @rpath/libcrypto.3.dylib            "$FW/libcrypto.3.dylib"
install_name_tool -id @rpath/libssl.3.dylib               "$FW/libssl.3.dylib";  relink "$FW/libssl.3.dylib"
install_name_tool -id @rpath/libtorrent-rasterbar.2.0.dylib "$FW/libtorrent-rasterbar.2.0.dylib"; relink "$FW/libtorrent-rasterbar.2.0.dylib"
relink "$APP/Contents/MacOS/Fetch"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Fetch"

# 3. App icon (optional — Fetch has no art yet).
ICON_KEY=""
if [ -f "$SRC_ICON" ]; then
  IS="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$IS"
  for s in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
    sips -z "${s%%:*}" "${s%%:*}" "$SRC_ICON" --out "$IS/icon_${s##*:}.png" >/dev/null
  done
  iconutil -c icns "$IS" -o "$APP/Contents/Resources/AppIcon.icns"
  ICON_KEY="  <key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Fetch</string>
  <key>CFBundleDisplayName</key><string>Fetch</string>
  <key>CFBundleIdentifier</key><string>com.mattssoftware.fetch</string>
  <key>CFBundleExecutable</key><string>Fetch</string>
$ICON_KEY
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <!-- Vendored libtorrent/openssl Homebrew bottles are built minos 26.0,
       so this is the honest floor (raise broader support = rebuild deps). -->
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Fetch</string>
</dict>
</plist>
PLIST

# 4. Sign inside-out: dylibs, then exe, then bundle (hardened runtime).
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  for d in libcrypto.3.dylib libssl.3.dylib libtorrent-rasterbar.2.0.dylib; do
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$FW/$d"
  done
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/Fetch"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=1 "$APP" && echo "✓ signed (Developer ID, hardened runtime)"
else
  echo "⚠ Developer ID not found — ad-hoc signing"
  for d in "$FW"/*.dylib; do codesign --force -s - "$d"; done
  codesign --force --deep -s - "$APP" || true
fi

echo "✓ built $APP"
echo "── residual /opt/homebrew refs (should be none): ──"
( otool -L "$APP/Contents/MacOS/Fetch" "$FW"/*.dylib | grep -E '/opt/homebrew' || echo "  none ✓" )
