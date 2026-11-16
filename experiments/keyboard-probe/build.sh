#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
sdk_stage=$(mktemp -d /tmp/uhnmeyker-kbd-sdk.XXXXXXXX)
trap 'rm -rf -- "$sdk_stage"' EXIT
unzip -q "${1:-../ps5-payload-sdk-v0.43.zip}" -d "$sdk_stage"
make PS5_PAYLOAD_SDK="$sdk_stage/ps5-payload-sdk" all check
file build/ps5-keyboard-probe.elf
readelf -d build/ps5-keyboard-probe.elf | sed -n '/NEEDED/p'
if nm build/ps5-keyboard-probe.elf | grep -q 'ps_mouse_'; then
  echo 'Unexpected mouse code linked' >&2
  exit 1
fi
