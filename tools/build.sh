#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app"
SDK="${1:-${IOS_SDK:-$ROOT/work/ios-sdks/iPhoneOS16.5.sdk}}"
test -f "$SDK/SDKSettings.plist" || { echo 'Set IOS_SDK to an iPhoneOS SDK directory.' >&2; exit 1; }
# This frozen management protocol must survive every public helper revision.
make -C "$ROOT/service" build/padd-host
python3 "$ROOT/service/stop_contract_test.py" "$ROOT/service/build/padd-host"
mkdir -p "$ROOT/work" "$ROOT/dist"
BUILD="$(mktemp -d "$ROOT/work/ps5-pad-build.XXXXXXXX")"
APP="$BUILD/Payload/PS5Pad.app"
mkdir -p "$APP"
cc -std=c11 -Wall -Wextra -Werror test_loader.c -o "$BUILD/test_loader"
"$BUILD/test_loader"
cc -std=c11 -Wall -Wextra -Werror test_helper_update.c -o "$BUILD/test_helper_update"
"$BUILD/test_helper_update"
cc -std=c11 -Wall -Wextra -Werror test_protocol.c -o "$BUILD/test_protocol"
cc -std=c11 -Wall -Wextra -Werror test_input_queue.c -o "$BUILD/test_input_queue"
cc -std=c11 -Wall -Wextra -Werror test_initialization.c -o "$BUILD/test_initialization"
cc -std=c11 -Wall -Wextra -Werror test_lifecycle.c -o "$BUILD/test_lifecycle"
"$BUILD/test_lifecycle"
cc -std=c11 -Wall -Wextra -Werror test_input_feedback.c -o "$BUILD/test_input_feedback"
"$BUILD/test_protocol"
"$BUILD/test_input_queue"
"$BUILD/test_initialization"
"$BUILD/test_input_feedback"
cc -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror test_discovery.c -o "$BUILD/test_discovery"
"$BUILD/test_discovery"
python3 check_ui_contract.py "$SDK"
python3 "$ROOT/tools/check_poweroff_scope.py"
cc -std=c11 -Wall -Wextra -Werror test_poweroff.c -o "$BUILD/test_poweroff"
"$BUILD/test_poweroff"
# Keep the existing portable compiler pipeline, but use the installed Apple
# toolchain on GitHub's macOS runners instead of requiring Linux llvm-18.
if [[ "$(uname -s)" == Darwin ]]; then
  IOS_CC=(xcrun --sdk iphoneos clang)
  IOS_LD=(xcrun --sdk iphoneos ld)
  SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
else
  IOS_CC=(clang-18)
  IOS_LD=(ld64.lld-18)
  SDK_VERSION=16.5
fi
for source in main QPConnection QPDiscovery QPLocalNetworkAccess QPHelperLoader QPPowerOff; do
  "${IOS_CC[@]}" -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fblocks -O2 -Wall -Wextra \
    -Werror -Wno-unused-parameter -c "$source.m" -o "$BUILD/$source.o"
done
"${IOS_LD[@]}" -arch arm64 -platform_version ios 15.0 "$SDK_VERSION" -syslibroot "$SDK" \
  -o "$APP/PS5Pad" "$BUILD/main.o" "$BUILD/QPConnection.o" "$BUILD/QPDiscovery.o" "$BUILD/QPLocalNetworkAccess.o" "$BUILD/QPHelperLoader.o" "$BUILD/QPPowerOff.o" \
  -lSystem -lobjc -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework Network \
  -headerpad 0x4000 -no_adhoc_codesign
cp Info.plist "$APP/Info.plist"
# Packaging must fail, not silently substitute old Rest Mode behavior.
HELPER_VERSION="$(python3 - "$ROOT/service/payload/padd.c" <<'PY'
import re, sys
from pathlib import Path
source=Path(sys.argv[1]).read_text()
found=re.search(r'PADD_VERSION\s+0x([0-9A-Fa-f]+)',source)
if not found: raise SystemExit('Cannot identify PS5 helper version')
number=int(found.group(1),16)
print(f'{number >> 8}.{number & 255}')
PY
)"
ELF="$ROOT/service/prebuilt/padd-controller-$HELPER_VERSION.elf"
test -f "$ELF" || { echo "Missing verified helper $HELPER_VERSION ELF; do not package an older helper." >&2; exit 1; }
cp "$ELF" "$APP/padd-controller.elf"
cp "$ROOT/service/prebuilt/ps5pad-poweroff-1.0.elf" "$APP/ps5pad-poweroff.elf"
VERSION="$(python3 -c 'import plistlib; print(plistlib.load(open("Info.plist","rb"))["CFBundleShortVersionString"])')"
OUTPUT="$ROOT/dist/PS5-Pad-$VERSION-unsigned.ipa"
python3 package.py "$APP" "$BUILD/PS5-Pad.ipa"
python3 verify_ipa.py "$BUILD/PS5-Pad.ipa" --elf "$ELF" --report "$BUILD/verification.json"
cp "$BUILD/PS5-Pad.ipa" "$OUTPUT"
cp "$BUILD/verification.json" "$ROOT/dist/PS5-Pad-$VERSION-verification.json"
python3 "$ROOT/tools/prepare_source.py" --ipa "$OUTPUT" --report "$ROOT/dist/PS5-Pad-$VERSION-verification.json"
printf 'Ready: %s\n' "$OUTPUT"
