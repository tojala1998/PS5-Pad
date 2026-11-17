#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app"
SDK="${1:-${IOS_SDK:-$ROOT/work/ios-sdks/iPhoneOS16.5.sdk}}"
test -f "$SDK/SDKSettings.plist" || { echo 'Set IOS_SDK to an iPhoneOS SDK directory.' >&2; exit 1; }
mkdir -p "$ROOT/work" "$ROOT/dist"
BUILD="$(mktemp -d "$ROOT/work/ps5-pad-build.XXXXXXXX")"
APP="$BUILD/Payload/PS5Pad.app"
mkdir -p "$APP"
cc -std=c11 -Wall -Wextra -Werror test_loader.c -o "$BUILD/test_loader"
"$BUILD/test_loader"
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
clang-18 -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fblocks -O2 -Wall -Wextra \
  -Werror -Wno-unused-parameter -c main.m -o "$BUILD/main.o"
clang-18 -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fblocks -O2 -Wall -Wextra \
  -Werror -Wno-unused-parameter -c QPConnection.m -o "$BUILD/QPConnection.o"
clang-18 -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fblocks -O2 -Wall -Wextra \
  -Werror -Wno-unused-parameter -c QPDiscovery.m -o "$BUILD/QPDiscovery.o"
clang-18 -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fblocks -O2 -Wall -Wextra \
  -Werror -Wno-unused-parameter -c QPLocalNetworkAccess.m -o "$BUILD/QPLocalNetworkAccess.o"
clang-18 -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fblocks -O2 -Wall -Wextra \
  -Werror -Wno-unused-parameter -c QPHelperLoader.m -o "$BUILD/QPHelperLoader.o"
ld64.lld-18 -arch arm64 -platform_version ios 15.0 16.5 -syslibroot "$SDK" \
  -o "$APP/PS5Pad" "$BUILD/main.o" "$BUILD/QPConnection.o" "$BUILD/QPDiscovery.o" "$BUILD/QPLocalNetworkAccess.o" "$BUILD/QPHelperLoader.o" \
  -lSystem -lobjc -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework Network \
  -headerpad 0x4000 -no_adhoc_codesign
cp Info.plist "$APP/Info.plist"
ELF="$ROOT/service/prebuilt/padd-controller-2.7.elf"
cp "$ELF" "$APP/padd-controller.elf"
VERSION="$(python3 -c 'import plistlib; print(plistlib.load(open("Info.plist","rb"))["CFBundleShortVersionString"])')"
OUTPUT="$ROOT/dist/PS5-Pad-$VERSION-unsigned.ipa"
python3 package.py "$APP" "$BUILD/PS5-Pad.ipa"
python3 verify_ipa.py "$BUILD/PS5-Pad.ipa" --elf "$ELF" --report "$BUILD/verification.json"
cp "$BUILD/PS5-Pad.ipa" "$OUTPUT"
cp "$BUILD/verification.json" "$ROOT/dist/PS5-Pad-$VERSION-verification.json"
python3 "$ROOT/tools/prepare_source.py" --ipa "$OUTPUT" --report "$ROOT/dist/PS5-Pad-$VERSION-verification.json"
printf 'Ready: %s\n' "$OUTPUT"
