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
