$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Run packaging environment checks on Windows.' }
# Mock only build commands in this test process. Exercise the actual wrapper,
# including restoration after failure, without compiling or needing Swift.
$keys = @('CARGO_PROFILE_RELEASE_LTO','CARGO_PROFILE_RELEASE_CODEGEN_UNITS','CARGO_PROFILE_RELEASE_STRIP','CARGO_PROFILE_RELEASE_OPT_LEVEL')
$saved = @{}
foreach ($key in $keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
$metadata = Join-Path $PSScriptRoot '../test-results/size/build.json'
$metadataBefore = if (Test-Path $metadata) { [IO.File]::ReadAllBytes($metadata) } else { $null }
function npm {
    foreach ($key in $script:expected.Keys) {
        $actual = [Environment]::GetEnvironmentVariable($key, 'Process')
        if ($actual -cne $script:expected[$key]) { throw "$key expected '$($script:expected[$key])', got '$actual'." }
        if ($null -eq $script:expected[$key] -and (Test-Path "Env:$key")) { throw "$key must be absent, not empty." }
    }
    $global:LASTEXITCODE = if ($script:failBuild) { 1 } else { 0 }
}
function git { 'test-commit' }
function rustc { 'test-rust' }
function swift { 'test-swift' }
try {
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, 'saved-test-value', 'Process') }
    foreach ($profile in @('baseline','balanced','size')) {
        $script:expected = @{
            CARGO_PROFILE_RELEASE_LTO = $null
            CARGO_PROFILE_RELEASE_CODEGEN_UNITS = $null
            CARGO_PROFILE_RELEASE_STRIP = $null
            CARGO_PROFILE_RELEASE_OPT_LEVEL = $null
        }
        if ($profile -ne 'baseline') {
            $script:expected.CARGO_PROFILE_RELEASE_LTO = if ($profile -eq 'size') { 'true' } else { 'thin' }
            $script:expected.CARGO_PROFILE_RELEASE_CODEGEN_UNITS = '1'
            $script:expected.CARGO_PROFILE_RELEASE_STRIP = 'debuginfo'
            $script:expected.CARGO_PROFILE_RELEASE_OPT_LEVEL = if ($profile -eq 'size') { 's' } else { '3' }
        }
        foreach ($failure in @($false,$true)) {
            $script:failBuild = $failure
            $thrown = $false
            try { & "$PSScriptRoot/../scripts/build-installer.ps1" -NativeProfile $profile }
            catch { if (-not $failure -or $_.Exception.Message -ne 'Windows installer build failed.') { throw }; $thrown = $true }
            if ($failure -ne $thrown) { throw "Build failure handling failed for $profile." }
            foreach ($key in $keys) {
                if ([Environment]::GetEnvironmentVariable($key, 'Process') -ne 'saved-test-value') { throw "Environment not restored: $key" }
            }
        }
    }
    Write-Host 'PASS baseline/balanced/size settings, absent vs empty variables, and environment restoration on success/failure'
} finally {
    foreach ($key in $keys) {
        if ($null -eq $saved[$key]) { Remove-Item "Env:$key" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    }
    if ($null -eq $metadataBefore) { Remove-Item $metadata -Force -ErrorAction SilentlyContinue }
    else { [IO.File]::WriteAllBytes($metadata, $metadataBefore) }
    Remove-Item Function:npm,Function:git,Function:rustc,Function:swift
    $global:LASTEXITCODE = 0
}
