# Windows optimization

## Implemented

- File-level installer and installed-app size reports, SHA256 hashes, component totals, baseline deltas and optional byte budgets.
- Three Swift runtime staging modes: `full` retains the previous broad bundle for comparison; `runtime` keeps the complete application runtime and VC redistributables from pinned roots; `imports` narrows that set to recursive ordinary/delayed PE dependencies, export-forwarder targets and explicit runtime-loaded extras. Both optimized modes validate dependencies and reject conflicting versions. They never copy System32 DLLs. Every staged DLL has a provenance/hash/dependency manifest outside the app package.
- Fresh staging before replacing generated runtime files, with checks against accidentally bundling stale Linux libraries or unknown files.
- Offline lyric protocol checks under a sanitized PATH, covering Unicode, enhanced LRC, YAML, plain text and errors, in addition to the demo.
- Windows-scoped native compiler profiles: `baseline`; `balanced` (thin LTO, one codegen unit, debug information stripping, speed optimization); `size` (full LTO and size optimization). No panic-mode changes or shared Linux release-profile changes.
- Optional process-tree sampling of visible demo, hidden tray and wallpaper scenarios during installed native acceptance. Includes live WebView2/Swift children; reports memory and normalized CPU with limitations stated in each report.
- CI controls for comparing modes/profiles, Python packaging regressions, PowerShell syntax checks and a package-size job summary.

The selected defaults are `runtime` / `balanced`: it removes compiler tools while retaining the complete application DLL distribution, including libraries loaded dynamically. `imports` remains experimental. No rendering quality, assets, features, update feeds, keys or app identifiers are changed. This is the packaging and measurement stage of `OPTIMIZATION_PLAN.md`; scheduler changes and a Rust lyric-engine replacement are not implemented here.

## Build and compare on Windows

Install the normal Windows build prerequisites from `README.md`, then:

```powershell
python -m pip install -r windows/scripts/requirements-build.txt
python -m unittest discover -s windows/tests -p test_packaging.py -v
./windows/scripts/build-sidecar.ps1 -RuntimeMode full
./windows/scripts/build-installer.ps1 -NativeProfile baseline
```

Install the resulting NSIS setup into a dedicated directory and record it:

```powershell
python windows/scripts/measure-package.py --installer PATH_TO_SETUP.exe --installed PATH_TO_INSTALLED_APP --frontend linux/dist --output windows/test-results/size/baseline.json
```

Retain that installer and report outside the next build's output directory. Build the candidate using `-RuntimeMode runtime` and `-NativeProfile balanced`, install into a fresh directory, then:

```powershell
python windows/scripts/measure-package.py --installer PATH_TO_CANDIDATE_SETUP.exe --installed PATH_TO_CANDIDATE_APP --frontend linux/dist --baseline windows/test-results/size/baseline.json --output windows/test-results/size/candidate.json
./windows/tests/native-smoke.ps1 -AppPath PATH_TO_CANDIDATE_APP/afterglow-windows.exe -CheckDesktop -MeasurePerformance
```

All paths above beginning `PATH_TO_` are placeholders. To enforce approved budgets, pass `--max-installer-bytes` and/or `--max-installed-bytes`. The JSON report is still written on a budget failure. Do not assign budgets until actual release measurements exist.

For CI, dispatch **Windows preview** on this branch with the desired `runtime_mode`, `native_profile` and `measure_performance` inputs. Reports live under `size/` and native evidence under `native/` in the `afterglow-windows-x86_64-preview` artifact. The separate **Windows installed preview** workflow can install that run on a runner without the Swift toolchain; enable `audit_runtime` to recheck its private DLL graph and package-tool tests there. It does not publish unless explicitly requested through its release inputs.

Full-mode roots come from Swift build/toolchain/runtime and VC redistributable discovery. Both optimized modes use the active compiler version's application runtime under `Swift/Runtimes/<version>/usr/bin`, the helper build directory and the VC redistributable directory. Swift's compiler and application distributions can contain different DLLs with the same name (observed for BlocksRuntime in Windows CI), so mixing them is unsafe. Both optimized modes require the matching application runtime and still reject conflicting copies. Full mode records conflicts while retaining the original root precedence for baseline comparison.

## Performance measurements

To sample an existing installed app without changing its state:

```powershell
./windows/scripts/measure-process-tree.ps1 -AppProcessId APP_PID -Scenario visible-lyrics -Seconds 120 -Output windows/test-results/performance/visible.json
```

Repeat baseline/candidate scenarios on the same Windows machine. CI's optional 15-second samples are smoke evidence, not battery or steady-state performance benchmarks. CPU excludes work from short-lived processes missed between samples. Working-set sums can double-count shared pages; private committed bytes are not private working set. Use ETW/WPR for precise startup, GPU, frame-pacing and wakeup attribution, and hardware tests for battery use.

## Acceptance still required

An import graph cannot identify every `LoadLibrary` dependency. `runtime-extra-dlls.json` supports named additions with reasons; it is intentionally not populated with guessed libraries. Imports mode remains experimental until provider HTTPS/cache/fallback paths and module-load traces have been exercised on a clean Windows system, alongside installed native checks. A successful demo or ordinary-import scan alone cannot establish safety.

Before release: compare component bytes, test clean install and upgrade/settings preservation, compare appearance and motion, and validate real players, audio isolation, Explorer recovery, mixed DPI, sleep/resume and physical power behavior. There is no published optimized release as part of this work. Keep the full bundle and existing signed installer available for rollback.

## Reference baseline

GitHub release metadata for `windows-v0.2.1` reports **146,601,820 bytes** for `Afterglow_0.2.1_x64-setup.exe` (about 146.6 MB / 139.8 MiB), inspected 12 November 2026. This is download size only, not installed footprint. The actual download baseline is larger than the initial ~110 MB estimate.

The instrumented full-bundle [baseline manifest](https://github.com/medhansh-19/Afterglow/actions/runs/43193551691) contains **118 DLLs / 522,756,512 bytes**. Three development tools alone account for **386,968,576 bytes**: `liblldb.dll` (166,076,928), `_InternalSwiftScan.dll` (155,166,208), and `LTO.dll` (65,725,440). That run's installer step failed due to an empty Cargo environment override; its completed DLL staging manifest is valid size evidence, not a successful installer test. The override has been fixed and covered by Windows tests.

Primary build references: [Tauri size guidance](https://v2.tauri.app/concept/size/), [Windows installer](https://v2.tauri.app/distribute/windows-installer/), [Microsoft PE format](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format).
