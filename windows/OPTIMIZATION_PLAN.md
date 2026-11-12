# Windows size and performance implementation plan

Date: 12 November 2026

## Goal and scope

Reduce the Windows download, installed footprint and idle resource use while preserving current functionality, visual assets, rendering quality, lyric accuracy and update compatibility. The reported ~110 MB Windows and ~10 MB macOS figures are user estimates, not measured baselines. Do not promise macOS-sized Windows packages: macOS supplies frameworks that Windows currently receives as private Swift runtime DLLs.

This is a plan only. Windows implementation inspected read-only at `/Users/medhanshadhlakha/.codex/worktrees/afterglow-windows-fixes/Afterglow` (branch `codex/windows-desktop`). Confirm the release commit and outstanding changes there before implementation. No application code or build configuration was changed for this plan.

## Findings from the repository

- Windows uses the shared Tauri/Rust shell and web frontend under `linux/`, not Electron. `windows/tauri.windows.conf.json` already uses WebView2 `downloadBootstrapper`; it does not deliberately bundle a fixed browser runtime.
- `windows/scripts/build-sidecar.ps1` builds a release Swift lyric helper, then collects nearly every x64 DLL from several Swift runtime/build/toolchain directories. Its exclusion list removes some compiler DLLs, but collection is not based on the helper's actual dependencies. This is the strongest candidate for unnecessary bytes, not yet a measured size attribution.
- `linux/src-tauri/tauri.conf.json` packages the entire staged `runtime/` and `notices/` directories.
- The inspected `linux/src-tauri/Cargo.toml` has no explicit release optimization profile.
- Rendering already has frame limits and power handling. Nevertheless, `linux/src/app.js` can schedule animation callbacks faster than its draw limit; the hidden main window in desktop mode and per-monitor wallpaper views need profiling for duplicate work. `linux/src/wallpaper-view.js` also schedules animation callbacks between capped draws.
- The Swift helper is a bounded, one-request JSON process supporting resolve/import/demo. Replacing it would require reproducing provider fallback, caching, parsers and text handling, not just drawing lyrics.

## Phase 1 — establish comparable baselines

Build the exact current release on Windows x64 and archive the installer, hashes, configuration and toolchain versions. Distinguish:

1. Actual setup executable download bytes, excluding any CI artifact containing screenshots/logs.
2. Installed application bytes, broken down into Rust executable, Swift helper, individual DLLs, frontend assets, notices and other files.
3. Shared prerequisites such as WebView2, reported separately; app data/cache separately again.
4. Cold/warm launch, time to first usable display, lyric resolution latency, full-process-tree private working set, CPU, GPU and wakeups.

Run repeated same-machine comparisons for idle/paused, active lyrics, beat sync, Controls preview, hidden tray, desktop wallpaper on one and multiple monitors, lock/display-off, sleep/resume. Include WebView2 children and helper processes. Preserve screenshots and timing traces with the measurements.

Deliverable: size inventory and performance baseline in CI artifacts. Set absolute byte budgets after this inventory; do not infer causes from installer size alone.

## Phase 2 — narrow the Swift runtime bundle

Primary change: replace the broad DLL sweep in `windows/scripts/build-sidecar.ps1` with deterministic dependency staging.

- Walk the helper's PE imports recursively, including delay imports and transitive runtime dependencies. Resolve from approved, versioned runtime/redist roots; record each DLL's provenance, architecture, hash, bytes and dependency reason.
- Distinguish OS/API-set dependencies from privately redistributed DLLs. Do not copy arbitrary system files or choose the first DLL among incompatible toolchain versions.
- Cover runtime-loaded libraries with explicit, documented additions validated by module-load tracing through all supported operations. Static imports alone are insufficient.
- Stage into a clean Windows-specific directory; ensure the resource mapping cannot pick up stale Linux runtimes or other build outputs. Keep required notices and redistribution obligations intact.
- Retain the existing sanitized-PATH smoke test, and extend acceptance to imports, all providers/fallback paths, HTTPS, non-Latin text, emoji, caches, failures and malformed inputs.
- Install and exercise the package on a clean Windows VM with no Swift SDK or developer tools. A demo-only response is not sufficient evidence that a DLL is unnecessary.

Keep the original staging path available for comparison during development. Ship only when dependency coverage and clean-machine checks pass. This phase may save substantially, or little if the runtime is mostly required; report the measured result.

## Phase 3 — optimize binaries and installer

- Benchmark a Rust release profile with LTO, one codegen unit and stripped distribution symbols. Compare normal speed optimization against `opt-level = "s"`; select using both binary bytes and audio/render/startup performance. Preserve separate diagnostic symbols. Scope or validate changes for Linux because the manifest is shared.
- Leave panic semantics unchanged initially. A switch to abort is a behavior change and requires a separate justification.
- Audit enabled Cargo features and shipped release files. Remove only demonstrably unused dependencies, development artifacts, duplicates and source maps; retain fonts, textures, icons and required notices.
- Check the existing NSIS compression algorithm and compare supported alternatives only if useful. Compression reduces download size, not steady-state CPU or installed RAM; measure installation time too. Do not count a default setting as a new saving.
- Keep the existing WebView2 bootstrapper approach, application identifier, updater keys and feed compatible. No UPX or first-launch Swift download in the initial work.

Deliverable: before/after bytes by component and clean install/update/uninstall results, not a nominal compiler-settings change.

## Phase 4 — reduce runtime work without lowering quality

- Schedule work at the existing draw cadence instead of waking on every display refresh and then skipping most draws. Cancel dormant timers/callbacks on hide, pause, lock and sleep; resume immediately on meaningful events.
- In desktop mode, profile the main view separately from wallpaper views. Retain the state/IPC needed to drive wallpapers, while stopping invisible drawing and unused preview work.
- Coalesce wallpaper state updates; use one native audio analysis stream with bounded messages and per-view rendering. Confirm the current ownership before changing it.
- Cache measured hotspots such as repeated text/layout/DOM queries and reusable render data. Bound artwork/lyric caches and release obsolete image resources and capture buffers.
- Prefer native media-session events where practical; retain enough polling for players with incomplete events, without affecting lyric synchronization.
- Preserve current frame caps, resolution, blur, typography, effects and beat responsiveness. Any optional lower-quality battery mode is separate scope requiring a user choice.

Smaller packages do not automatically mean lower RAM or battery consumption. Accept performance changes only using process-tree measurements and visual/timing checks.

## Phase 5 — architecture fallback if the required runtime remains dominant

Only after phases 1–3: evaluate moving the Windows lyric helper into the existing Rust host, removing the Windows private Swift runtime. Keep the Mac implementation intact.

Before committing, create a shared fixture corpus and compare Swift and Rust results for every supported import format, word timing, Unicode, provider priority/backoff, recording alternatives, cache semantics and failures. Preserve the frontend-facing JSON contract and saved-data compatibility. Run providers locally; retain current privacy behavior. Estimate maintenance cost of two engines explicitly.

This is the largest potential structural reduction if Swift is the dominant payload, and the highest regression-risk phase. Prototype and measure before authorizing it as the default implementation. Retain the existing helper until parity is demonstrated.

## Acceptance and rollout

- Feature parity: existing shared/frontend/native tests plus installed-app checks for players, lyric import/resolution, beat isolation, exports/clipboard, shortcuts, tray, wallpaper, mixed DPI, Explorer restart, sleep/resume and updater/settings preservation.
- Appearance: deterministic screenshot comparisons at the same window size/DPI/track/timestamps; inspect animations separately. Do not accept reduced quality to satisfy byte targets.
- Performance: repeat baseline scenarios with the same environment; require no material startup, synchronization, audio or frame-pacing regression. Proposed investigation threshold: >5% regression outside observed run-to-run variance; establish tolerances from baseline noise before making this a gate.
- Size: require a measured reduction over the actual setup and installed baselines. A 50% download reduction is a stretch objective, not a forecast. Set the achievable shipping target after dependency attribution; 10 MB is not a commitment.
- Add per-component CI size reports and budgets based on the accepted optimized build. Keep signed rollback installers; stage the candidate and verify an upgrade from an existing installation before publishing.

Recommended order: measurement → deterministic runtime staging → binary/package tuning → measured runtime optimization → Rust lyric-engine feasibility only if still justified. Keep packaging and scheduling changes in separate reviewable commits.

## Primary technical references

- Tauri app-size guidance: https://v2.tauri.app/concept/size/
- Tauri Windows installer and WebView2 choices: https://v2.tauri.app/distribute/windows-installer/
- Tauri configuration, including NSIS compression: https://v2.tauri.app/reference/config/
- Microsoft PE imports and delay imports: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
