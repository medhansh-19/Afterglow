param([ValidateSet('baseline','balanced','size')][string]$NativeProfile = 'balanced')
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Build the Windows installer on Windows.' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
python (Join-Path $PSScriptRoot 'generate-installer-hooks.py') `
    --runtime (Join-Path $repo 'linux/src-tauri/runtime') `
    --obsolete (Join-Path $repo 'windows/obsolete-runtime-dlls.json') `
    --output (Join-Path $repo 'windows/generated/installer-hooks.nsh')
if ($LASTEXITCODE -ne 0) { throw 'Installer runtime cleanup generation failed.' }
# Scope Cargo settings to this Windows build; the shared Linux manifest and
# panic/unwind behavior remain unchanged. Baseline enables honest comparisons.
$settings = & "$PSScriptRoot/native-profile.ps1" -NativeProfile $NativeProfile
$previous = @{}
foreach ($key in $settings.Keys) {
    $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
    if ($null -eq $settings[$key]) { Remove-Item "Env:$key" -ErrorAction SilentlyContinue }
    else { [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process') }
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
        if ($null -eq $previous[$key]) { Remove-Item "Env:$key" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
    }
}
