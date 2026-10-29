# Development history

Afterglow's evolution, in release order. These notes describe behavior at the time of each release; later entries may replace earlier designs, defaults or limitations. See the [README](README.md) for the current overview.

## V2.0 — Color and instrumental shapes

**Album cover** is the default Glow color mode. Spotify supplies its cover URL and Afterglow downloads artwork only from Spotify’s HTTPS image CDNs. Apple Music supplies embedded artwork through its existing Automation permission. A 64×64 thumbnail is sampled locally; a population-weighted palette keeps dominant hues and mostly neutral covers neutral, then lifts dark accents for readable contrast. The accent colors the border, lyric words, connecting lines, anchors, progress and song title. It is derived from the actual current recording’s artwork, not hardcoded song-name mappings. Missing artwork falls back to Rose; the settings menu states when that happens. Palette results stay in a bounded memory cache.

Empty lyric intervals (including intros and explicit line-end gaps) now show a larger crossing polygon/star and waveform ring. Ambient motion works immediately, with no new permissions. Five detected onsets build a five-point star; later onsets evolve the geometry. Intersections are intentional for instrumental and lyric connections; word labels retain separate layout cells.

Choose the waveform-circle button or **Display settings → Beat sync… → Enable beat sync** for actual audio response. This is opt-in each session and requires macOS Screen & System Audio Recording approval. ScreenCaptureKit is filtered to the connected Spotify/Apple Music process; Afterglow registers only an audio output. It does not register screen-frame or microphone outputs, write audio/video files, or upload audio. The native permission and menu-bar indicator may still mention screen capture because that is the system API’s permission category. Disabling sync, disconnecting/changing players, closing the display or sleeping stops the stream. Re-enable after reconnecting. macOS may require reopening the app after a new grant.

The detector follows RMS energy and approximate bass/energy onsets, not a perfect tempo model. Quiet audio, sustained notes, compression and busy mixes affect onset counts. Without permission, the visual is ambient and the Beat sync popover says so; it is never advertised as measured beat tracking. Reduce Motion freezes geometric motion and energy-driven frame modulation.

The real secure macOS lock screen is not a supported display surface. Use full-screen mode while unlocked; the app does not alter loginwindow or system security.

### Accurate timing

Afterglow first reads LRCLIB's Lyricsfile data, including real individual-word timestamps when provided. It validates chronological order, text correspondence, and start/end bounds before using them. If only line timestamps exist, the entire current lyric line is highlighted. The Timing popover identifies the timing source; no word timings are invented by default. Older LRC-only responses remain supported. Community timestamps can still be inaccurate.

**Timing** opens a per-recording correction from −5 to +5 seconds in 0.05-second steps. Use **Earlier** if lyrics trail the vocals, **Later** if lyrics lead. The correction affects lyrics only, not music playback or the progress bar. **Reset timing** returns to the original timestamps. These corrections cannot repair differences in timing between individual words.

**Estimate missing word timings** is an optional artistic effect, disabled by default. It is not exact karaoke timing. Real word timestamps take precedence even when estimates are enabled. The silent demo uses synthetic timings for its original sample text.

Playback uses a monotonic clock, query-latency compensation, small-drift smoothing and 0.4-second player sampling. Pause/resume and seeks reset the clock as appropriate; crossing a lyric-line boundary no longer waits for a half-second crossfade. Word emphasis transitions take 0.08 seconds, and Reduce Motion disables them.

Missing, instrumental, offline and unsynced songs have explicit states; use **Try lyrics again** to retry. Some recordings have mismatched metadata or unavailable lyrics. The display does not run above the actual macOS lock screen.

## V2.1

Instrumental passages now draw a triangle, pentagon, crossing star, hexagon or crossing seven-point path edge by edge, with a moving light at the tip. Live onsets advance the pen; ambient mode draws continuously. Completed routes hold and fade instead of erupting or switching at a beat.

Open **Lyric library** from the book icon or settings. LRCLIB lookup now retries without album-edition metadata and searches for the same title, artist and recording duration (within two seconds). Results are cached in memory for 30 minutes. The optional open-source [lyrics.ovh](https://github.com/NTag/lyrics.ovh) API adds **untimed text** in the library reader. Only title and artist go to that fallback. Disable it in the library sheet if desired. Timed coverage is still dependent on LRCLIB; no service guarantees every song.

You can import your own UTF-8 standard LRC, Lyricsfile YAML with real word timestamps, or plain `.txt` for the selected recording. Imports stay inside Afterglow's sandbox. “Use online lyrics” archives the local override for recovery. Source files remain unchanged. Maximum import size is 500 KB. Enhanced angle-tag LRC is not a supported import format; use standard line LRC or Lyricsfile for word timings.

## V2.2 — more usable timed matches, fewer repeated requests

Search now continues when LRCLIB's exact lookup fails. Exact lookup has a three-second limit so a slow external lookup cannot stall the whole chain indefinitely. Shared connections and a bounded local cache improve repeat lookups: timed results survive launches for 30 days, untimed results refresh after ten minutes, and clean misses pause repeated requests for five minutes. Retry always refreshes online data. Cache is inside the app sandbox, capped at 64 entries/10 MB.

When durations differ, **Review timed versions** opens up to six distinct same-title/artist versions with album, length, difference from your recording, and lyric preview. Choose one explicitly to save its timing for this recording; “Use online lyrics” archives that choice. Manual matches are labeled and may drift. During the first check of The Fate of Ophelia (3:40), search listed versions beginning at 3:46. After installing the update, the exact recording retrieved synchronized lyrics successfully; alternate timings are only offered for review when exact timing is unavailable. No new provider is enabled in this update: tested Karalyr endpoints had no match for the sample tracks.

## V2.3 — colored spectrum and flowing ribbons

Replaces triangle/star/polygon graphics and lyric connecting chords with a spectrum inspired by the supplied reference: colored frequency bars, soft reflections and flowing wave ribbons. A subdued version remains behind the words during lyrics. Text and frame retain the album accent. Animation state survives lyric changes; pause freezes it and Reduce Motion renders a static scene.

Live bars use a 2048-sample Hann-windowed FFT and 32 logarithmic frequency bands, with attack/release smoothing and a stale-audio fade. Ambient motion remains available when capture is off. These are distinct modes: a decorative wave is not called synchronized audio. Lyric highlighting still follows the player's timeline and available provider timestamps; audio visualization does not fabricate word timestamps. Capture remains selected-player audio only, with no microphone, recordings or uploads.

## V2.3.1 — lyric graph restored

Per the corrected direction, the original lyric constellation and its glowing connecting graph are restored. Colored bars/ribbons appear only during gaps in the timed lyric timeline or tracks explicitly marked instrumental; they never sit behind sung words. A missing lyric result is not treated as proof of an instrumental passage. Live audio capture still depends on macOS permission and has not been claimed fixed by this layout correction.

## V2.4 — livelier instrumental motion

Taller moving peaks, thirteen deeper ribbon curves, five traveling light trails, floating spectrum peak markers and stronger reflected glow replace the previous shallow visualizer. Live audio onset adds a short pulse to motion speed/glow; ambient mode has a more visible traveling pattern. Lyric words and the connecting graph remain unchanged, and the visualizer still appears only in timed instrumental gaps or explicitly instrumental tracks. Pause freezes every moving element; Reduce Motion removes traveling highlights.

## V2.5 — tonal curves only

Instrumental visuals now follow the album/frame color in lighter and darker tones. Vertical bars, floating caps and rainbow gradients have been removed. Seventeen wider, taller flowing curves use live frequency/energy data, with smooth bounded crests and same-color light trails. The lyric constellation stays unchanged. Grey album accents yield shades of grey; other album hues remain in that hue family. Pausing freezes motion, and Reduce Motion renders shallow static curves.

## V2.5.1 — jitter and transition fixes

Removed the periodic curve-phase wrap that caused layered waves to jump. Curves now share a persistent clock across lyric changes, with smoother audio envelopes, up to 60 fps scheduling, and edge-faded light trails. Tiny lyric timing gaps under 0.7 seconds no longer flash the instrumental visualizer. Longer gaps use a short wave-only fade that completes at the next vocal timestamp; lyric timing is not delayed. Seeking and pausing resolve without retaining an outdated scene. The monochrome album palette and lyric graph remain intact.

## V2.6 — broader recording searches

Lookup now searches album-specific results before broader full-title and normalized-title results, so compilation entries cannot crowd the correct recording out of a capped search response. It tries both the full collaboration title and a version with parenthetical feat/with credits removed. Combined artist credits match only when the extra collaborators are explicitly named in your track metadata; unrelated artists and different title versions still fail. Automatic timestamps still require a duration within two seconds. Search variants continue through individual service failures, with no further same-service requests after a rate limit.

Existing successful timed cache entries remain available offline. Old untimed decisions are rechecked once under the improved matcher. Lookup is bounded to two exact queries and three deduplicated searches; no new provider or data recipient is added. Recordings with larger duration differences remain in the explicit version-review flow.

## V2.6.1 — waves across the display

Instrumental curves now span the full window width, including full screen, instead of stopping at the narrower lyric graph container. The lyric graph and controls keep their existing layout. Curve ends stay visible at both edges within the same album color.

## V2.7 — larger lyric map and subtle moving frame

The lyric graph uses more width and height with larger words and less top/side padding. “afterglow” follows the album color. The border is dimmer, with a small same-color highlight traveling around it and a restrained, smoothed response to live beats. Pause freezes the highlight; Reduce Motion and the motion toggle keep the frame static. Existing tonal instrumental curves, lyric timing and provider matching are unchanged.

## V2.7.1 — prevent stale lyrics across long instrumental breaks

Some timed providers stretch a short line until the next timestamp, even when that timestamp is minutes away. Afterglow now limits these sparse line-only holds longer than 30 seconds to an estimated 8–16-second display, then shows the beat curves. Musical-note-only entries and explicit instrumental markers also become instrumental scenes. Ordinary sustained lyrics and real word timings are preserved. This fallback prevents old text looking frozen; it does not detect vocals from audio or recover missing lyric timestamps.

## V2.8 — compact controls

The playback bar now stays hidden behind a small bottom-left controls button. Click it or press Command-K to open; click away, press Escape, or choose Hide playback controls to close. Track information stays centered and the lyric layout does not jump. Timing and Beat sync open within that same popover. There is no idle countdown that could close controls during a keyboard interaction.

## V2.9 — Desktop Mode

Choose **Display → Desktop Mode** (Option-Command-W while Afterglow is active), or use the **Desktop Mode** button in the compact playback controls. The existing display becomes a borderless live wallpaper on its current monitor, behind desktop icons and app windows. Desktop clicks pass through. The clock follows your existing Show clock preference; controls and the wordmark stay hidden, and paused lyrics fade to a quiet background. Songs without synced lyrics show ambient or audio-driven waves instead of library buttons.

The waveform icon in the macOS menu bar provides playback, player selection, glow color, clock, motion, beat sync, **Return to Window Mode**, and Quit. Returning restores the window's previous position and size. Afterglow must remain running; quitting reveals the system wallpaper. The wallpaper appears across desktop Spaces on the selected monitor; it does not duplicate onto every monitor. Display Mode is selected per session, and launch still begins in the normal window so you can connect a player. Full-screen mode exits before switching to Desktop Mode.

## V2.10 — Focus Mode and lyric alignment

Choose **Focus Mode — Hide Widgets & Stage Manager** from the waveform menu-bar icon, the Display menu, the header's viewfinder button, or the compact playback controls. Shift-Command-F toggles it while Afterglow is active. Focus Mode opens a clean native full-screen Space, keeping desktop widgets and Stage Manager thumbnails outside the listening view. Press Escape or click **Exit Focus** to return; if you started from Desktop Mode, the wallpaper returns automatically. It does not change your system widget or Stage Manager preferences.

The lyric constellation now has a centred maximum width and more room at the display edges. Lines connect to the diamonds beneath each word; labels use fixed anchors and consistent bottom alignment, with column-sized widths to keep long words out of adjacent columns. Instrumental waves still span the full display.

## V2.11 — Focus from any app

**Shift-Command-F now controls Afterglow globally while it is running**, including when Finder, a browser, or another app is active. Press it to enter or exit Focus Mode without selecting Afterglow first. The global binding takes precedence over the active app's Shift-Command-F action. Turn it off in **Display → Use ⇧⌘F Globally**, or the waveform menu's **Focus Shortcut** submenu, to restore ordinary per-app handling. If another global shortcut owner blocks registration, the same menus show the failure and how to retry. No keyboard-monitoring or Accessibility permission is required.

Clicking Afterglow's Dock icon while Desktop Mode is active now opens Focus directly. The wallpaper remains behind app windows across desktop Spaces; Finder continues to manage the desktop. After closing the normal Afterglow window, the global shortcut reopens it and enters Focus.

## V2.12 — Rendering and playback efficiency

Player clock, playback commands, and artwork queries now run on one serialized background actor, keeping AppleScript waits off the UI thread. Polls never overlap; stale results from an old player connection are discarded. Track identity is checked on every poll, while title/artist/album/duration are cached until the track changes. PlaybackClock also ignores out-of-order samples.

Waves retain all 17 ribbons at 30 fps, share frequency/shape samples across layers, and place their highlights directly on the rendered mesh. Hidden instrumental scenes stop drawing; covered displays reduce their update rate. Audio delivery no longer invalidates the entire display for every frame. Reference animation clocks avoid a second SwiftUI state update for each tick, and unchanged lyric graphs are reused until their line or highlighted word changes.

The update switches estimated word highlighting off once, retaining your saved song offsets and real word timestamps. LRCLIB often supplies line timestamps only; those songs highlight the synchronized line rather than guessing individual vocals. Estimates remain an explicit option in the existing timing controls. If you opt in again, estimates now respect the line's explicit end rather than stretching across an instrumental gap. The waveform menu now includes **Lyric Timing** with earlier/later adjustments and reset for the current recording, available in Focus Mode.

## V2.12.1 — Restore word-by-word progression

Word-by-word emphasis is restored and enabled by default. The update reverses V2.12's one-time setting change; real word timestamps still take precedence, and the existing word progression is used when only line timing exists. The performance improvements remain. Your saved song offsets are preserved.

## V2.12.2 — Fluid word emphasis

Word emphasis now uses a fixed text layout with animated scale, glow, and diamond size instead of changing font metrics on each word. A short 140 ms ease-out places emphasis quickly and settles smoothly. Word selection still follows the same playback timestamps; line changes reset immediately. Word-by-word progression remains enabled, reduced-motion preferences are respected, and no timing offsets are changed.

## V2.13 — Controls in the top-left menu bar

Use **Controls**, beside View and Display in Afterglow's macOS menu bar, for the playback and settings previously reached through the bottom-left launcher: play/pause, previous/next/stop, player connection, Focus/Desktop/full-screen modes, appearance, global shortcut preferences, lyric timing, the lyric library/importer, and beat-sync settings. Timing, library, and beat-sync panels can open directly from the menu in Focus Mode. The waveform status menu shares the same complete controls. The bottom-left launcher remains available in the ordinary window.

## V3.0 — Personal wallpaper and lyric markers

Open **Controls → Appearance → Wallpaper & Lyric Markers…** (also available from the display settings button). Choose a JPEG, PNG, HEIC, TIFF or WebP image and adjust opacity from 0–100%; the starting value is 15%. The image fills the display with centered cropping. Remove Image returns to black. Images are downsampled to at most 2560 pixels on the longest edge on a background task, then copied into local app storage so they survive restart without access to the original file. No image upload is used.

Choose Diamond (the original), Dot, Triangle, Rectangle, Star, Octagon or Emoji for the anchors below lyric words. Emoji supports one composed character and a suggestions menu. Marker choice, custom emoji and opacity persist. Window, Focus and Desktop modes use the same appearance. PlaybackClock, lyric resolution, word onsets, offsets and transport are unchanged. Exact word synchronization requires word-timed source lyrics; existing estimated progression remains an approximation for line-timed songs.

## V3.0.1 — Direct Appearance settings

Use **Controls → Appearance & Wallpaper…** to open the full appearance panel directly, including in Focus Mode. Glow color, clock and motion toggles now live with wallpaper and marker controls, avoiding the unreliable Appearance hover submenu. The waveform status menu uses the same direct entry. Player polling no longer publishes unchanged empty error/status values, reducing unnecessary command-menu rebuilds. Playback clock and timestamp logic are unchanged.

## V3.0.2 — Missing lyrics are visible in wallpaper mode

Focus and Desktop now show a compact status when synchronized lyrics are unavailable, rather than silently displaying only ambient waves. Controls includes Retry Synced Lyrics for an untimed/missing recording. When other timed recordings are available, the status points to the lyric library. Real instrumental passages remain unchanged. A recording-duration mismatch still requires explicit review; timestamps are never stretched to fit another version.

## V3.0.3 — Small missing-lyrics notice, continuous visualizer

When synchronized lyrics are unavailable, every display mode shows the same flowing visualizer plus a small “Lyrics not found” notice. The visualizer uses live beat/audio frames when Beat Sync is enabled; without audio-recording permission it uses ambient motion. During lookup the small notice reads “Finding lyrics…”. Genuine instrumental tracks do not show a missing-lyrics notice. Retry and lyric imports remain in Controls.

## V3.0.4 — independent timed lyric backup

When LRCLIB has no synchronized lyrics (including outages and rate limits), Afterglow now tries the free, keyless [Karalyr API](https://karalyr.com/docs) before accepting untimed text. Karalyr must return the same title, artist and recording duration within two seconds. Its Enhanced LRC is parsed into actual supplied word timestamps; malformed word timing falls back to line timing. No audio is uploaded and no timestamps are estimated by this backup.

The chain is **LRCLIB → Karalyr → lyrics.ovh**. Existing LRCLIB untimed text is retained if Karalyr has no matching timed entry; lyrics.ovh is used only when lyric text is otherwise absent. Karalyr receives title, artist and duration, with at most two bounded exact requests per lookup. Both backup services have separate switches in Lyric library, enabled by default. Disabled providers are not contacted and their cached lyrics are excluded. Existing successful timed cache entries remain usable; old untimed cache decisions are refreshed once to try the new source.

Coverage depends on the providers: Karalyr has a limited community catalog, and lyrics.ovh supplies untimed text only. Missing lyrics still show the existing fallback display. **Try lyrics again** bypasses cached results and misses.
