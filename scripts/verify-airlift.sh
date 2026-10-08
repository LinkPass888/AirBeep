#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
shasum -a 256 -c Vendor/AirCard/SHA256SUMS

# The Xcode nm cannot parse the compiler_builtins objects emitted by newer
# Rust (LLVM 22) and crashes with "Unknown attribute kind", falsely reporting
# our patch-added symbols as missing. Use the Rust LLVM nm instead, which is
# built from the same LLVM and reads them correctly.
find_nm() {
  # rustup llvm-tools-preview places llvm-nm inside the active toolchain.
  if command -v rustc >/dev/null 2>&1; then
    local sysroot host nm_bin
    sysroot="$(rustc --print sysroot)"
    host="$(rustc -vV | sed -n 's/^host: //p')"
    nm_bin="$sysroot/lib/rustlib/$host/bin/llvm-nm"
    [ -x "$nm_bin" ] && { printf '%s' "$nm_bin"; return; }
  fi
  command -v llvm-nm && return
  command -v rust-nm && return
  command -v nm
}
NM="$(find_nm)"

for library in \
  Vendor/AirCard/AirliftFFI.xcframework/ios-arm64/libairlift_ffi.a \
  Vendor/AirCard/AirliftFFI.xcframework/ios-arm64-simulator/libairlift_ffi.a
do
  for symbol in al_exploit_read_file al_bytes_free al_set_target_host; do
    found=false
    if "$NM" -gU "$library" 2>/dev/null | grep -q "_${symbol}"; then
      found=true
    elif strings "$library" 2>/dev/null | grep -q "_${symbol}"; then
      found=true
    fi
    if [ "$found" = "false" ]; then
      echo "Airlift library is missing $symbol: $library (nm=$NM)" >&2
      echo "Available _al_ symbols via NM:" >&2
      "$NM" -gU "$library" 2>&1 | grep "_al_" | head -n 30 || true
      echo "Available _al_ symbols via strings:" >&2
      strings "$library" 2>/dev/null | grep "_al_" | head -n 30 || true
      exit 1
    fi
  done
done

if [[ $# -eq 0 ]]; then
  exit 0
fi

app_path="$1"
expected_version="$2"
# Rust resolves this symbol with dlsym, so a successful link alone is insufficient.
exports=$(xcrun dyld_info -exports "$app_path/placard")
for symbol in _ALGetGrappaToken _al_exploit_read_file _al_bytes_free _al_set_target_host; do
  if ! grep -q "${symbol}$" <<< "$exports"; then
    echo "Archive is missing exported symbol $symbol" >&2
    exit 1
  fi
done
python3 - "$app_path/Info.plist" "$expected_version" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as file:
    info = plistlib.load(file)
assert info['CFBundleShortVersionString'] == sys.argv[2], 'Archive version mismatch'
assert '_remotepairing-pairable-host._tcp' in info['NSBonjourServices']
assert '_aircardprobe._tcp' in info['NSBonjourServices']
assert info['NSLocalNetworkUsageDescription']
assert 'audio' in info['UIBackgroundModes']
print('Archive version, Grappa export and Airlift permissions verified')
PY
