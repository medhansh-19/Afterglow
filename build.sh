#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
# Release builds may contain both supported Mac architectures.
if [[ "${AFTERGLOW_UNIVERSAL:-0}" == 1 ]]; then
    swift build -c release --product Afterglow --arch arm64
    swift build -c release --product Afterglow --arch x86_64
else
    swift build -c release --product Afterglow
fi
stage="$(mktemp -d "${TMPDIR:-/tmp}/afterglow-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Afterglow.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ "${AFTERGLOW_UNIVERSAL:-0}" == 1 ]]; then
    arm_bin="$(swift build -c release --arch arm64 --show-bin-path)"
    intel_bin="$(swift build -c release --arch x86_64 --show-bin-path)"
    lipo -create "$arm_bin/Afterglow" "$intel_bin/Afterglow" -output "$app/Contents/MacOS/Afterglow"
else
    cp .build/release/Afterglow "$app/Contents/MacOS/Afterglow"
fi
framework="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$framework" ]] || { echo 'Sparkle framework is missing.' >&2; exit 1; }
mkdir -p "$app/Contents/Frameworks"
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp .build/checkouts/Yams/LICENSE "$app/Contents/Resources/Yams-LICENSE.txt"
cp .build/checkouts/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt"
if [[ -f Resources/Afterglow.icns ]]; then
    cp Resources/Afterglow.icns "$app/Contents/Resources/Afterglow.icns"
fi
zsh tools/sign-local.sh "$app" Resources/Afterglow.entitlements
codesign --verify --deep --strict --verbose=2 "$app"
mkdir -p build
ditto -c -k --norsrc --keepParent "$app" "$PWD/build/Afterglow.zip"
echo "Built: $PWD/build/Afterglow.zip"
if [[ "${1:-}" == "install" ]]; then
    if [[ -e /Applications/Afterglow.app ]]; then
        echo 'An installation already exists. Close it and move it aside before installing this build.' >&2
        exit 1
    fi
    ditto "$app" /Applications/Afterglow.app
    codesign --verify --deep --strict /Applications/Afterglow.app
    echo 'Installed /Applications/Afterglow.app'
fi
