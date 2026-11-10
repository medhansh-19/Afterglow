# Windows validation evidence

## Current local evidence

Validation was performed on a macOS development host. The following results are actual portable checks, not Windows-native certification:

- `node --test linux/tests/domain.test.js windows/tests/*.test.js` — **22 passed**. Includes recording identity, monotonic pause/seek behavior, timed word gaps, Unicode card limits, invalid schema rejection, collection inheritance/uniqueness, scene privacy separation and migration, punctuation segmentation, original timestamp preservation, 24-word paging, chorus memory and sparse long holds, album-color collections, named swatch deduplication, selected-alternative persistence and bounded retry cancellation.
- `npm run build --prefix linux` — **passed**, production Vite bundle.
- `python windows/tests/ui.py` with a local Vite server and Playwright Chromium in `?platform=windows` mode — **passed**. Exercises silent demo, seek/pause, seven clocks/markers, real paused Appearance preview, preset/named swatches and album collection modes, scene and PNG/map export dimensions, duplicate-name failure, collection delete/cancel and focus, saved excerpts, persistence, invalid-library preservation, Windows help/native-unavailable errors and 640px layout. No page errors. Report/artifacts are emitted through `AFTERGLOW_TEST_OUTPUT` (default `/tmp/afterglow-windows-ui`).
- Frontend Design Premium strict audit against `linux/` — **passed with zero findings** after repairing the nonfunctional brand link. Static audit is supplementary to runtime tests.

The browser demo explicitly has no music or capture. It cannot exercise Windows media sessions, WASAPI, Explorer wallpaper, the tray, WebView2-specific rendering, native clipboard or system dialogs.

## Windows-native checks

The Windows installer was built and installed by [Windows preview run 42674498927](https://github.com/medhansh-19/Afterglow/actions/runs/42674498927), commit `87cff9d`, on Windows Server 2025. All 319 Swift checks, 22 JavaScript tests, 3 native Rust tests, the shared helper protocol, private-runtime staging, license collection and NSIS packaging passed. That run's original UI automation failed to locate controls; subsequent changes corrected the test harness's accessibility activation and rendering waits.

**Installed-app acceptance passed** in [run 42681669228](https://github.com/medhansh-19/Afterglow/actions/runs/42681669228), test-harness commit `8a5247a`, using that same installer on a clean Windows runner without Swift installed. Passed checks include packaged helper Unicode/LRC/enhanced LRC/YAML/TXT/error handling, WebView2 readiness, real demo/lyric IPC, Controls and Appearance, two preference saves, on-disk verification, true process restart and value reload, single-instance forwarding, close-to-tray ownership and window restoration. The application binary was unchanged by the test-harness fixes.

Installer: `Afterglow_0.1.0_x64-setup.exe` (approximately 139 MiB). SHA256: `0611760eb71e739d41c40774e0221eb698567e2e4892f2e681672df4e8e9c267`.

The complete [Linux regression run 42653383695](https://github.com/medhansh-19/Afterglow/actions/runs/42653383695) also passed, including real MPRIS, selected-stream audio isolation, Linux packaging, native startup and headless Wayland wallpaper checks. Its snapshot predates the final additional shared appearance/retry features; those later changes passed the portable browser/domain checks described above. The macOS target built successfully with the shared core changes.

`windows/tests/native-smoke.ps1` accepts the **installed or staged packaged layout**:

```powershell
pwsh -File windows/tests/native-smoke.ps1 -AppPath 'C:\path\Afterglow.exe' -OutputDirectory 'C:\path\smoke-evidence'
```

The executable must have `afterglow-lyrics.exe` and the `runtime` directory beside it. The harness strips Swift development locations from PATH, tests packaged helper Unicode/LRC/enhanced LRC/YAML/TXT/error handling, launches the real app, waits for WebView2/IPC readiness, invokes the accessible demo and native helper, opens Controls/Appearance, updates a native accessible clock slider twice, verifies the on-disk value and reload after a true process restart, forwards a single-instance action, closes the window while retaining its tray owner and restores it by launching again. It rejects native UI error logs. It does not downgrade failures into a browser-only success.

The harness uses `AFTERGLOW_SMOKE_LOG` only as optional diagnostic evidence. Without that environment variable the installed app has no smoke-log output. The tests do not introduce remote debugging or a test-only privileged IPC command.

## Manual Windows 11 acceptance still required

1. Install on a clean x64 Windows 11 machine without Swift, Rust or Node. Run demo, close/reopen, save preferences, replace existing preferences, restart and uninstall. Check non-ASCII user/install paths and Windows scaling.
2. Test Spotify and Apple Music independently, switch recordings rapidly, pause/play/seek/previous/next/stop, reopen the player and handle unsupported commands. Confirm SMTC metadata/timeline corresponds to audible playback.
3. Play two distinguishable simultaneous audio streams. Select only the player process; verify unrelated audio cannot change beat output. Pause/hide/lock/sleep, stop the process, change output devices and test protected or silent streams. No fallback to all system audio is permitted.
4. Exercise Desktop Mode behind icons, icon clicks, tray restore/quit, Explorer restart, monitor removal/rearrangement, fractional scaling and multiple workspaces. Unsupported shell attachment must retain accessible controls and show an error.
5. Exercise global shortcut conflict, success, disable/re-enable and focused alternatives. Native clipboard should paste into Paint; native PNG dialogs should save/cancel correctly.
6. Compare long/RTL lyrics, every clock/marker/emoji, scene restoration, collection color scope, cards and map appearance against the current Mac version. Check [PARITY.md](PARITY.md) for missing features rather than treating them as passed.
7. Measure actual power usage on battery/battery-saver and physical suspend/resume. Hardware claims require these measurements.


## Windows 0.1.1 fixes

Portable regression checks cover full-width waves at 640×480, 1920×1080, 3440×1440, 1080×1920 and 3840×2160, reduced-motion geometry, Mac-derived glass colors and notification expiry/replacement/interaction/dismissal. `windows/tests/regressions-ui.py` exercises the actual UI with a mocked native boundary: capture while Controls stays open, pause/resume, track changes, stop-before-stream-switch, capture failure/retry, notices and live effective-color updates. These tests do not certify WASAPI hardware or real-player audio isolation. Existing Windows UI checks continue to exercise preferences, exports and recovery.

The Windows native adapter now requests event-driven process-loopback samples and lets Windows select the buffer size. The official reference is [Microsoft's ApplicationLoopback sample](https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/ApplicationLoopback/cpp/LoopbackCapture.cpp). Installed-app CI and native compilation must pass before publishing the 0.1.1 installer. Real Spotify/Apple Music and physical-device audio testing remain the acceptance items above.


### Published 0.1.1 evidence

- [Windows build, UI regressions and installed acceptance](https://github.com/medhansh-19/Afterglow/actions/runs/42693788192) passed for application source `138cbec899177e6305e560bcc04fd91084412e3f`: shared Swift/helper checks, 25 JavaScript checks, 3 Rust checks, Vite/NSIS and the installed native app.
- [Clean-machine fresh install and 0.1.0 → 0.1.1 upgrade](https://github.com/medhansh-19/Afterglow/actions/runs/42697174708) passed without Swift installed. Existing library bytes survived setup unchanged; saved clock preferences and a custom named color survived the new app's launch and restart. A prior run could not consistently activate WebView2's demo button; the harness now brings the native window forward and uses focused keyboard activation. Application binaries were unchanged by that harness correction.
- [Full Linux regression](https://github.com/medhansh-19/Afterglow/actions/runs/42693787869) passed, including real MPRIS, selected-stream isolation, package builds and native lifecycle/wallpaper checks.
- Installer SHA256: `f9a877d71ba2f2ced8ac83a668ebc4650e964bba6706b0a1676799967766e6c7`; 145,489,601 bytes. The downloadable filename is `Afterglow-windows-x64-setup.exe`.

The optional installed-workflow upgrade fixture is pinned to the original build artifact and its SHA256, so changing the website's moving installer alias cannot silently change the baseline. Application code is identical to the tested source; subsequent commits contain acceptance-harness and validation records only. Windows real-player audio and physical hardware checks remain unverified as stated above.

## Windows 0.2.1

The Desktop button could deadlock WebView2 by building a new webview from a synchronous command. Windows desktop creation and recovery now run on a serialized worker; IPC awaits completion, while tray and shortcut entry points dispatch to that worker. Linux retains GTK's main-thread context. The wallpaper waits for a complete first frame before hiding Controls.

The footer follows the supplied Mac reference's font sizes and spacing. The main window opens maximized, the canvas uses the current viewport aspect ratio, and each desktop view uses its monitor's physical bounds and taskbar inset. Wallpaper timing and native audio consumption are independent of the hidden main window. Beat response remains active when ambient flow is off.

A native test exposed `STATUS_HEAP_CORRUPTION` in capture activation: a Rust allocation was also owned by a `VT_BLOB` PROPVARIANT. The blob now uses COM allocation with a single owner. The real Windows process-loopback API is tested with the production audio format for three activation/start/stop cycles. This verifies native capture setup, not real Spotify/Apple Music signal or two-player isolation.

Portable validation passes 33 JavaScript tests, the production Vite build, Windows/Linux browser workflows and desktop event/timing checks. Browser checks cover independent word timing, stale audio, ambient-flow-off beat response, state deltas, occluded startup and 16:9, 16:10, ultrawide, portrait, 4K and high-scaling layouts. The native event boundary is mocked in those browser checks. The strict static UI audit reports zero findings.

Native desktop acceptance uses clearly identified modern Progman and legacy WorkerW fixtures on hosted Windows. These are actual Win32 windows in a separate process, with unchanged production discovery and IPC; they are not Explorer certification. Acceptance checks monitor bounds, parenting, click-through/non-activation styles, first-frame readiness, Controls restoration, host process loss/restart and cleanup. Framebuffer pixel checks are explicitly reported as unavailable if the hosted desktop cannot capture visible signal.

- [Modern native fixture, clean installation and upgrade acceptance](https://github.com/medhansh-19/Afterglow/actions/runs/42800669606) passed on the signed 0.2.1 installer from build 42796089973. Visible pixels were verified. The library survived setup byte-for-byte, and saved color/clock preferences survived launch/restart.
- [Legacy native fixture acceptance](https://github.com/medhansh-19/Afterglow/actions/runs/42801480080) passed against that same installer. Its report identifies `native-legacy-fixture` and `desktopPixelsVerified: true`.
- Application source for that installer is `47d77c5fae3ec2508b5815f796c539f6f821f5e0`. Following commits only correct the hosted acceptance harness. The combined final workflow is [42801696737](https://github.com/medhansh-19/Afterglow/actions/runs/42801696737), source `37893e34051a95eee6249553a1900e09c27ee14f`.

The hosted shell automatically restarted and sometimes won discovery ahead of a fixture. The harness now waits for its fixture's complete hierarchy, temporarily disables shell auto-restart only on hosted CI (restored in `finally`), and accurately reports a real Explorer selection rather than claiming fixture coverage. Earlier harness runs failed; their installers were not published as 0.2.1.

The mode actions are inside Controls, leaving a single Controls button on the listening screen. Save screenshot exports the viewport's aspect ratio at 2× resolution; browser acceptance verifies the resulting 2400×1600 PNG for a 1200×800 surface. Lyric-map export's font fetch is now permitted by the packaged app's self-only content policy. Browser export is verified; native Save dialog/clipboard hardware acceptance remains separate.

Windows 0.2.1 retains main's signed updater support. Existing 0.1.x copies require a manual bootstrap installation. Physical Windows 11 Explorer, real Spotify/Apple Music signal isolation, mixed-DPI hot-plug and physical suspend remain unverified; fixtures and native API tests do not certify that hardware behavior.
