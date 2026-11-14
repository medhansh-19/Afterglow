# Platform development branches

The platform branches start from the same version of `main`:

| Branch | Platform | Build workflow |
| --- | --- | --- |
| `codex/windows` | Windows | `.github/workflows/windows.yml` |
| `codex/macos` | macOS | `.github/workflows/macos.yml` |
| `codex/linux` | Linux | `.github/workflows/linux.yml` |

Push platform work to its matching branch to run that platform build. Download
build outputs from the workflow run in GitHub Actions. Release publishing remains
an explicit workflow action.

Keep the shared source tree on each branch: Windows and Linux use shared frontend
code under `linux/`, and all platforms depend on the Swift core. Merge shared fixes
through `main`, then merge `main` into each platform branch. Merge completed platform
work back through a pull request to `main`.

Existing feature branches remain available. Uncommitted local changes are not
included in these branches until explicitly committed.
