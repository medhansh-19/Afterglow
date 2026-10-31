# Afterglow

A native macOS music display with synchronized lyrics, album-colored glow and flowing audio-reactive visuals.

## Why I made this

I'm Medhansh, and I listen to a lot of music. My Spotify listening time easily reaches 10,000 minutes a month. That's probably not always a good thing, but I love my music.

Music is my hobby, and the lyrics are a huge part of it. I pay attention to what the artist is saying, how they say it, and that one line I end up replaying the whole song for. The beat gets me into a song; the words give me a reason to stay.

So Spotify's lyrics screen always felt a little boring to me. I wanted something that gave those words more presence. Music videos can be great, but sometimes I love a song and just don't like its video. Sometimes I just want to listen and let the lyrics do their thing.

Afterglow started as a lyrics app. Somewhere along the way, it became a live wallpaper for my Mac. Now the words, the album colors and the movement can live right on my desktop while the music plays. That evolution wasn't the original plan, but it feels right for a project I started because I wanted to use it myself.

## What it does

- Connect Spotify or Apple Music.
- View lyrics in a window, Focus Mode or as a desktop wallpaper.
- Match colors to album artwork and adjust lyric timing.
- Use LRCLIB, with optional Karalyr, NetEase and lyrics.ovh backups, or import your own lyrics.

## A lot of this started out loud

I use Wispr Flow a lot. Most of my longer prompts to Codex are spoken through it: the ideas, the explanations of what feels off, and the changes I want to try next.

When I have a picture in my head of how a lyric should feel on screen, I can talk through the whole thought while it's fresh. I don't have to shorten it because I'm tired of typing. Flow has become a regular part of how I build, and Afterglow is one of the things I've been building with it.

## Get started

Requires macOS 14+ and Swift 6 / Apple Command Line Tools.

```sh
swift run CoreChecks
zsh build.sh install
open /Applications/Afterglow.app
```

The installer requires `/Applications/Afterglow.app` to be absent. To build a ZIP without installing, run `zsh build.sh`; the result is `build/Afterglow.zip`. Builds are locally signed, not notarized.

Local builds reuse a private signing certificate stored in `~/Library/Application Support/Afterglow/Signing` so macOS permissions survive rebuilds. The first build creates a local keychain and trusts its certificate for code signing only; macOS may ask you to authenticate. Keep that folder private and preserve it across updates. Set `AFTERGLOW_SIGNING_IDENTITY` to use your own signing certificate instead.

When moving from an older ad hoc build, remove the old Afterglow entry from Screen & System Audio Recording, add `/Applications/Afterglow.app`, enable access, and reopen Afterglow once.

Start music, open Afterglow and connect your player. Grant Automation permission when prompted. Open controls with **⌘K**, toggle Focus with **⇧⌘F**, Desktop view with **⇧⌘D**, or Beat Sync with **⇧⌘B**. Global shortcuts can be disabled in Controls → Keyboard Shortcuts.

## Lyrics & privacy

Fallback sources run automatically. For small duration differences, Afterglow selects the closest compatible timed recording and labels it; timing may differ slightly. Synced coverage varies; lyrics.ovh provides untimed text only. Manage backups and imports in **Lyric library**. Track metadata goes to enabled lyric services; caches and preferences stay on your Mac.

Beat sync is optional and requires Screen & System Audio Recording permission. Selected-player audio is analyzed locally, without microphone capture, recordings or audio uploads.

[Development history](CHANGELOG.md) records the changes across releases.

## Rights

All rights reserved. No public permission to copy, modify or redistribute Afterglow is granted. See [LICENSE](LICENSE). Dependencies retain their [own licenses](THIRD_PARTY_NOTICES.md).

## Scenes and lyric cards

Open **Appearance & Wallpaper** from the Afterglow menu, choose your backdrop, glow, marker and visual preferences, then **Save Scene for This Song**. Saved scenes return automatically for that recording; songs without a scene use your default appearance. Use **Update Scene** to keep later changes or **Remove Scene** to return to defaults. Scenes and independent wallpaper copies stay on this Mac.

Open **Lyric Cards** from the menu (or **Create a Lyric Card** in the library). Select up to six lines and 280 characters, then save the excerpt, **Export PNG** or **Copy Image**. Cards use the song’s album accent, falling back to Rose when unavailable, and export at 1080 × 1350. Saved excerpts retain their original song and colors even after playback changes.
