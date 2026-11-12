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
    foreach ($key in $global:AfterglowPackagingExpected.Keys) {
        $actual = [Environment]::GetEnvironmentVariable($key, 'Process')
        if ($actual -cne $global:AfterglowPackagingExpected[$key]) { throw "$key expected '$($global:AfterglowPackagingExpected[$key])', got '$actual'." }
        if ($null -eq $global:AfterglowPackagingExpected[$key] -and (Test-Path "Env:$key")) { throw "$key must be absent, not empty." }
    }
    $global:LASTEXITCODE = if ($global:AfterglowPackagingFailBuild) { 1 } else { 0 }
}
function git { 'test-commit' }
function rustc { 'test-rust' }
function swift { 'test-swift' }
try {
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, 'saved-test-value', 'Process') }
    foreach ($profile in @('baseline','balanced','size')) {
        $global:AfterglowPackagingExpected = @{
            CARGO_PROFILE_RELEASE_LTO = $null
            CARGO_PROFILE_RELEASE_CODEGEN_UNITS = $null
            CARGO_PROFILE_RELEASE_STRIP = $null
            CARGO_PROFILE_RELEASE_OPT_LEVEL = $null
        }
        if ($profile -ne 'baseline') {
            $global:AfterglowPackagingExpected.CARGO_PROFILE_RELEASE_LTO = if ($profile -eq 'size') { 'true' } else { 'thin' }
            $global:AfterglowPackagingExpected.CARGO_PROFILE_RELEASE_CODEGEN_UNITS = '1'
            $global:AfterglowPackagingExpected.CARGO_PROFILE_RELEASE_STRIP = 'debuginfo'
            $global:AfterglowPackagingExpected.CARGO_PROFILE_RELEASE_OPT_LEVEL = if ($profile -eq 'size') { 's' } else { '3' }
        }
        foreach ($failure in @($false,$true)) {
            $global:AfterglowPackagingFailBuild = $failure
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
    Remove-Variable AfterglowPackagingExpected,AfterglowPackagingFailBuild -Scope Global -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
}
