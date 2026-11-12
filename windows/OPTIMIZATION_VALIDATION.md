# Windows package optimization evidence

12 November 2026. Development branch: `codex/windows-optimization`, based on `codex/windows-desktop` at `b6dba92`.

## Measured size

Actual setup executable and fresh installed directory sizes, not CI artifact ZIP sizes. Decimal MB below. Shared WebView2 and user data/cache are excluded.

| Build | Installer bytes | Installed bytes | Private runtime DLLs |
| --- | ---: | ---: | ---: |
| Full bundle / baseline compiler | 146,590,923 | 547,195,801 | 118 |
| Complete app runtime / balanced compiler, with upgrade cleanup | 21,106,018 | 85,643,004 | 32 |
| Experimental imports-only / balanced compiler | 20,246,279 | 82,002,943 | 17 |

The selected complete-runtime build reduces the installer by **85.60%** and installed footprint by **84.35%**. It retains the entire pinned Swift application runtime and VC redistributable set, including libraries not found in static imports. Imports-only saves less than another 1 MB of download and remains experimental.

The baseline runtime manifest contained `liblldb.dll`, `_InternalSwiftScan.dll` and `LTO.dll`, totaling 386,968,576 uncompressed bytes of compiler/debugger tools. The optimized build gets DLLs from the active compiler version's application-runtime distribution, rather than the compiler directory. Actual runtime component sizes including README: 522,756,672 → 61,928,000 bytes. Native executable: 16,278,528 → 15,555,072 bytes. The Swift helper and all 623 license-notice files are byte-identical between these two measured builds.

## Completed evidence

- [Rebuilt full baseline](https://github.com/medhansh-19/Afterglow/actions/runs/43194614221): shared core, frontend/browser, Windows native unit checks, installer, modern and legacy native desktop fixtures all passed.
- [Imports-only candidate](https://github.com/medhansh-19/Afterglow/actions/runs/43193544553): same checks passed, including both desktop fixtures.
- [Imports-only clean Windows install](https://github.com/medhansh-19/Afterglow/actions/runs/43195611395): no Swift toolchain; native checks, strict DLL re-audit, UTF-8/YAML/LRC imports, live LRCLIB HTTPS lookup and cross-process lyric cache reload passed.
- [Complete-runtime candidate](https://github.com/medhansh-19/Afterglow/actions/runs/43195285085): shared core, frontend/browser, Windows native checks, installer and modern desktop fixture passed. The separate legacy fixture failed once because its selected wallpaper parent belonged to a different host PID than the requested fixture. A separate rerun against the identical installer is tracked below; this failure is not hidden or treated as a passing test.
- [Complete-runtime clean install and upgrade](https://github.com/medhansh-19/Afterglow/actions/runs/43197286110): clean runner without Swift; native install checks, DLL graph audit, live HTTPS lookup/cache and upgrade from 0.1.0 all passed. Library hash, saved color/preferences and native relaunch were preserved.
- Portable packaging regressions: 18 tests passed locally, including real PE import/delay/forwarder fixtures, recursive dependencies/cycles, conflicting runtime versions, unknown vendor DLLs in System32, complete-runtime retention and size-budget handling. Windows build-wrapper tests cover all compiler profiles and environment restoration after success/failure.

Final cleanup-enabled setup SHA256: `c7efef221b612bc986ffabdd180ebe7e9e5137e461de2716156640de04552fe6`.

## Final verification tracking

- [Default configuration build](https://github.com/medhansh-19/Afterglow/actions/runs/43196593575): all checks passed, including native tests under the selected compiler profile and both desktop fixtures. Installer 21,102,092 bytes; installed footprint 85,643,004 bytes. This precedes the upgrade-cleanup hook below.
- [Independent legacy fixture rerun](https://github.com/medhansh-19/Afterglow/actions/runs/43197812392): passed against the identical complete-runtime installer on a clean runner, with `native-legacy-fixture` as the actual host and visible desktop pixels verified. The earlier host-selection race remains recorded above.

Application/renderer/assets/native integration source is unchanged relative to `b6dba92`; changes concern packaging, compiler settings, measurement and tests. Existing unrelated uncommitted interface/desktop edits in the original worktree were left untouched. Browser QA screenshots were inspected; this work does not alter typography, effects, resolution or frame-rate settings.

## Upgrade cleanup regression

The stricter [post-upgrade size check](https://github.com/medhansh-19/Afterglow/actions/runs/43199581020) exposed that NSIS over-installs retained obsolete compiler DLLs, even though settings and application functionality survived. Thus earlier small installed-size results applied to fresh installations only.

The fix generates a post-install hook from 86 explicit historical DLL names, excluding every DLL in the incoming runtime. It runs after the new resources are installed, deletes no unknown files or app data, never schedules future deletion of incoming files on reboot, and fails visibly if an obsolete file cannot be removed. Baseline full bundles retain their incoming DLLs. Packaging tests cover incoming-file preservation and rejection of path/NSIS-code injection. The [cleanup-enabled build](https://github.com/medhansh-19/Afterglow/actions/runs/43200485288) passed all shared, browser, Windows native, fresh-install size-budget and modern/legacy fixture checks. The [final clean install and upgrade](https://github.com/medhansh-19/Afterglow/actions/runs/43202071763) passed on runners without Swift: exact incoming DLL-set comparison, post-upgrade size budgets, library/settings preservation, native relaunch, live HTTPS lyric lookup and cache reload after upgrade. Post-upgrade installed size is 85,643,004 bytes, matching the fresh install. No obsolete DLLs remain.

Toolchains recorded by the build: Swift 6.2.1 and Rust 1.99.1, Windows x64. The final application/installer build commit is `f2dbf16`; later commits add acceptance checks and documentation without changing application code.

## Performance scope and remaining work

This round demonstrates download and disk savings, not lower steady-state RAM, CPU or battery use. Unused compiler DLLs in the old installer were not necessarily loaded into the running app.

Optional 15-second hosted-Windows samples include WebView2 and helper descendants. Baseline vs imports-only samples showed similar private committed memory (roughly 132–135 MB visible demo, 196–198 MB tray, 210–212 MB wallpaper). Both also showed high WebView2 CPU in hidden/wallpaper hosted scenarios (~30% of four logical CPUs); visible-demo samples were below 1%. These are short runs on distinct hosted VMs with accessibility/native-host fixtures, not a controlled hardware benchmark. No speed or battery improvement is established. Investigate native visibility, duplicate main/wallpaper rendering and GPU behavior with ETW/WPR on physical Windows hardware before scheduling changes.

Real Spotify/Apple Music interaction, capture isolation, actual Explorer recovery, physical mixed-DPI monitors, sleep/wake, other providers' live fallback paths and battery behavior still require acceptance. The desktop tests use native fixtures; their success does not prove every real Explorer shell configuration.

No optimized release or update feed was published. The candidate retains version 0.2.1 for development comparisons; increase the release version and complete release acceptance before publishing. CI enforces 25 MB installer / 100 MB installed budgets for the selected default build, with deliberate headroom over the measured package.
