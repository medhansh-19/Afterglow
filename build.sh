#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release --product Afterglow
stage="$(mktemp -d "${TMPDIR:-/tmp}/afterglow-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Afterglow.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Afterglow "$app/Contents/MacOS/Afterglow"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp .build/checkouts/Yams/LICENSE "$app/Contents/Resources/Yams-LICENSE.txt"
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
