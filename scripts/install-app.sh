#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi
export CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
./scripts/build-app.sh

pkill -x CherryTools 2>/dev/null || true
while pgrep -x CherryTools >/dev/null; do sleep 0.2; done

target="/Applications/CherryTools.app"
rm -rf "$target"
ditto dist/CherryTools.app "$target"
codesign --verify --strict "$target"
open "$target"
echo "$target"
