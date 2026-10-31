#!/bin/zsh
# Check that a content-changing update preserves the app's certificate-bound identity.
set -euo pipefail
cd "${0:A:h}/.."
stage="$(mktemp -d "${TMPDIR:-/tmp}/afterglow-signing-check.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
unzip -q "${1:-build/Afterglow.zip}" -d "$stage"
app="$stage/Afterglow.app"
before="$(codesign -d -r- "$app" 2>/dev/null)"
[[ "$before" == *'certificate leaf'* ]] || { echo 'FAIL: certificate-bound identity required'; exit 1; }
hash_before="$(codesign -d --verbose=3 "$app" 2>&1 | awk -F= '/^CDHash=/ {print $2}')"
echo 'Content changed for signing regression check' > "$app/Contents/Resources/signing-check.txt"
zsh tools/sign-local.sh "$app" Resources/Afterglow.entitlements
after="$(codesign -d -r- "$app" 2>/dev/null)"
hash_after="$(codesign -d --verbose=3 "$app" 2>&1 | awk -F= '/^CDHash=/ {print $2}')"
[[ "$before" == "$after" ]] || { echo 'FAIL: signing identity changed'; exit 1; }
[[ "$hash_before" != "$hash_after" ]] || { echo 'FAIL: test did not change code hash'; exit 1; }
codesign --verify --deep --strict "$app"
echo 'PASS: different code hashes retain the same certificate-bound identity'
