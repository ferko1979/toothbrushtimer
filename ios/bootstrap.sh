#!/bin/bash
# Generates ToothbrushTimer.xcodeproj and opens it in Xcode.
#   ./bootstrap.sh                 (asks for the bundle ID prefix)
#   BUNDLE_PREFIX=hu.nev DEVELOPMENT_TEAM=ABCDE12345 ./bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodebuild >/dev/null; then
  echo "Hiba: Xcode kell (App Store → Xcode), majd: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null; then
  if command -v brew >/dev/null; then
    echo "XcodeGen telepítése Homebrew-val..."
    brew install xcodegen
  else
    echo "Hiba: telepítsd a Homebrew-t (https://brew.sh), vagy az XcodeGen-t: https://github.com/yonaskolb/XcodeGen" >&2
    exit 1
  fi
fi

CONFIG=.bootstrap.env
[ -f "$CONFIG" ] && source "$CONFIG"
if [ -z "${BUNDLE_PREFIX:-}" ]; then
  default="hu.$(whoami | tr -cd 'a-zA-Z0-9' | tr 'A-Z' 'a-z')"
  read -r -p "Bundle ID előtag (egyedi legyen, pl. ${default}): " BUNDLE_PREFIX
  BUNDLE_PREFIX=${BUNDLE_PREFIX:-$default}
fi
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  read -r -p "Apple Team ID (üresen hagyható, ilyenkor Xcode-ban választod ki): " DEVELOPMENT_TEAM || true
fi
printf 'BUNDLE_PREFIX=%s\nDEVELOPMENT_TEAM=%s\n' "$BUNDLE_PREFIX" "${DEVELOPMENT_TEAM:-}" > "$CONFIG"
export BUNDLE_PREFIX DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"

echo "Projekt generálása (bundle ID: ${BUNDLE_PREFIX}.toothbrushtimer)..."
xcodegen generate
echo
echo "Kész. Gyors ellenőrzés a Swift-portra (Python-referenciával összevetve):"
echo "  (cd BrushCore && swift test)"
echo
open ToothbrushTimer.xcodeproj
