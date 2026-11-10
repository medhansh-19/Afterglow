# Afterglow for Linux

A Linux development preview of Afterglow, alongside the native macOS app. **This branch is not a full-parity release.** Do not advertise it as one or replace the Mac download. See [PARITY.md](PARITY.md) for remaining desktop integrations and validation.

The interface uses Tauri/WebKitGTK with local HTML/Canvas/SVG. Rust connects to MPRIS, selected-player audio and desktop services. The lyric service is the same `AfterglowCore` Swift implementation used on macOS: recording matching, LRCLIB/Karalyr/NetEase/lyrics.ovh fallback, cache, LRC/enhanced LRC/YAML/plain-text imports.

## Build on Ubuntu 24.04

Install Swift 6.2.1, Rust stable and Node.js 22.12+, then:

```sh
sudo apt-get update
sudo apt-get install build-essential pkg-config libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev libgtk-layer-shell-dev libdbus-1-dev libssl-dev libcurl4-openssl-dev libxdo-dev patchelf pulseaudio-utils
bash linux/scripts/build-sidecar.sh
npm ci --prefix linux
npm run desktop --prefix linux
```

The build requires Linux; running the web preview on macOS does not test Linux integrations. `npm run dev --prefix linux` starts a browser preview with an explicitly silent demo. It does not connect to desktop players or capture audio.

For a reproducible container build:

```sh
docker build -f linux/Dockerfile -t afterglow-linux-dev .
docker run --rm -v "$PWD:/workspace" -v afterglow-swift-build:/workspace/.build -v afterglow-rust-build:/workspace/linux/src-tauri/target afterglow-linux-dev bash -lc 'bash linux/scripts/build-sidecar.sh && npm ci --prefix linux && npm run bundle --prefix linux'
```

Linux CI builds x86_64 packages. Artifacts are attached to the **Linux preview** workflow run, rather than linked to a nonexistent stable release. AppImage is a packaging format, not a promise of compatibility with older glibc distributions. This preview targets Ubuntu 24.04 or compatible newer systems; other distributions need testing.

## Install a preview package

Download the artifact from a successful Linux preview workflow run and extract its ZIP. On compatible Ubuntu systems, install the `.deb` with `sudo apt install ./Afterglow_0.1.0_amd64.deb` (use the ARM64 filename for ARM64 hardware). Apt installs the runtime dependencies. Launch Afterglow from the applications menu.

For AppImage, install `pulseaudio-utils` for beat sync and Noto core/color-emoji fonts for multilingual lyrics and custom emoji, make the file executable and run it. Systems without FUSE can use `APPIMAGE_EXTRACT_AND_RUN=1 ./Afterglow_0.1.0_amd64.AppImage`. These packages are development previews; use the feature checklist before relying on desktop integrations.

## Use

Start music in Spotify or another MPRIS-compatible player. In Controls → Player, choose the player. Playback metadata and timing are read locally; no Spotify account token is required. Apple Music web playback depends on the browser’s MPRIS implementation and is not equivalent to native Apple Music integration.

Controls include per-recording lyric timing, imports and alternative recordings, album/custom/collection colors, marker/emoji/word progression, wallpaper copies, seven clock styles, song scenes, collections and saved excerpts. Cards export at 1080 × 1350; map export freezes the current graph. Data saves atomically under the platform app-data directory, typically `~/.local/share/local.medhansh.afterglow.linux/library.json`; the shared lyric cache uses Foundation’s user cache directory. Invalid libraries are preserved and writes are disabled for that session.

Beat Sync asks you to select an active audio stream. It uses `pactl` and `parec` through PipeWire-Pulse or PulseAudio, **monitoring only that stream**. Choose a new stream if your player reconnects or switches output devices. A browser can combine several tabs in one audio stream. Capture stops while playback is paused, the app is hidden, or the system sleeps. No microphone, recording files or audio uploads are used.

Ctrl+K opens controls; Ctrl+Shift+F/D/B/A/M opens Focus/Desktop/Beat Sync/Appearance/Capture. Controls → Help can request global shortcuts through the desktop portal. When the portal is unavailable, desktop keyboard settings can launch `afterglow-linux --action focus|desktop|beats|appearance|capture`; the single-instance handler forwards the action to the running app. These are argument values, not a shell pipeline.

Desktop mode creates a separate display-only wallpaper view, sharing the same playback and capture owner. The tray menu restores the normal window. X11 uses a desktop-type, click-through window. Compatible Wayland desktops use GTK Layer Shell; GNOME Wayland needs a separate integration. Unsupported integrations return a visible error. Wallpaper behavior is not yet certified across desktops or multiple displays.

## Verification

```sh
swift run CoreChecks
python3 linux/tests/service.py
npm test --prefix linux
npm run build --prefix linux
# Requires a Linux session bus and python3-dbus/python3-gi:
dbus-run-session -- bash linux/tests/mpris.sh
# Requires a running Vite preview and Python Playwright:
python3 linux/tests/ui.py
# After npm run bundle, with xvfb/openbox/xdotool/x11-utils installed:
xvfb-run -a -s '-screen 0 1440x900x24' dbus-run-session -- bash linux/tests/native-smoke.sh linux/src-tauri/target/release/afterglow-linux
```

Run the exported packages on a clean machine without Swift installed before release. Linux CI records package and native-window results. Browser tests cover UI behavior but cannot establish WebKitGTK rendering, real player compatibility, audio isolation, portal approval or compositor behavior.

## In-app updates (0.2.0 onward)

The tray menu includes **Check for Updates…** and a persistent **Automatically Check for Updates** setting. Checks run after 30 seconds and every six hours. Downloads require consent and signed-version verification, followed by an **Install and restart** prompt. AppImages replace their own file (keep it in a writable location). Debian packages install using the platform updater's authorization flow; your desktop may ask for administrator authentication. Never run the app itself as root. Settings stay in the existing application data directory.

The feed chooses the installed format: a Debian app receives a `.deb`, and an AppImage receives an AppImage. Raw binaries and unimplemented distribution formats have no generic update fallback. Earlier previews require one manual upgrade. See `docs/UPDATES.md` for release and acceptance procedures.
