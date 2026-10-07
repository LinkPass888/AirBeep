#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AIRCARD_REPO="${AIRCARD_REPO:-https://github.com/mak5er/AirCard-iOS.git}"
AIRCARD_COMMIT="${AIRCARD_COMMIT:-40640c4d827aeab8d798285b57d24fcf6be070d0}"
BUILD_PARENT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
BUILD_ROOT="$BUILD_PARENT/airbeep-aircard-$AIRCARD_COMMIT"
PATCH_FILE="$ROOT/scripts/airlift-read-file.patch"

# AirCard's build script otherwise defaults to a beta Xcode app that is not
# present on the GitHub runner. setup-xcode has already selected the right one.
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

rm -rf "$BUILD_ROOT"
git clone --quiet --filter=blob:none "$AIRCARD_REPO" "$BUILD_ROOT"
git -C "$BUILD_ROOT" checkout --quiet --detach "$AIRCARD_COMMIT"

# Make the Rust LLVM nm available so verify-airlift.sh can inspect the
# patch-added symbols. The Xcode nm cannot read Rust's compiler_builtins
# objects (LLVM version mismatch).
if command -v rustup >/dev/null 2>&1; then
  rustup component add llvm-tools-preview 2>/dev/null || true
fi

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
