param(
  [Parameter(Mandatory = $true)][string]$AppPath,
  [string]$OutputDirectory = "$PSScriptRoot/../../output/windows-native-smoke"
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Native smoke requires Windows; browser tests cannot replace it.' }
$AppPath = (Resolve-Path $AppPath).Path
$directory = Split-Path $AppPath
$helper = Join-Path $directory 'afterglow-lyrics.exe'
$runtime = Join-Path $directory 'runtime'
if (-not (Test-Path $helper)) { throw 'Packaged helper is missing beside the installed app.' }
if (-not (Test-Path $runtime)) { throw 'Packaged Swift runtime directory is missing.' }
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
$log = Join-Path $OutputDirectory 'native.log'
Remove-Item $log -Force -ErrorAction SilentlyContinue
$originalPath = $env:PATH
$originalLog = $env:AFTERGLOW_SMOKE_LOG
# Neither the Swift development toolchain nor the build directory may satisfy DLL loading.
$cleanPath = @("$env:SystemRoot/system32", $env:SystemRoot, "$env:SystemRoot/System32/Wbem") -join ';'
$env:PATH = $cleanPath
$env:AFTERGLOW_SMOKE_LOG = $log
$application = $null
try {
  function Request-Helper([hashtable]$Request) {
    $info = [System.Diagnostics.ProcessStartInfo]::new($helper)
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
    $info.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $info.CreateNoWindow = $true
    $info.Environment['PATH'] = "$runtime;$cleanPath"
    $process = [System.Diagnostics.Process]::Start($info)
    $output = $process.StandardOutput.ReadToEndAsync()
    $errorOutput = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write(($Request | ConvertTo-Json -Depth 10 -Compress))
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(20000)) { $process.Kill($true); throw 'Packaged helper timed out.' }
    if ($process.ExitCode -ne 0) { throw "Packaged helper failed: $($errorOutput.Result)" }
    return $output.Result | ConvertFrom-Json
  }
  $demo = Request-Helper @{ command = 'demo' }
  if ($demo.document.lines[0].words.Count -eq 0) { throw 'Packaged demo has no word timestamps.' }
  $lrc = Request-Helper @{ command = 'import'; fileExtension = 'lrc'; text = "[offset:500]`n[00:02.50]सितारे ✨`n[00:05.00]Returns" }
  if ($lrc.document.lines[0].time -ne 2 -or $lrc.document.lines[0].text -ne 'सितारे ✨') { throw 'Packaged helper lost UTF-8 or lyric offset.' }
  $enhanced = Request-Helper @{ command = 'import'; fileExtension = 'lrc'; text = '[00:02.00]<00:02.00>Light <00:03.00>returns<00:04.00>' }
  if ($enhanced.document.lines[0].words.Count -ne 2) { throw 'Packaged enhanced-LRC parser failed.' }
  $yaml = Request-Helper @{ command = 'import'; fileExtension = 'yaml'; text = "lines:`n- text: Light`n  start_ms: 1000`n  end_ms: 2000`n" }
  if ($yaml.document.lines[0].time -ne 1) { throw 'Packaged YAML parser failed.' }
  $plain = Request-Helper @{ command = 'import'; fileExtension = 'txt'; text = 'Untimed lyrics' }
  if ($plain.document.plainText -ne 'Untimed lyrics') { throw 'Packaged plain-text parser failed.' }
  $bad = Request-Helper @{ command = 'unknown' }
  if (-not $bad.error) { throw 'Packaged helper accepted invalid protocol command.' }

  Add-Type -AssemblyName UIAutomationClient
  Add-Type -AssemblyName UIAutomationTypes
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AfterglowSmokeWindow {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@
  function Wait-Until([scriptblock]$Check, [string]$Failure, [int]$Seconds = 30) {
    $limit = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
      if (& $Check) { return }
      Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $limit)
    throw $Failure
  }
  function Find-Button([string]$Name) {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($application.MainWindowHandle)
    if ($null -eq $root) { return $null }
    $condition = [System.Windows.Automation.AndCondition]::new(
      [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty, $Name),
      [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    )
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
  }
  function Invoke-Button([string]$Name) {
    $script:button = $null
    Wait-Until { $script:button = Find-Button $Name; $null -ne $script:button } "Native accessible button is missing: $Name"
    $pattern = $script:button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $pattern.Invoke()
  }
  $application = Start-Process -FilePath $AppPath -PassThru
  Wait-Until { $application.Refresh(); $application.MainWindowHandle -ne [IntPtr]::Zero } 'Afterglow native main window did not appear.'
  Wait-Until { (Test-Path $log) -and (Get-Content $log -Raw).Contains('ui-ready') } 'WebView2 did not report native UI readiness.'
  Invoke-Button 'Try the silent demo'
  Wait-Until { (Get-Content $log -Raw).Contains('lyrics:demo') } 'Native UI did not invoke packaged lyric service.'
  Invoke-Button 'Controls'
  Invoke-Button 'Appearance'
  # Change a native accessible range twice: the second save exercises replace-existing semantics.
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($application.MainWindowHandle)
  $sliderCondition = [System.Windows.Automation.AndCondition]::new(
    [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty, 'Clock size'),
    [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Slider)
  )
  $slider = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $sliderCondition)
  if ($null -eq $slider) { throw 'Native accessible clock-size slider is missing.' }
  $range = $slider.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
  $baselineSaves = @((Get-Content $log) | Where-Object { $_ -like '*library-saved*' }).Count
  $range.SetValue(110)
  Wait-Until { @((Get-Content $log) | Where-Object { $_ -like '*library-saved*' }).Count -gt $baselineSaves } 'First native preference save failed.'
  $range.SetValue(120)
  Wait-Until { @((Get-Content $log) | Where-Object { $_ -like '*library-saved*' }).Count -gt ($baselineSaves + 1) } 'Replacing existing native preferences failed.'
  # A second invocation forwards to the same owner rather than creating a second app.
  $secondary = Start-Process -FilePath $AppPath -ArgumentList '--action', 'appearance' -PassThru
  if (-not $secondary.WaitForExit(10000)) { $secondary.Kill($true); throw 'Second app instance did not exit.' }
  Wait-Until { (Get-Content $log -Raw).Contains('single-instance:appearance') } 'Single-instance action was not forwarded.'
  # Closing the main window should retain the tray owner; launching without an action restores it.
  $window = $application.MainWindowHandle
  [AfterglowSmokeWindow]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  Wait-Until { -not [AfterglowSmokeWindow]::IsWindowVisible($window) } 'Close did not hide the main window.'
  $application.Refresh()
  if ($application.HasExited) { throw 'Close exited the app instead of retaining the tray owner.' }
  $restore = Start-Process -FilePath $AppPath -PassThru
  if (-not $restore.WaitForExit(10000)) { $restore.Kill($true); throw 'Restore app invocation did not exit.' }
  Wait-Until { [AfterglowSmokeWindow]::IsWindowVisible($window) } 'Single-instance restore did not reopen the window.'
  Start-Sleep -Milliseconds 500
  $contents = Get-Content $log -Raw
  if ($contents.Contains('client-error:')) { throw "Native UI reported an error: $contents" }
  $report = @{
    passed = $true; appPath = $AppPath; developerSwiftPathRemoved = $true
    helper = @('demo', 'unicode-lrc-offset', 'enhanced-lrc', 'yaml', 'txt', 'invalid-command')
    native = @('WebView2-ready', 'accessible-demo-button', 'native-lyrics-bridge', 'controls', 'appearance', 'save-replace-existing-preferences', 'single-instance-action', 'close-to-tray-owner', 'restore-window')
    untested = @('real-Spotify-Apple-Music', 'process-audio-isolation', 'Explorer-wallpaper', 'physical-sleep-battery', 'native-clipboard-dialog', 'tray-menu-click')
  }
  $report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDirectory 'report.json') -Encoding utf8
  Write-Host 'PASS packaged Swift helper with stripped developer PATH, native WebView2 demo/controls, single-instance forwarding and close/restore lifecycle'
} finally {
  if ($application -and -not $application.HasExited) { Stop-Process -Id $application.Id -Force -ErrorAction SilentlyContinue }
  $env:PATH = $originalPath
  $env:AFTERGLOW_SMOKE_LOG = $originalLog
}
