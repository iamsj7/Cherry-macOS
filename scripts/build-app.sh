#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${PWD}/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${PWD}/.build/swiftpm-module-cache"
export XDG_CACHE_HOME="${PWD}/.build/cache"
swift build --disable-sandbox -debug-info-format none -c release --arch arm64
app="${PWD}/dist/CherryTools.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/out/Products/Release/CherryTools "$app/Contents/MacOS/CherryTools"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/CherryTools.icns "$app/Contents/Resources/CherryTools.icns"
cp Resources/CherryToolsIcon.png "$app/Contents/Resources/CherryToolsIcon.png"
codesign --force --sign - "$app"
echo "$app"
