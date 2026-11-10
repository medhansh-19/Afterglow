# Signed desktop updates

All supported desktop apps expose **Check for Updates…** and **Automatically Check for Updates**. Installation preserves the existing application identifiers and data directories. Music playback belongs to the connected player and continues while Afterglow restarts.

## Platform behavior

- **macOS:** Sparkle owns scheduling, download/install UI, skipped versions, preferences and relaunch. Checks default to every six hours. Automatic installation is off by default; the native update dialog offers the supported choices. The packaged app includes Sparkle, its installer XPC helper, matching sandbox entitlements and an executable-relative framework search path. Both archive and appcast signatures are mandatory. `swift run` does not start the updater because it has no app bundle.
- **Windows:** Checks begin after 30 seconds, then every six hours. Native dialogs offer download, then install/restart. NSIS manages replacement and relaunch. The existing version-bound signature check remains enabled.
- **Linux:** The same flow selects `linux-x86_64-deb` or `linux-x86_64-appimage` according to the installed package. Debian upgrades use the official updater's privilege authorization flow (usually a desktop authentication dialog). AppImages need a writable destination. After a successful update the app restarts. There is deliberately no `linux-x86_64` catch-all that could send one package type to another.

Windows/Linux suppress duplicate automatic prompts per version until restart, serialize operations, and keep background check failures quiet. Explicit check/download failures show retry instructions. Checks time out after 30 seconds; large installer downloads have 30 minutes. Declining installation currently discards the downloaded bytes.

## Signing and build setup

- `TAURI_SIGNING_PRIVATE_KEY`: existing Tauri private key for Windows and Linux; empty password. Public key is embedded in each config. The official bundler creates signatures tied to the version.
- `MACOS_SPARKLE_PRIVATE_KEY`: separate base64 Ed25519 private seed accepted by Sparkle 2.10.1. The corresponding public key is embedded as `SUPublicEDKey`. `tools/macos-appcast.py` supplies the key through standard input to Sparkle's official signing tool, verifies the archive against the packaged public key, and signs/verifies the appcast itself.
- Local key backups are outside the repo under `~/Library/Application Support/Afterglow/Updates/`. Never commit them. Preserve both signing keys across releases; key loss requires an explicit manual trust migration.
- Mac candidates: `AFTERGLOW_SIGNING_IDENTITY=- AFTERGLOW_UNIVERSAL=1 zsh build.sh`. These are development signatures and are **not notarized**. For a configured distribution identity, set `AFTERGLOW_SIGNING_IDENTITY` to it; the existing signing script uses Hardened Runtime and signs nested components with that identity. Preserve symlinks and execute bits when packaging Sparkle. Production notarization/stapling remains an additional distribution step before generating the final signed archive and feed; never change an archive after signing it for updates.
- `AFTERGLOW_UNIVERSAL=1` builds arm64 and x86_64 independently and combines them. Windows and Linux currently target x86_64. Core Swift targets on those systems do not resolve Sparkle's macOS binary artifact.

## Stage a release

1. Increase the actual app version: Mac `Resources/Info.plist` short version **and** monotonically increasing build number; Windows `windows/tauri.windows.conf.json`; Linux `linux/src-tauri/tauri.conf.json`. Never change an app identifier to release an update.
2. Run the matching CI workflow on the release commit. Require native tests, signing/packaging and installed/packaged launch checks. Mac CI creates a universal development candidate; Windows/Linux create signed native installers and `.sig` files.
3. Merge the staging workflow into the default branch before its first manual dispatch. Run **Stage signed desktop update** with platform, successful run ID and an immutable version tag (for example `macos-v3.0.8`, `linux-v0.2.1` or `windows-v0.2.1`). It rejects a run with the wrong workflow, commit or result and creates a **draft** release. Mac staging signs `appcast.xml`; Linux staging requires both package types and signatures; Windows staging requires its installer and signature.
4. Accept the exact candidate on the target OS: old-to-new upgrade, consent/decline, current version, offline retry, invalid signature, settings/library retention and restart. Mac additionally needs Gatekeeper/sandbox helper testing; Debian needs authentication and cancellation testing; AppImage needs writable/read-only location testing. Do not promote a failed candidate. Existing 0.1.0 Windows/Linux or pre-3.0.8 Mac builds require one manual bootstrap install.
5. Publish the immutable release, then upload its tested metadata to the appropriate persistent channel release. Create each public channel release once, then replace only its feed asset:
   - `macos-updates`: `appcast.xml`
   - `windows-updates`: `windows-latest.json`
   - `linux-updates`: `linux-latest.json`

Feed asset URLs point to immutable versioned release assets. Publishing an unrelated platform release does not advance the others. Keep Mac feeds byte-identical after signing; modifying XML or a ZIP invalidates its signature. Tauri rejects equal/older versions, signature failures and package-format mismatches.

## Validation scope

Automated checks cover native compilation, manifest boundaries, signatures, packaging, nested code signatures, loader paths, both Mac architectures and packaged app launch. Full old-to-new UI/authorization acceptance remains a rollout requirement; a successful build alone does not prove every OS authorization interaction. The public channels remain inactive until explicitly promoted. No existing installed app is modified by this code change.
