param(
    [string]$TargetTriple = 'x86_64-pc-windows-msvc',
    [ValidateSet('full','imports')][string]$RuntimeMode = 'full'
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Build the Windows lyric service on Windows.' }
if ($TargetTriple -ne 'x86_64-pc-windows-msvc') { throw 'This preview packages Windows x64 only.' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
function Get-PeMachine([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { return 0 }
        $stream.Position = 0x3c
        $offset = $reader.ReadUInt32()
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { return 0 }
        return $reader.ReadUInt16()
    } finally { $reader.Dispose() }
}
Push-Location $repo
try {
    swift build -c release --product afterglow-lyrics
    if ($LASTEXITCODE -ne 0) { throw 'Swift lyric service build failed.' }
    $bin = (swift build -c release --show-bin-path | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate the Swift build output.' }
    $binary = Join-Path $bin 'afterglow-lyrics.exe'
    if ((Get-PeMachine $binary) -ne 0x8664) { throw 'The lyric service must be a Windows x64 executable.' }
    $binaries = Join-Path $repo 'linux/src-tauri/binaries'
    $runtime = Join-Path $repo 'linux/src-tauri/runtime'
    New-Item -ItemType Directory -Force $binaries,$runtime | Out-Null
    $destination = Join-Path $binaries "afterglow-lyrics-$TargetTriple.exe"
    Copy-Item $binary $destination -Force

    $swift = (Get-Command swift).Source
    $infoText = swift -print-target-info
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the Swift target runtime.' }
    $info = ($infoText -join "`n") | ConvertFrom-Json
    $roots = @((Split-Path $swift -Parent), $bin)
    $roots += @($info.paths.runtimeLibraryPaths)
    if ($env:SDKROOT) { $roots += Join-Path $env:SDKROOT 'usr/bin' }
    $roots += $env:Path -split ';' | Where-Object { $_ -match '(?i)swift' }
    # The installer places runtimes outside the toolchain on modern Swift.
    foreach ($base in @("$env:LOCALAPPDATA/Programs/Swift", "$env:ProgramFiles/Swift", 'C:/Library/Developer')) {
        if (Test-Path $base) {
            $roots += Get-ChildItem $base -Filter 'swiftCore.dll' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object DirectoryName
        }
    }
    # Redistributable VC DLLs belong to the private Swift helper runtime, never
    # copied from System32. The native Rust executable links its CRT statically.
    $vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
    if (Test-Path $vswhere) {
        $vs = & $vswhere -latest -products '*' -property installationPath
        if ($vs) {
            $redist = Join-Path $vs 'VC/Redist/MSVC'
            if (Test-Path $redist) {
                $latest = Get-ChildItem $redist -Directory | Sort-Object Name -Descending | Select-Object -First 1
                if ($latest) { $roots += Join-Path $latest.FullName 'x64/Microsoft.VC143.CRT' }
            }
        }
    }
    $roots = @($roots | Where-Object { $_ -and (Test-Path $_ -PathType Container) } | Select-Object -Unique)
    # Resolve into a fresh directory first, so missing/ambiguous imports cannot
    # leave a partially trimmed runtime. Full mode remains the shipping baseline
    # until imports mode passes provider and clean-machine acceptance.
    $python = (Get-Command python).Source
    $staging = Join-Path ([IO.Path]::GetTempPath()) ('afterglow-runtime-' + [guid]::NewGuid())
    New-Item -ItemType Directory $staging | Out-Null
    try {
        $rootsFile = Join-Path $staging 'roots.json'
        ConvertTo-Json -InputObject @($roots) | Set-Content $rootsFile -Encoding utf8
        $report = Join-Path $repo 'windows/test-results/size/runtime-manifest.json'
        & $python windows/scripts/stage-runtime.py --binary $binary --roots $rootsFile `
            --system (Join-Path $env:SystemRoot 'System32') --destination (Join-Path $staging 'dlls') `
            --report $report --extras windows/runtime-extra-dlls.json --mode $RuntimeMode
        if ($LASTEXITCODE -ne 0) { throw 'Runtime dependency staging failed.' }
        # runtime/ is generated build output. Do not package stale Linux .so
        # files alongside Windows DLLs when reusing a cross-platform checkout.
        $unexpected = @(Get-ChildItem $runtime -Force | Where-Object {
            $_.PSIsContainer -or ($_.Name -ne 'README.txt' -and $_.Name -notmatch '(?i)(\.dll$|\.so(\..*)?$)')
        })
        if ($unexpected.Count) { throw 'Unexpected files in runtime/; refusing to package or delete them.' }
        Get-ChildItem $runtime -File | Where-Object { $_.Name -ne 'README.txt' } | Remove-Item
        Copy-Item (Join-Path $staging 'dlls/*.dll') $runtime
    } finally { Remove-Item $staging -Recurse -Force }

    # Reproduce the packaged loader environment. A globally installed Swift must
    # not mask a missing private runtime DLL. The helper remains a console process
    # whose JSON pipes are owned by the native application.
    $originalPath = $env:Path
    $originalBinary = $env:AFTERGLOW_LYRICS_BINARY
    try {
        $system = Join-Path $env:SystemRoot 'System32'
        $env:Path = "$runtime;$system;$env:SystemRoot"
        $start = [Diagnostics.ProcessStartInfo]::new($destination)
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
        $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $child = [Diagnostics.Process]::Start($start)
        $output = $child.StandardOutput.ReadToEndAsync()
        $errors = $child.StandardError.ReadToEndAsync()
        $child.StandardInput.Write('{"command":"demo"}')
        $child.StandardInput.Close()
        if (-not $child.WaitForExit(20000)) {
            $child.Kill($true)
            throw 'Staged helper timed out without developer PATH.'
        }
        if ($child.ExitCode -ne 0) { throw "Staged helper failed without developer PATH (exit $($child.ExitCode)): $($errors.Result)" }
        $reply = $output.Result | ConvertFrom-Json
        if (-not $reply.document.lines.Count) { throw 'Staged helper returned no timed demo lyrics.' }
        # Exercise Unicode, YAML, enhanced LRC and invalid inputs too. Resolve
        # Python before stripping PATH; these are still local/offline checks.
        $env:AFTERGLOW_LYRICS_BINARY = $destination
        & $python -X utf8 linux/tests/service.py
        if ($LASTEXITCODE -ne 0) { throw 'Staged helper protocol checks failed without developer PATH.' }
    } finally {
        $env:Path = $originalPath
        $env:AFTERGLOW_LYRICS_BINARY = $originalBinary
    }
    Write-Host "Staged $destination with $((Get-ChildItem $runtime -Filter '*.dll').Count) private runtime DLLs."
} finally { Pop-Location }
