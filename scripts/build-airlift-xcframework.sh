#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AIRCARD_REPO="${AIRCARD_REPO:-https://github.com/mak5er/AirCard-iOS.git}"
AIRCARD_COMMIT="${AIRCARD_COMMIT:-40640c4d827aeab8d798285b57d24fcf6be070d0}"
BUILD_PARENT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
BUILD_ROOT="$BUILD_PARENT/airbeep-aircard-$AIRCARD_COMMIT"
PATCH_FILE="$ROOT/scripts/airlift-read-file.patch"

rm -rf "$BUILD_ROOT"
git clone --quiet --filter=blob:none "$AIRCARD_REPO" "$BUILD_ROOT"
git -C "$BUILD_ROOT" checkout --quiet --detach "$AIRCARD_COMMIT"

git -C "$BUILD_ROOT" apply --check "$PATCH_FILE"
git -C "$BUILD_ROOT" apply "$PATCH_FILE"

"$BUILD_ROOT/build-ios.sh"

rm -rf "$ROOT/Vendor/AirCard/AirliftFFI.xcframework"
cp -R "$BUILD_ROOT/AirliftFFI.xcframework" "$ROOT/Vendor/AirCard/AirliftFFI.xcframework"

cd "$ROOT"
{
  find Vendor/AirCard/AirliftFFI.xcframework -type f -print
  printf '%s\n' placard/Airlift/GrappaHelper.h placard/Airlift/GrappaHelper.m
} | LC_ALL=C sort | xargs shasum -a 256 > Vendor/AirCard/SHA256SUMS

echo "Built patched AirliftFFI from AirCard-iOS $AIRCARD_COMMIT"
