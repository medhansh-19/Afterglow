param([ValidateSet('baseline','balanced','size')][string]$NativeProfile = 'baseline')
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Build the Windows installer on Windows.' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
# Scope Cargo settings to this Windows build; the shared Linux manifest and
# panic/unwind behavior remain unchanged. Baseline enables honest comparisons.
$settings = @{
    CARGO_PROFILE_RELEASE_LTO = $null
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = $null
    CARGO_PROFILE_RELEASE_STRIP = $null
    CARGO_PROFILE_RELEASE_OPT_LEVEL = $null
}
if ($NativeProfile -ne 'baseline') {
    $settings.CARGO_PROFILE_RELEASE_LTO = if ($NativeProfile -eq 'size') { 'true' } else { 'thin' }
    $settings.CARGO_PROFILE_RELEASE_CODEGEN_UNITS = '1'
    $settings.CARGO_PROFILE_RELEASE_STRIP = 'debuginfo'
    $settings.CARGO_PROFILE_RELEASE_OPT_LEVEL = if ($NativeProfile -eq 'size') { 's' } else { '3' }
}
$previous = @{}
foreach ($key in $settings.Keys) {
    $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
    [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process')
}
Push-Location (Join-Path $repo 'linux')
try {
    npm run tauri -- build --config ../windows/tauri.windows.conf.json
    if ($LASTEXITCODE -ne 0) { throw 'Windows installer build failed.' }
    $metadata = @{
        nativeProfile = $NativeProfile
        cargoOverrides = $settings
        commit = (git rev-parse HEAD)
        rust = (rustc --version)
        swift = ((swift --version) -join "`n")
    }
    $output = Join-Path $repo 'windows/test-results/size'
    New-Item -ItemType Directory -Force $output | Out-Null
    $metadata | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $output 'build.json') -Encoding utf8
} finally {
    Pop-Location
    foreach ($key in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process')
    }
}
