param(
    [Parameter(Mandatory = $true)][string]$HelperPath,
    [string]$OutputDirectory = "$PSScriptRoot/../test-results/providers"
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Provider loader checks require Windows.' }
$HelperPath = (Resolve-Path $HelperPath).Path
$runtime = Join-Path (Split-Path $HelperPath) 'runtime'
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$modules = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$requests = [Collections.Generic.List[object]]::new()
$passed = $false
try {
    # Public fixture metadata only. Do not store or print the provider's lyrics.
    foreach ($bypass in @($true,$false)) {
        $request = @{
            command = 'resolve'; bypassCache = $bypass
            track = @{title='Never Gonna Give You Up';artist='Rick Astley';album='';duration=213}
            allowPlainFallback = $false; allowTimedFallback = $false
        }
        $info = [Diagnostics.ProcessStartInfo]::new($HelperPath)
        $info.UseShellExecute = $false; $info.CreateNoWindow = $true
        $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
        $info.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
        $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $info.Environment['PATH'] = "$runtime;$env:SystemRoot/System32;$env:SystemRoot"
        $process = [Diagnostics.Process]::Start($info)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.StandardInput.Write(($request | ConvertTo-Json -Depth 5 -Compress))
            $process.StandardInput.Close()
            $clock = [Diagnostics.Stopwatch]::StartNew()
            while (-not $process.WaitForExit(25)) {
                if ($clock.Elapsed.TotalSeconds -gt 90) { $process.Kill($true); throw 'Provider helper timed out.' }
                try {
                    $process.Refresh()
                    foreach ($module in $process.Modules) { [void]$modules.Add($module.FileName) }
                } catch {} # Sampling may race an exiting process.
            }
            if ($process.ExitCode -ne 0) { throw "Provider helper exited with $($process.ExitCode): $($stderr.Result)" }
            $reply = $stdout.Result | ConvertFrom-Json
            $requests.Add(@{
                bypassCache = $bypass; source = $reply.document.source
                timedLineCount = @($reply.document.lines).Count
                retrievedFromCache = $reply.document.retrievedFromCache
                error = $reply.error
            })
            if (-not $reply.document.lines.Count) { throw 'Live LRCLIB timed lookup did not succeed; check provider/network availability before attributing this to packaging.' }
            if (-not $bypass -and -not $reply.document.retrievedFromCache) { throw 'A second helper process did not retrieve the persisted lyric cache.' }
        } finally { if (-not $process.HasExited) { $process.Kill($true) }; $process.Dispose() }
    }
    $passed = $true
    Write-Host 'PASS packaged helper: live HTTPS timed lyrics and cross-process cache reload without developer PATH'
} finally {
    @{
        passed = $passed; requests = @($requests.ToArray()); observedModules = @($modules | Sort-Object)
        limits = @('Live LRCLIB and cache only; other providers/fallback paths remain unverified.', 'Sampled module list can miss short-lived loads; not an exhaustive ETW trace.')
    } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $OutputDirectory 'report.json') -Encoding utf8
}
