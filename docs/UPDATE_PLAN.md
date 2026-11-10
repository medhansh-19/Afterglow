# Desktop update implementation plan

This extends the Windows updater to every currently supported desktop platform, without changing music-player integrations or existing application identifiers.

| Platform | Implementation | Installable update | Bootstrap version |
| --- | --- | --- | --- |
| macOS | Sparkle 2.10.1, native update UI, signed feed and Ed25519 archive, sandbox installer helper | Afterglow.app ZIP; universal arm64/x86_64 builds | 3.0.8, build 35 |
| Windows | Tauri 2.14.1, native dialogs and version-bound signature | NSIS installer | 0.2.0 |
| Linux | Shared Tauri update flow, format-specific manifest | Debian (system authorization) or writable AppImage, then restart | 0.2.0 |

1. Preserve Windows behavior and expose the same check/preferences actions on Linux. Let the pinned official updater select and install the current package format. Keep 30-second checks, 30-minute downloads, six-hour scheduling, duplicate-prompt suppression, single-flight operations and explicit download/install consent.
2. Integrate Sparkle conditionally in the macOS app so Windows/Linux Swift core builds never resolve its binary dependency. Use Sparkle's own persisted preferences and scheduling. Add menu actions to the app and menu-bar menus. Embed and sign nested helpers inside out, add the sandbox XPC entitlement names, and set a bundle-relative loader path. Optionally build a universal Mac binary.
3. Use distinct platform feed channels. Windows/Linux share the existing Tauri signing key; Mac uses a separate Ed25519 seed backed up outside the repo and in GitHub Actions. Sign Mac appcast metadata as well as archives, fail closed on unsigned feeds, and verify archives before extraction. Keep private keys out of source and arguments.
4. Extend release staging to select Windows, Linux or Mac and require a successful matching CI run on the selected commit. Generate exact-format manifests or a signed appcast and create drafts only. Public promotion remains a separate operation after acceptance; Mac development candidates remain clearly labeled as ad-hoc and not notarized.
5. Verify Swift builds and core checks, both Mac architectures, embedded framework/helpers/entitlements and packaged launch, manifest boundary tests, signature/key matching and tamper rejection, native Tauri policy tests and all platform CI pipelines.

Existing binaries cannot gain the updater retroactively; one manual bootstrap upgrade is required on each platform. Separate platform versions are intentional. This is cross-platform support for the existing distribution formats, not a claim to support every Linux packaging system or CPU architecture.

References: https://sparkle-project.org/documentation/ and https://v2.tauri.app/plugin/updater/ .
