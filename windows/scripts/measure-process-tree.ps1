param(
    [Parameter(Mandatory = $true)][int]$AppProcessId,
    [Parameter(Mandatory = $true)][string]$Scenario,
    [ValidateRange(1,3600)][int]$Seconds = 120,
    [ValidateRange(250,10000)][int]$IntervalMs = 1000,
    [string]$Output = "$PSScriptRoot/../test-results/performance/process-tree.json"
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Process-tree measurement requires Windows.' }
$rootProcess = Get-Process -Id $AppProcessId
if ($rootProcess.ProcessName -ne 'afterglow-windows') { throw 'Select the installed Afterglow process, not a player or test harness.' }
$rootStarted = $rootProcess.StartTime.ToUniversalTime().Ticks
$logicalCores = [Environment]::ProcessorCount
$samples = [Collections.Generic.List[object]]::new()
$previousCpu = @{}
$previousAt = $null
$clock = [Diagnostics.Stopwatch]::StartNew()
while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
    $rootProcess = Get-Process -Id $AppProcessId -ErrorAction SilentlyContinue
    if (-not $rootProcess -or $rootProcess.StartTime.ToUniversalTime().Ticks -ne $rootStarted) { break }
    $tree = @(Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,CreationDate)
    $rootCreated = ($tree | Where-Object ProcessId -eq $AppProcessId).CreationDate
    $ids = [Collections.Generic.HashSet[int]]::new()
    [void]$ids.Add($AppProcessId)
    do {
        $added = $false
        foreach ($item in $tree) {
            if ($item.CreationDate -ge $rootCreated -and $ids.Contains([int]$item.ParentProcessId)) {
                if ($ids.Add([int]$item.ProcessId)) { $added = $true }
            }
        }
    } while ($added)
    $now = $clock.Elapsed.TotalMilliseconds
    $deltaCpuMs = 0.0
    $workingSet = 0L
    $privateBytes = 0L
    $processes = @()
    $currentCpu = @{}
    foreach ($processId in $ids) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if (-not $process) { continue }
        try {
            $started = $process.StartTime.ToUniversalTime().Ticks
            $identity = "$processId/$started"
            $cpu = $process.TotalProcessorTime.TotalMilliseconds
            $currentCpu[$identity] = $cpu
            if ($previousCpu.ContainsKey($identity)) { $deltaCpuMs += [Math]::Max(0, $cpu - $previousCpu[$identity]) }
            $workingSet += $process.WorkingSet64
            $privateBytes += $process.PrivateMemorySize64
            $processes += [pscustomobject]@{
                pid = $processId; name = $process.ProcessName
                cpuTotalMs = $cpu; workingSetBytes = $process.WorkingSet64
                privateCommittedBytes = $process.PrivateMemorySize64
            }
        } catch { continue } # A short-lived helper can exit during enumeration.
    }
    $cpuPercent = $null
    if ($null -ne $previousAt -and $now -gt $previousAt) {
        $cpuPercent = 100 * $deltaCpuMs / ($now - $previousAt) / $logicalCores
    }
    $samples.Add([pscustomobject]@{
        elapsedMs = $now; cpuPercentOfMachine = $cpuPercent
        workingSetBytes = $workingSet; privateCommittedBytes = $privateBytes
        processes = $processes
    })
    $previousAt = $now
    $previousCpu = $currentCpu
    $remaining = $Seconds * 1000 - $clock.Elapsed.TotalMilliseconds
    if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int][Math]::Min($IntervalMs, $remaining)) }
}
$report = @{
    schemaVersion = 1; scenario = $Scenario; logicalCores = $logicalCores
    requestedSeconds = $Seconds; actualSeconds = $clock.Elapsed.TotalSeconds
    machine = @{ os = [Environment]::OSVersion.VersionString; processor = $env:PROCESSOR_IDENTIFIER }
    notes = @(
        'Includes currently running descendants such as WebView2 and the Swift helper.'
        'CPU is normalized to total logical CPU capacity; first sample has no CPU delta.'
        'Short-lived processes between samples can be missed; use ETW for precise CPU/startup attribution.'
        'Working-set sum can count shared pages repeatedly. Private committed bytes are not private working set.'
        'Does not measure GPU, wakeups, frame pacing or battery energy; capture those separately.'
    )
    samples = @($samples.ToArray())
}
$destination = [IO.Path]::GetFullPath($Output)
[IO.Directory]::CreateDirectory((Split-Path $destination)) | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content $destination -Encoding utf8
Write-Host "Recorded $($samples.Count) process-tree samples to $destination"
