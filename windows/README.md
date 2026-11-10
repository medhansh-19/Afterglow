# Afterglow for Windows

A Windows 11 x64 development preview built from the same local Tauri interface as the Linux port and the same Swift lyric engine as macOS. The native Mac app remains separate. See [the feature audit](PARITY.md) and [validation evidence](VALIDATION.md) for what has been implemented and what still needs testing.

## Install

Download the Windows 0.1.1 setup executable from [GitHub Releases](https://github.com/medhansh-19/Afterglow/releases). Run it to install or update the existing preview; local preferences are preserved. Build artifacts are also available from the **Windows preview** workflow. The installer bundles the lyric helper and its Swift runtime; users do not need to install Swift, Rust, Node.js or Python. WebView2 is required and the installer can bootstrap Microsoft's runtime when it is missing.

This preview is unsigned and has no automatic updater. Users of earlier downloads must install the new setup executable manually; publishing a release cannot update an already installed copy. Keep the installer and its SHA256 checksum together. Use Windows Settings → Apps to uninstall it. App data is kept separately from the install directory.

## Connect music

Start a song in Spotify, Apple Music for Windows, or a player that publishes a Windows media session. Open Afterglow → Controls → Player and choose it. Availability of playback position, seeking and transport actions depends on what the player exposes to Windows. The app reads player metadata locally; no Spotify account token or Apple Music credentials are requested.

Use Controls for lyric imports, recording alternatives, timing adjustment, appearance, saved colors, clocks, song scenes, collections, lyric cards and beat sync. Plain-text lyrics remain in the lyric library; the main display uses timed lyrics. The silent demo is available without connecting a player.

Beat sync uses Windows process loopback, capturing only the chosen process tree. Select the player's audio process explicitly: Windows media-session identities are not process IDs. A browser process tree can include several tabs. Capture continues while Controls and its live preview are open. Switching audio streams stops the previous capture before starting the selected stream. Capture stops when playback pauses, the window is hidden without a visible wallpaper, or Windows sleeps. Audio is analyzed locally, without microphone capture, audio files or uploads. DRM-protected playback or a player that does not expose an audio session may be unavailable or silent.

Desktop mode creates a separate, click-through view behind Explorer's desktop icons. The system tray restores the main window and offers Quit. Explorer restarts, multiple monitors, scaling and third-party desktop shells need hardware validation; see the feature audit.

Local shortcuts use Ctrl+K for Controls and Ctrl+Shift+F/D/B/A/M for Focus, Desktop, Beat sync, Appearance and lyric-map capture. Enable global shortcuts in Controls → Help. A conflicting binding produces an error. Lyric cards and frozen maps can be saved as PNG or copied as images. The Mac screenshot companion and native share sheet are not currently reproduced; use the explicit capture and export actions.

## Data and privacy

Collections, scenes, imported lyrics, saved colors and private wallpaper copies are stored in `library.json` under the platform app-data directory for `local.medhansh.afterglow.windows`. The shared lyric cache is stored separately in Foundation's user-cache directory. Invalid saved libraries are preserved and file writes are disabled for that session; temporary interface changes are not saved. Updates replace a library atomically.

The selected song's metadata is sent to enabled lyric providers. Lyric services, album artwork and player brands remain subject to their owners' terms. The lyric service and artwork loader run locally; beat audio is never sent to a provider.

## Build on Windows

Install the [Swift 6.2.1 toolchain and its Windows prerequisites](https://www.swift.org/install/windows/manual/), Visual Studio 2022 C++ build tools with a Windows SDK, Rust stable with the `x86_64-pc-windows-msvc` target, Node.js 22.12+, Python 3 and WebView2. Enable Developer Mode for Swift Package Manager as described in the [Swift installation instructions](https://www.swift.org/install/windows/winget/).

From the repository root in PowerShell:

```powershell
swift run CoreChecks
./windows/scripts/build-sidecar.ps1
npm ci --prefix linux
npm test --prefix linux
node --test windows/tests/*.test.js
npm run build --prefix linux
python linux/scripts/collect-notices.py
Set-Location linux
npm run tauri -- build --config ../windows/tauri.windows.conf.json
```

The `linux/` directory contains the shared desktop frontend and Rust shell for both ports; the Windows config selects its native adapters and Windows installer. The setup executable is written under `linux/src-tauri/target/release/bundle/nsis/`. Development also needs the built sidecar:

```powershell
Set-Location linux
npm run tauri -- dev --config ../windows/tauri.windows.conf.json
```

Browser preview and macOS checks exercise portable logic only. Windows CI compiles the native adapters, runs Windows tests and packages the app. Real Spotify/Apple Music, capture isolation, Explorer recovery, sleep/wake and hardware power behavior remain separate acceptance tests. See [PLAN.md](PLAN.md) for architecture and official API sources.

## Signed in-app updates (0.2.0 onward)

Windows checks after 30 seconds and every six hours. The tray menu offers **Check for Updates…** and a persistent **Automatically Check for Updates** preference. Download and installation each require consent. Downloads are cryptographically verified; background network failures do not interrupt listening. Failed user-initiated downloads show a retry instruction. Declining installation discards the downloaded bytes; a manual check can download again. Settings and the application identifier remain unchanged.

Existing 0.1.0 previews need one manual upgrade. macOS and Linux now have their own signed update channels. See `docs/UPDATES.md` for the cross-platform release procedure.

Release steps:
1. Increase `windows/tauri.windows.conf.json` version. Keep the updater public key unchanged. CI uses repository secret `TAURI_SIGNING_PRIVATE_KEY` (not an Authenticode certificate).
2. Run Windows preview CI on the release commit. Require native tests, install smoke test and signed `.exe.sig` output.
3. Run **Stage signed desktop update** (select Windows) with that successful run ID and an immutable `windows-vX.Y.Z` tag. It produces a draft containing the installer, signature and `windows-latest.json`.
4. On a real Windows machine, test an older updater-enabled build against the candidate manifest: accept download, verify installation/relaunch and settings; also test decline, offline and a corrupted signed artifact. Never promote a failed candidate.
5. Publish the versioned release. Create a public GitHub release tagged `windows-updates` once, then upload the tested `windows-latest.json` to that channel release with `gh release upload windows-updates windows-latest.json --clobber`. Keep the installer at its immutable versioned URL. The feed is Windows-only and unrelated releases do not affect it.

Before the first feed is promoted, automatic checks quietly retry; manual checks report that the service could not be reached. Keep a secure backup of the signing key. Losing it requires a manual upgrade to trust a new key. Authenticode signing and SmartScreen reputation remain a separate Windows distribution concern.
