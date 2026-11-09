# Afterglow Windows implementation plan

Prepared 9 November 2026. This is the planning agent's architecture and acceptance plan. Implementation status and executed checks belong in `PARITY.md` and `VALIDATION.md`; a planned feature is not a passed feature.

## Objective and baseline

Deliver an installable Windows app using the same approach as the Linux port: preserve the shared Swift lyric engine, reuse the local Tauri interface, and replace operating-system integrations with native Windows adapters. Keep macOS and Linux working. Audit against the **current local macOS application**, including its newer uncommitted features, rather than treating the Linux preview as full Mac parity.

The implementation worktree starts at merged Linux commit `f6d05b5` on branch `codex/windows-app`. The original `/Users/medhanshadhlakha/Documents/ChatGPT/Afterglow` checkout contains newer Mac work and must remain unchanged. Inspect that checkout read-only. Do not copy whole SwiftUI files over the merged Linux core: Linux added portability changes that must survive.

Initial target: **Windows 11 x64 development preview**, native Rust MSVC build, WebView2. GSMTC metadata is available earlier, but process-specific audio loopback requires build 20348 or later. Treat older Windows as a separately documented compatibility target, with a visible unsupported-audio error; do not silently capture the entire device. Windows ARM64 requires its own Swift, Rust, DLL, installer and native validation before being claimed supported. [Microsoft GSMTC](https://learn.microsoft.com/en-us/uwp/api/windows.media.control.globalsystemmediatransportcontrolssessionmanager), [Microsoft process-loopback requirements](https://learn.microsoft.com/en-us/windows/win32/api/audioclientactivationparams/ns-audioclientactivationparams-audioclient_process_loopback_params).

## What the current code does

### Native Mac application

`Sources/Afterglow/Player.swift` uses fixed, cached AppleScript against Spotify and Apple Music. Metadata is cached by player track identity; position sampling is monotonic. Transport supports previous, play/pause, stop and next. Mac Spotify stop pauses and resets to zero. Artwork comes from the player, with bounded allowlisted fetching and palette extraction.

`DisplayModel.swift` owns connection, demo, recording identity, lyrics, retries, timing, provider state and scenes. `AfterglowCore/LyricsResolver.swift` is the canonical source for provider matching, fallbacks, cache and imports. Preserve recording/version/duration matching, fresh online lookup with saved-copy outage fallback, provider backoff and explicit imported overrides. Never fabricate word timestamps from plain text.

`Constellation.swift`, `InstrumentalView.swift` and `GlowFrame.swift` provide the actual lyric graph, word/line emphasis, instrumental intervals, flowing ribbons and moving outline. `ChorusMemory.swift` recognizes substantial normalized repeated passages, ignores short filler and supplies canonical indices without rewriting timing. `LyricWordPage.swift` handles word pages. A hash of every repeated line is only an approximation of that behavior.

`WallpaperAppearance.swift`, `GlowColorLibrary.swift` and `GlowColorWheel.swift` provide album/manual/preset/saved/custom colors, wallpaper copies, markers, custom emoji and song scenes. Appearance has a real synchronized preview. `CustomClock.swift`, `ClockSettings.swift` and `ClockAppearance.swift` provide seven clock faces, 70–140% scale, date, seconds, hour format, independent/follow-lyrics colors and saved scene clock settings.

`SongCollections.swift` in the app and core owns local atomic persistence, recording memberships, editable Liked/Favorites and custom unique collection names, selected color source and collection-over-scene color precedence. Selecting an inherited collection is a valid explicit choice; it must not unexpectedly fall through to a different colored collection. Editing the currently displayed collection color updates the collection, not a hidden global preference. Invalid disk data is preserved and failed writes do not become published state.

`LyricCards.swift`, `LyricCardArtwork.swift` and `LyricMapCapture.swift` save excerpts of at most six lines/280 characters, export 1080×1350 cards and freeze the real visible lyric map. `ScreenshotCompanion.swift` passively observes standard Mac screenshot shortcuts when opted in and offers a separate branded preview with Save, Copy and native Share. It never claims the screenshot hotkey, reads another app's image or sends automatically.

`DesktopMode.swift` owns window/desktop/focus transitions and restoration, including Stage Manager/widget behavior specific to macOS. `FocusShortcut.swift` owns global shortcuts and recovery after closing the ordinary window. `EnergyMonitor.swift` and `EnergyBudget.swift` supply event-driven sleep/display/session/thermal/battery scheduling. AC playback is capped at 30 Hz; battery/low-power at 20 Hz; previews at 15 Hz; critical thermal at 10 Hz. Paused and hidden animation stops, clocks tick independently and capture is released while paused/hidden/asleep.

### Existing Linux port

`linux/src-tauri/src/main.rs` exposes bounded commands for players, transport, artwork, lyric-service requests, local libraries, audio, desktop mode, shortcuts and PNG export. A single owner manages capture and a second display-only WebView renders wallpaper through `publish_display` / `display-state`. Tray and single-instance actions already exist.

`linux/src/{app,domain,render,lyric-graph,ribbon-mesh,clock-preview,bridge}.js` contains the reusable interface, local data validation, recording identity, rendering, seven clock faces, scenes, cards and collections. `Sources/AfterglowLyricsService/main.swift` runs one bounded JSON request on stdin and produces one JSON response on stdout, using the same core parsers/resolver as macOS. Rust cancels superseded lookups and enforces input/output/time limits. Linux adapters are MPRIS, PulseAudio/PipeWire stream monitors, X11/Wayland, portals, UPower and logind.

Linux already documents that it is a development preview. Its controls cover many Mac features but do not establish semantic or visual parity. Examples to examine: simplified chorus matching/paging, collection validation/color scope, settings reset, lack of real preview panels, passive screenshots/native sharing and incomplete power behavior. Reusing these files does not waive those checks.

## Architecture decision

Keep `linux/` as the shared desktop code directory for this change, despite its historical name. A directory rename would enlarge review and risk Linux CI for no immediate user benefit. Add Windows scripts, documentation and config under `windows/`; add target-specific Rust modules under the existing shell. A later independent refactor may rename shared code to `desktop/`.

Use compile-time `cfg(target_os = "windows")` at the native adapter boundary and explicit platform metadata for user-facing help, labels and browser preview storage. Do not infer supported functionality only from the browser's user agent. Platform-gate Linux-only dependencies. Keep the existing CSP, local-only frontend and display-window capabilities.

| Existing boundary | Windows implementation | Contract to preserve |
|---|---|---|
| `player::players`, `player::control` | WinRT GSMTC session adapter | Stable selected session; sane timeline/metadata; actual command outcome |
| `artwork::fetch` | Session thumbnail stream | Bounded validated PNG/JPEG/WebP data URL; no arbitrary filesystem read |
| `audio::streams`, `Capture::start/stop` | Render-session PID list and WASAPI process loopback | Only selected process tree, generation cancellation, same FFT/event payload |
| `desktop::set` | Display-only Windows wallpaper host | Click-through below icons, main-window restore, single capture owner |
| `power::start` | Power, display, session and suspend notifications | Stop capture immediately; schedule rendering/polling by visible activity |
| `shortcuts::start` | Windows hotkey registration/message pump | Same action dispatch and visible conflict/errors; unregister on disable/exit |
| Library and sidecar owner | Windows-safe paths, executable/runtime packaging, replace semantics | Bounded requests, preserved corrupt files, repeat saves and no orphan helper |

## Implementation sequence and acceptance

### 1. Cross-platform foundation and installer

1. Add a Windows Tauri configuration overlay with a Windows identifier, NSIS setup target, Windows icon and WebView2 installation strategy. Give explicit development/bundle commands. An `.msi` may be added only when actually built/tested; NSIS `.exe` alone is a useful first deliverable. Tauri supports both formats; MSI creation requires Windows. [Tauri Windows packaging](https://v2.tauri.app/distribute/windows-installer/).
2. Install pinned Swift/Rust/Node versions in a Windows CI runner. Use the same Swift version as Linux initially unless a reproducible Windows incompatibility demands another pin. Swift's official Windows instructions require Visual Studio C++ tools and Windows SDK. [Swift installation](https://www.swift.org/install/windows/), [manual prerequisites](https://www.swift.org/install/windows/manual/).
3. Build `afterglow-lyrics.exe` for Windows with SwiftPM. Stage the target-suffixed `afterglow-lyrics-x86_64-pc-windows-msvc.exe` expected by Tauri `externalBin`. Resolve the packaged helper beside the main executable; use the suffixed executable only in development. Tauri expects target-specific external binaries. [Tauri sidecars](https://v2.tauri.app/develop/sidecar/).
4. Collect transitive runtime dependencies of the release helper, including Swift/Foundation, dispatch, ICU/curl/OpenSSL when used and the applicable Visual C++ runtime. Preserve dependency notices and fail if required libraries are absent. Bundle into private resources; configure only the child process DLL search/PATH, avoid global environment changes. Swift explicitly requires redistribution of needed runtime libraries. [Swift Windows runtime model](https://github.com/swiftlang/swift/blob/main/docs/WindowsToolchain.md).
5. Hide the lyric helper console using Windows process creation flags. Preserve 600 KB request / 4 MB response / 90 second deadline and cancellation controls. Supply a private working directory and avoid ambient PATH executable lookup. Check helper start errors clearly.
6. Replace Linux-only library overwrite assumptions. `rename(temp, existing)` is not a portable replacement primitive. Use a tested Windows-compatible replace operation with a same-directory temporary file, flushed content, original-file preservation on failure and serialization of saves. Test at least two saves to the same library, restart persistence and failure retention. Do not delete the original as a preparatory overwrite step.
7. Check Foundation URLSession/TLS, cache directories, portable FFT, Yams and all CoreChecks on Windows. Test the staged helper in a process with Swift removed from PATH. Package success on the development runner alone does not prove runtime independence.

**Acceptance:** A clean Windows machine can install, launch, run the silent demo, import timed lyrics, save twice, restart with preferences retained, and uninstall without requiring Swift/Rust/Node installations. Installer, architecture, hashes, commit and exact runtime test evidence are recorded.

### 2. Windows playback, artwork and timing

1. Initialize WinRT/COM on the worker thread and request `GlobalSystemMediaTransportControlsSessionManager`. Enumerate participating sessions; persist `SourceAppUserModelId` as session selection. Separate duplicate-session identity if needed. Apple Music/Spotify support is conditional on their actual Windows sessions exposing the required fields; do not equate the API's existence with a verified app integration. [Microsoft session manager](https://learn.microsoft.com/en-us/uwp/api/windows.media.control.globalsystemmediatransportcontrolssessionmanager).
2. Read title, artist, album, playback status/rate, timeline and controls capability. Reject non-finite/unreasonable values and stale disconnected sessions. Keep all untrusted metadata as data.
3. Convert WinRT 100 ns units accurately. Timeline `Position` is valid at `LastUpdatedTime`; while playing, compensate for elapsed UTC time multiplied by playback rate, clamp to the available timeline, then hand the frontend a fresh monotonic sample. Do not add elapsed time when paused. Handle clock anomalies and future timestamps conservatively. [Microsoft timeline semantics](https://learn.microsoft.com/en-us/uwp/api/windows.media.control.globalsystemmediatransportcontrolssessiontimelineproperties).
4. Use supported `Try*Async` transport methods; treat a returned `false` as failure. Disable unsupported controls instead of pretending they work. Native Mac stop semantics should be compared explicitly where Windows exposes only pause or no seek.
5. Prefer change events (`SessionsChanged`, media/playback/timeline changes) plus bounded fallback polling, retaining single in-flight sampling. Avoid recreating managers and reading image bytes every animation frame.
6. Read bounded session thumbnail streams through WinRT, sniff supported image formats and feed the existing artwork/palette pipeline. Do not grant frontend arbitrary `file:`/HTTP access to make artwork work.

**Acceptance:** Fixture tests cover discover/select/disconnect, metadata, next/previous/pause/stop/seek, stale timeline compensation and thumbnails. Real Windows Spotify and Apple Music each need a human/native machine run with track, seek, pause/resume and lyrics alignment evidence. Browser-only tests cannot satisfy this gate.

### 3. Player-specific beat capture

1. Enumerate active render audio sessions using audio session manager interfaces and `IAudioSessionControl2` process IDs. Resolve a readable process identity; make process-tree scope visible. GSMTC's application ID is not a process ID. Do not guess a PID from arbitrary untrusted strings.
2. Activate `VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK` using `AUDIOCLIENT_ACTIVATION_PARAMS`, `AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK` and `PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE`. Follow the first-party ApplicationLoopback sample's activation completion and capture lifecycle. [Microsoft sample](https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/ApplicationLoopback/cpp/LoopbackCapture.cpp).
3. Guard unsupported OS/API failures and dead processes. Use only the chosen process tree; never substitute device-wide loopback or a microphone. Multiprocess browsers may combine tabs; explain that real scope at selection.
4. Convert capture format to bounded mono floating samples (including silent packets), reuse the existing FFT/band analysis, emit existing `audio-frame` events, and never persist captured PCM.
5. Stop and release on pause, disconnect, hidden views, suspend, session lock and quit. Generation checks prevent an old capture from publishing into a newly selected song/process. Reconnect only while the user's enabled intent still applies; process restarts require revalidation.

**Acceptance:** On an interactive Windows audio host, play two distinguishable signals from two process trees. Only the selected signal may affect captured energy/bands. Check silence, routing changes, dead/reused PID, pause/hide/sleep, restart and stop cancellation. Hosted CI often lacks a real endpoint: missing hardware is an explicit unexecuted test, never a pass.

### 4. Window, desktop, tray and shortcuts

1. Reuse the separate display-only wallpaper WebView with limited capabilities. Never run a second player/capture owner in it. Main-window closure and hidden WebViews require lifecycle handling so controls can reopen and wallpaper does not become orphaned.
2. For desktop mode, attach to an appropriate Explorer wallpaper host only after checking current shell support. The common WorkerW/Progman message technique is an implementation-dependent integration, not a supported stable wallpaper API. Handle host absence/restart and fail visibly while retaining the normal window. `SetParent` alone does not place content below desktop icons; check child/popup styles, DPI awareness, monitor-coordinate translation and input transparency. [Microsoft SetParent rules](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setparent).
3. Preserve non-activating click-through, position on the selected display, correct 100/125/150/200% scaling, monitor removal and return-to-window. Test Windows Show Desktop, virtual desktops and Explorer restart. Record any single-monitor limit explicitly.
4. Use native tray actions for Open, Return to Window and Quit; single-instance startup must reveal a usable window and preserve queued `--action` requests until the frontend is ready.
5. Register Ctrl+Shift+F/D/B/A/M hotkeys through a native message loop (or Tauri global shortcut plugin). Use no-repeat semantics, report conflicts and support disabling/unregistering. Windows-logo shortcuts are OS-reserved. Never register PrintScreen/Win+Shift+S as ordinary action hotkeys. [Microsoft RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey).
6. Focus Mode must have a reliable Escape exit and restored bounds/decorations. Mac-specific Stage Manager/widget hiding has no direct Windows counterpart; describe the Windows behavior honestly. If Beat Sync hotkey merely opens settings rather than toggling capture, mark it as a semantic difference.

**Acceptance:** Native window/tray/single-instance/hotkey tests on Windows, including a global shortcut conflict, close/reopen, quit with capture enabled, focus transitions and desktop restoration. Desktop-specific tests run in an Explorer interactive session, not a headless build runner only.

### 5. Power and responsiveness

1. Register for Windows power source, energy-saver and display notifications. Receive suspend/resume and session lock/unlock signals; update existing `power-state` events. Stop native capture before publishing suspension. Unregister notification handles on exit. [Microsoft power events](https://learn.microsoft.com/en-us/windows/win32/power/system-power-management-events), [notification registration](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerpowersettingnotification).
2. Mirror current Mac scheduling goals: 30 Hz AC / 20 Hz battery or energy saver; no paused/hidden animation; separate second/minute clock ticks; 1 s playing / 1.5 s constrained / 2 s paused / 5 s hidden fallback sampling. A visible wallpaper remains active when the controls are hidden. Stop player polling while sleeping/display off/session inactive.
3. Windows does not provide a drop-in equivalent to `ProcessInfo.thermalState` for this user app. Do not label battery detection as thermal parity. Retain conservative budgets and record unavailable automatic thermal levels until implemented with justified platform evidence.

**Acceptance:** Test policy decisions independently and measure real interactive battery/display/suspend lifecycle. Confirm no extra helper/capture threads remain after disable and paused clocks continue at only the required cadence.

### 6. Current Mac feature reconciliation

The testing agent owns the detailed matrix and sends defects to implementation. Prioritize behavior defects over pixel imitation:

- Keep untimed lyrics in the explicitly opened library. Main display remains synchronized graph/ribbons; no invented synchronization.
- Carry over punctuation boundaries, bracket filtering, long-line paging and active-word mapping without rewriting provider times.
- Match normalized passage-based chorus memory, filler exclusions and deterministic backward seeking.
- Match unique 1–40 character collection names, explicit inherited selection, collection color precedence and active color editing scope; confirm deletion and retain damaged/failed-save state.
- Match album/preset/saved/custom color choices for collections and clock; scenes snapshot the actual values and restore the global baseline correctly.
- Match seven clock styles, 70–140% range, format/date/seconds, preview and independent ticking.
- Preserve real lyric previews in Appearance and Collections, with per-recording timing and disabled/reduced motion behavior.
- Preserve card/excerpt limits, original metadata/colors, 1080×1350 export and actual frozen-map geometry. Verify Windows save dialog and image clipboard in other apps.
- Add native sharing and passive screenshot companion only through an explicit non-blocking opt-in implementation. Windows screenshot mechanisms differ; observing a shortcut is not proof a screenshot completed. Do not intercept or replace OS shortcuts, inspect other apps' captured pixels or send automatically. If absent, list as an actual feature gap and retain explicit map Save/Copy.
- Remove Linux-specific labels, MPRIS/PulseAudio installation advice and incorrect permission text on Windows. Add concise truthful Windows help/status/error copy.

## Verification and release evidence

| Layer | Checks | What it establishes |
|---|---|---|
| Shared model/core | `swift run CoreChecks`, service protocol tests, `npm test --prefix linux` | Parser, matching, timing, scene, collection and data-validation behavior |
| Frontend | Production Vite build plus browser feature scenarios | Controls and rendered UI behavior with fixtures; no native integration claim |
| Windows compile | `cargo check/test` on Windows, Windows CI | Windows API bindings and target dependencies compile |
| Staged helper | Protocol checks from bundled files with Swift PATH removed | Required helper runtime DLLs resolve without developer Swift |
| Windows package | NSIS build; install/launch demo/save/restart/uninstall | Installer and actual packaged executable work |
| Native OS fixture | Controlled SMTC publisher, clipboard, shortcuts, windows | Real API round trips, native lifecycle and error handling |
| Real player/audio/desktop | Interactive Windows 11 with Spotify, Apple Music, two audio streams, Explorer, multiple DPI displays | Actual product compatibility and integration correctness |

Run checks sequentially after dependent edits; share independent results between planning/build/testing agents. Fail workflow steps on real failures, upload diagnostic artifacts even on failure, and do not mark missing hardware or skipped native tests green. Record OS/build, architecture, commit, commands, outcomes, logs/screenshots and artifact SHA256 in `windows/VALIDATION.md`. Keep `windows/PARITY.md` a table of Implemented / Tested / Partial / Missing / Needs Windows hardware, with concrete evidence links and no inferred passes.

Development preview completion requires a working installer and truthful known limitations. **Full Mac parity** requires every applicable matrix row to pass, or a clearly documented Windows-native replacement accepted by the user. Updating the website or declaring stable Windows support must follow verified artifacts and correct claims; a download button does not establish compatibility.
