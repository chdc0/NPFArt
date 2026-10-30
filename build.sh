#!/usr/bin/env bash
# Builds NowPlayingFullArt.dylib (fallback) and NowPlayingFullArt-always.dylib.
#
# Needs macOS with Xcode 26 or newer (iOS 26 SDK — the animated-artwork API).
# No Theos, no Orion, no Swift Package Manager. Just clang + swiftc.

set -euo pipefail
cd "$(dirname "$0")"

MIN_IOS="16.0"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "SDK:  $SDK"
echo "Xcode: $(xcodebuild -version 2>/dev/null | head -1)"

echo "checking for the iOS 26 animated-artwork API ..."
if ! echo 'import MediaPlayer
@available(iOS 26.0, *)
func _probe(_ v: MPMediaItemAnimatedArtwork) { _ = v }
func _probe2() { if #available(iOS 26.0, *) { _ = MPMediaItemAnimatedArtwork.self } }' \
    | xcrun --sdk iphoneos swiftc -target "arm64-apple-ios${MIN_IOS}" -sdk "$SDK" -typecheck - 2>/dev/null; then
    echo "FAILED: this SDK has no MPMediaItemAnimatedArtwork." >&2
    echo "        Install Xcode 26+ (iOS 26 SDK) and re-run." >&2
    exit 1
fi
echo "  ok"

mkdir -p build out

echo "compiling bootstrap.c ..."
xcrun --sdk iphoneos clang \
    -target "arm64-apple-ios${MIN_IOS}" \
    -isysroot "$SDK" \
    -O2 \
    -c Sources/bootstrap.c \
    -o build/bootstrap.o

build_variant() {
    local name="$1"
    shift
    echo "compiling $name ..."
    xcrun --sdk iphoneos swiftc \
        -target "arm64-apple-ios${MIN_IOS}" \
        -sdk "$SDK" \
        -swift-version 5 \
        -O \
        -wmo \
        -emit-library \
        -module-name NowPlayingFullArt \
        -install_name "@rpath/${name}.dylib" \
        -framework UIKit \
        -framework MediaPlayer \
        -framework AVFoundation \
        -framework CoreImage \
        "$@" \
        -o "out/${name}.dylib" \
        Sources/NowPlayingFullArt.swift \
        build/bootstrap.o

    local size
    size="$(stat -f%z "out/${name}.dylib")"
    echo "  out/${name}.dylib  ${size} bytes"

    # The symbol that proves we are actually using the iOS 26 API.
    if xcrun nm -u "out/${name}.dylib" | grep -q "MPMediaItemAnimatedArtwork"; then
        echo "  ok: links MPMediaItemAnimatedArtwork"
    else
        echo "  WARNING: no MPMediaItemAnimatedArtwork reference — the hook will no-op" >&2
    fi
}

# Default: only fills in when the player supplied no Canvas.
build_variant NowPlayingFullArt

# Always: replaces Spotify's own animated artwork too.
build_variant NowPlayingFullArt-always -D NPA_ALWAYS

echo
echo "done:"
ls -l out/*.dylib
