#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
shasum -a 256 -c Vendor/AirCard/SHA256SUMS

for library in \
  Vendor/AirCard/AirliftFFI.xcframework/ios-arm64/libairlift_ffi.a \
  Vendor/AirCard/AirliftFFI.xcframework/ios-arm64-simulator/libairlift_ffi.a
do
  for symbol in al_exploit_read_file al_bytes_free al_set_target_host; do
    if ! nm -gU "$library" | grep -Eq "[[:space:]]_${symbol}$"; then
      echo "Airlift library is missing $symbol: $library" >&2
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
