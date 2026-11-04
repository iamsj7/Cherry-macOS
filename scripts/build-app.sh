#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${PWD}/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${PWD}/.build/swiftpm-module-cache"
export XDG_CACHE_HOME="${PWD}/.build/cache"
flags=(--disable-sandbox -debug-info-format none -c release --arch arm64)
swift build "${flags[@]}"
# The output folder differs between Swift toolchains, so ask for it.
binary="$(swift build "${flags[@]}" --show-bin-path | tail -n 1)/CherryTools"
app="${PWD}/dist/CherryTools.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/CherryTools"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/CherryTools.icns "$app/Contents/Resources/CherryTools.icns"
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$app"
echo "$app"
