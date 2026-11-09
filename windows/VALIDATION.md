# Windows validation evidence

## Current local evidence

Validation was performed on a macOS development host. The following results are actual portable checks, not Windows-native certification:

- `node --test linux/tests/domain.test.js windows/tests/*.test.js` — **22 passed**. Includes recording identity, monotonic pause/seek behavior, timed word gaps, Unicode card limits, invalid schema rejection, collection inheritance/uniqueness, scene privacy separation and migration, punctuation segmentation, original timestamp preservation, 24-word paging, chorus memory and sparse long holds, album-color collections, named swatch deduplication, selected-alternative persistence and bounded retry cancellation.
- `npm run build --prefix linux` — **passed**, production Vite bundle.
- `python windows/tests/ui.py` with a local Vite server and Playwright Chromium in `?platform=windows` mode — **passed**. Exercises silent demo, seek/pause, seven clocks/markers, real paused Appearance preview, preset/named swatches and album collection modes, scene and PNG/map export dimensions, duplicate-name failure, collection delete/cancel and focus, saved excerpts, persistence, invalid-library preservation, Windows help/native-unavailable errors and 640px layout. No page errors. Report/artifacts are emitted through `AFTERGLOW_TEST_OUTPUT` (default `/tmp/afterglow-windows-ui`).
- Frontend Design Premium strict audit against `linux/` — **passed with zero findings** after repairing the nonfunctional brand link. Static audit is supplementary to runtime tests.

The browser demo explicitly has no music or capture. It cannot exercise Windows media sessions, WASAPI, Explorer wallpaper, the tray, WebView2-specific rendering, native clipboard or system dialogs.

## Windows-native checks

The Windows workflow builds the Swift sidecar, stages its runtime DLLs, builds the native Tauri executable/installer and runs the project checks. Record the exact successful workflow URL, commit and artifact checksums here after completion; no successful Windows run is claimed by this initial evidence entry.

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
