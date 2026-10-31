#!/bin/zsh
# A persistent private signing identity keeps macOS permission grants valid across local updates.
set -euo pipefail
app="$1"
entitlements="$2"
if [[ -n "${AFTERGLOW_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --sign "$AFTERGLOW_SIGNING_IDENTITY" --entitlements "$entitlements" "$app"
    exit
fi
signing_dir="$HOME/Library/Application Support/Afterglow/Signing"
keychain="$signing_dir/local-signing.keychain-db"
identity='Afterglow Local Development'
umask 077
mkdir -p "$signing_dir"
if [[ ! -f "$keychain" ]]; then
    staging="$(mktemp -d "${TMPDIR:-/tmp}/afterglow-signing.XXXXXX")"
    initialized=false
    trap 'rm -rf "$staging"; if [[ "$initialized" != true ]]; then security delete-keychain "$keychain" 2>/dev/null || true; fi' EXIT
    openssl rand -hex 32 > "$signing_dir/password"
    password="$(cat "$signing_dir/password")"
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
        -subj "/CN=$identity/" -keyout "$staging/key.pem" -out "$staging/cert.pem" \
        -addext 'keyUsage=critical,digitalSignature' -addext 'extendedKeyUsage=codeSigning' 2>/dev/null
    openssl pkcs12 -export -inkey "$staging/key.pem" -in "$staging/cert.pem" \
        -out "$staging/identity.p12" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
        -macalg sha1 -passout "pass:$password"
    security create-keychain -p "$password" "$keychain"
    security set-keychain-settings "$keychain"
    security unlock-keychain -p "$password" "$keychain"
    security import "$staging/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
    # Trust is limited to code signing; this certificate is not a web/TLS root.
    security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$staging/cert.pem"
    initialized=true
fi
# codesign identity discovery also requires membership in the user's search list.
keychains=()
while IFS= read -r line; do
    line="${line#*\"}"
    line="${line%\"*}"
    keychains+=("$line")
done < <(security list-keychains -d user)
if (( ${keychains[(Ie)$keychain]} == 0 )); then
    security list-keychains -d user -s "${keychains[@]}" "$keychain"
fi
password="$(cat "$signing_dir/password")"
security unlock-keychain -p "$password" "$keychain"
fingerprint="$(security find-certificate -c "$identity" -Z "$keychain" | awk '/SHA-1 hash:/ {print $3; exit}')"
# Select the certificate by hash, including self-signed local identities.
codesign --force --options runtime --keychain "$keychain" --sign "$fingerprint" \
    --entitlements "$entitlements" "$app"
