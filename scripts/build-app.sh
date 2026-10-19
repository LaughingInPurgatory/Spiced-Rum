#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="${SPICED_RUM_BUILD_DIR:-${TMPDIR:-/tmp}/spiced-rum-build}"
export CLANG_MODULE_CACHE_PATH="$build_dir/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/cache/swift"
swift build --disable-sandbox --build-system native --scratch-path "$build_dir" --cache-path "$build_dir/cache" -c release --arch arm64
app="$PWD/dist/Spiced-Rum.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
rm -f "$app/Icon$(printf '\r')"
xattr -d com.apple.FinderInfo "$app" 2>/dev/null || true
cp "$build_dir/arm64-apple-macosx/release/SpicedRum" "$app/Contents/MacOS/SpicedRum"
mkdir -p "$app/Contents/Resources/ThirdParty"
cp Sources/SpicedRum/Resources/ThirdParty/steamwebhelper-wrapper.exe Sources/SpicedRum/Resources/ThirdParty/steamwebhelper-wrapper.c Sources/SpicedRum/Resources/ThirdParty/steam-on-m1-wine-MIT-LICENSE.txt "$app/Contents/Resources/ThirdParty/"
swiftc -parse-as-library -module-cache-path "$build_dir/cache/icon-generator" scripts/generate-app-icon.swift -o "$build_dir/generate-app-icon"
iconset="$build_dir/SpicedRum.iconset"
rm -rf "$iconset"
"$build_dir/generate-app-icon" "$build_dir/ShotglassMark.png" "$build_dir/AppIcon.png" "$iconset"
cp "$build_dir/ShotglassMark.png" "$app/Contents/Resources/ShotglassMark.png"
cp "$build_dir/AppIcon.png" "$app/Contents/Resources/AppIcon.png"
rm -f "$app/Contents/Resources/AppIcon.icns"
asset_catalog="$build_dir/SpicedRumAssets.xcassets"
iconset_assets="$asset_catalog/AppIcon.appiconset"
rm -rf "$asset_catalog"
mkdir -p "$iconset_assets"
cp "$iconset"/*.png "$iconset_assets/"
cat > "$iconset_assets/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
asset_output="$build_dir/asset-output"
rm -rf "$asset_output"
mkdir -p "$asset_output"
xcrun actool --compile "$asset_output" --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$build_dir/asset-info.plist" "$asset_catalog"
cp "$asset_output/Assets.car" "$app/Contents/Resources/Assets.car"
cp "$asset_output/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.spicedrum.mac</string>
<key>CFBundleName</key><string>Spiced-Rum</string>
<key>CFBundleDisplayName</key><string>Spiced-Rum</string>
<key>CFBundleExecutable</key><string>SpicedRum</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.3</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
printf 'APPL????' > "$app/Contents/PkgInfo"
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
