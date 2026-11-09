# In-app updates implementation plan

Scope: Windows first, using the existing Tauri application. macOS uses a separate Swift app and Linux Debian installations require a package-manager strategy; neither will be advertised as auto-updating by this change.

1. Use the official Tauri v2 updater and mandatory signed and version-bound NSIS artifacts. Keep the existing Windows application identifier and settings paths. Increment Windows version to 0.2.0.
2. Check on launch after a short delay, then every six hours. Add native tray actions for manual checks and a persisted automatic-check preference. Never install without consent. Suppress repeated automatic prompts for the same version until the next app launch. Manual checks always report results. Network failures remain quiet in background checks.
3. Download and verify before offering restart/install. Preserve the current installation on download or signature failure. Serialize checks/installations. Use native dialogs so keyboard navigation and screen readers follow the OS.
4. Publish signed artifacts and a Windows-only manifest in a draft GitHub release through a separate, manually dispatched workflow. The public endpoint points to an explicitly promoted `windows-updates` release so unrelated Mac/Linux releases cannot change the update channel. Release publication is a deliberate final operation after testing.
5. Generate a private signing key outside the repo and store it as a GitHub Actions secret. Commit only its public key. Pin plugin dependency in Cargo.lock. Do not weaken signature verification.
6. Verify policy unit tests, frontend checks, build, Windows native compilation and installer smoke checks in CI. Full old-to-new installer execution and settings preservation need a Windows acceptance run before production promotion.

Rollout: existing previews have no updater and need one manual installation of 0.2.0. Future versions must increase the Windows version and preserve the signing key. First release bootstraps the updater; it cannot retrofit old binaries.

Reference: https://v2.tauri.app/plugin/updater/
