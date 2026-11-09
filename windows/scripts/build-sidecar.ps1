param([string]$TargetTriple = 'x86_64-pc-windows-msvc')
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Build the Windows lyric service on Windows.' }
if ($TargetTriple -ne 'x86_64-pc-windows-msvc') { throw 'This preview packages Windows x64 only.' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $repo
try {
    swift build -c release --product afterglow-lyrics
    if ($LASTEXITCODE -ne 0) { throw 'Swift lyric service build failed.' }
    $bin = (swift build -c release --show-bin-path | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate the Swift build output.' }
    $binary = Join-Path $bin 'afterglow-lyrics.exe'
    $binaries = Join-Path $repo 'linux/src-tauri/binaries'
    $runtime = Join-Path $repo 'linux/src-tauri/runtime'
    New-Item -ItemType Directory -Force $binaries,$runtime | Out-Null
    # Remove old Windows runtime files, preserving Linux resources and README.
    Get-ChildItem $runtime -Filter '*.dll' -File | Remove-Item
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
    # Collect the installed Swift runtime DLL set (including Foundation, ICU,
    # dispatch and Blocks). Do not copy compiler executables or Windows system DLLs.
    foreach ($root in $roots) {
        Get-ChildItem $root -Filter '*.dll' -File | Where-Object {
            $_.Name -notmatch '^(?i:libclang|libLTO|LLVM|sourcekit|IndexStore|swiftScan|swiftSyntax)'
        } | ForEach-Object {
            $target = Join-Path $runtime $_.Name
            if (-not (Test-Path $target)) { Copy-Item $_.FullName $target }
        }
    }
    if (-not (Test-Path (Join-Path $runtime 'swiftCore.dll'))) { throw 'Swift runtime DLLs were not found; refusing an incomplete package.' }

    # Reproduce the packaged loader environment. A globally installed Swift must
    # not mask a missing private runtime DLL. The helper remains a console process
    # whose JSON pipes are owned by the native application.
    $originalPath = $env:Path
    try {
        $system = Join-Path $env:SystemRoot 'System32'
        $env:Path = "$runtime;$system;$env:SystemRoot"
        $output = '{"command":"demo"}' | & $destination
        if ($LASTEXITCODE -ne 0) { throw "Staged helper failed without developer PATH (exit $LASTEXITCODE)." }
        $reply = ($output -join "`n") | ConvertFrom-Json
        if (-not $reply.document.lines.Count) { throw 'Staged helper returned no timed demo lyrics.' }
    } finally { $env:Path = $originalPath }
    Write-Host "Staged $destination with $((Get-ChildItem $runtime -Filter '*.dll').Count) private runtime DLLs."
} finally { Pop-Location }
