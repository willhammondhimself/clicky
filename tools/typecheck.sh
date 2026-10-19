#!/bin/sh
#
# Typechecks the app sources from the terminal without building an app
# bundle (building with xcodebuild from the terminal resets the app's TCC
# permissions, so it is never used here). Mirrors the app target's settings:
# macOS 14.2 target, main-actor default isolation, and MemberImportVisibility
# (each file must import the module that defines what it uses; without it this
# script passed files Xcode rejects).
#
# Sources that import FluidAudio need the module Xcode compiled, so run
# Cmd+B in Xcode at least once; the script finds it in DerivedData.
#
# Usage: tools/typecheck.sh            (prints "0 errors" on success)

set -eu

cd "$(dirname "$0")/.."

derived_data_dir="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/leanring-buddy-* 2>/dev/null | head -1 || true)"
module_flags=""
if [ -n "$derived_data_dir" ] && [ -d "$derived_data_dir/Build/Products/Debug/FluidAudio.swiftmodule" ]; then
    checkouts="$derived_data_dir/SourcePackages/checkouts/FluidAudio/Sources"
    nemo_headers="$derived_data_dir/SourcePackages/artifacts/fluidaudio/NemoTextProcessing/NemoTextProcessing.xcframework/macos-arm64_x86_64/Headers"
    module_flags="-I $derived_data_dir/Build/Products/Debug \
        -Xcc -I$checkouts/FastClusterWrapper/include \
        -Xcc -I$checkouts/MachTaskSelfWrapper/include \
        -Xcc -I$nemo_headers \
        -Xcc -I$nemo_headers/CNemoTextProcessing"
else
    echo "note: FluidAudio module not found in DerivedData; build once in Xcode (Cmd+B) to typecheck files that import it" >&2
fi

# shellcheck disable=SC2086
output="$(xcrun swiftc -typecheck \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -target arm64-apple-macos14.2 \
    -parse-as-library \
    -default-isolation MainActor \
    -enable-upcoming-feature MemberImportVisibility \
    $module_flags \
    leanring-buddy/*.swift 2>&1 || true)"

error_count="$(printf '%s\n' "$output" | grep -c 'error:' || true)"
if [ "$error_count" -gt 0 ]; then
    printf '%s\n' "$output" | grep -B1 -A3 'error:'
    echo "typecheck: $error_count errors"
    exit 1
fi
echo "typecheck: 0 errors"
