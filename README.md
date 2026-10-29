# Afterglow

A native macOS music display with synchronized lyrics, album-colored glow and flowing audio-reactive visuals.

- Connect Spotify or Apple Music.
- View lyrics in a window, Focus Mode or as a desktop wallpaper.
- Match colors to album artwork and adjust lyric timing.
- Use LRCLIB, with optional Karalyr and lyrics.ovh backups, or import your own lyrics.

## Get started

Requires macOS 14+ and Swift 6 / Apple Command Line Tools.

```sh
swift run CoreChecks
zsh build.sh install
open /Applications/Afterglow.app
```

The installer requires `/Applications/Afterglow.app` to be absent. To build a ZIP without installing, run `zsh build.sh`; the result is `build/Afterglow.zip`. Builds are locally signed, not notarized.

Start music, open Afterglow and connect your player. Grant Automation permission when prompted. Open controls with **⌘K**, toggle Focus with **⇧⌘F**, or choose Desktop Mode from the Display menu.

## Lyrics & privacy

Synced coverage varies by recording; lyrics.ovh provides untimed text only. Manage backups and imports in **Lyric library**. Track metadata goes to enabled lyric services; caches and preferences stay on your Mac.

Beat sync is optional and requires Screen & System Audio Recording permission. Selected-player audio is analyzed locally, without microphone capture, recordings or audio uploads.

[Development history](CHANGELOG.md) records the changes across releases.

## Rights

All rights reserved. No public permission to copy, modify or redistribute Afterglow is granted. See [LICENSE](LICENSE). Dependencies retain their [own licenses](THIRD_PARTY_NOTICES.md).
