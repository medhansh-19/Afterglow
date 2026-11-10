param(
  [Parameter(Mandatory = $true)][string]$AppPath,
  [string]$OutputDirectory = "$PSScriptRoot/../../output/windows-native-smoke",
  [switch]$CheckDesktop,
  [ValidateSet('modern','legacy')][string]$DesktopLayout = 'modern'
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
$originalBrowserArguments = $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--force-renderer-accessibility'
# Neither the Swift development toolchain nor the build directory may satisfy DLL loading.
$cleanPath = @("$env:SystemRoot/system32", $env:SystemRoot, "$env:SystemRoot/System32/Wbem") -join ';'
$env:PATH = $cleanPath
$env:AFTERGLOW_SMOKE_LOG = $log
$application = $null
$desktopFixture = $null
$desktopPixelsVerified = $false
$desktopHost = 'unverified'
$originalShellRestart = $null
$shellRestartChanged = $false
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
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AfterglowSmokeWindow {
  public static uint ExpectedOwner = 0;
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
  public static IntPtr FindByClass(string cls) { return FindWindow(cls,null); }
  [DllImport("user32.dll")] static extern IntPtr GetDesktopWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint process);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder value, int length);
  [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr Style(IntPtr hWnd, int index);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  delegate bool WindowProc(IntPtr window, IntPtr data);
  delegate bool MonitorProc(IntPtr monitor, IntPtr hdc, ref Rect rect, IntPtr data);
  [DllImport("user32.dll")] static extern bool EnumWindows(WindowProc callback, IntPtr data);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, WindowProc callback, IntPtr data);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorProc callback, IntPtr data);
  public struct Rect { public int Left,Top,Right,Bottom; }
  public static System.Collections.Generic.List<IntPtr> Wallpapers(int pid) {
    var found = new System.Collections.Generic.List<IntPtr>();
    WindowProc callback = delegate(IntPtr window, IntPtr data) {
      uint process; GetWindowThreadProcessId(window, out process);
      var title = new System.Text.StringBuilder(256); GetWindowText(window,title,256);
      if (process == (uint)pid && title.ToString() == "Afterglow Wallpaper") found.Add(window);
      return true;
    };
    WindowProc top = delegate(IntPtr window, IntPtr data) { callback(window,data); EnumChildWindows(window,callback,data); return true; };
    EnumWindows(top,IntPtr.Zero); return found;
  }
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
  public static void RevealFixture() {
    if (ExpectedOwner == 0) return;
    // Fixture screenshot only: unrelated hosted terminal windows must not
    // occlude the synthetic desktop. Production wallpaper z-order is unchanged.
    WindowProc callback = delegate(IntPtr window, IntPtr data) {
      uint pid; GetWindowThreadProcessId(window,out pid);
      if(pid==ExpectedOwner && IsWindowVisible(window)) SetWindowPos(window,IntPtr.Zero,0,0,0,0,0x13);
      return true;
    };
    EnumWindows(callback,IntPtr.Zero);
  }
  public static string ValidateDesktop(int pid) {
    var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
    try {
      var monitors = new System.Collections.Generic.List<Rect>();
      MonitorProc callback = delegate(IntPtr monitor, IntPtr hdc, ref Rect rect, IntPtr data) { monitors.Add(rect); return true; };
      EnumDisplayMonitors(IntPtr.Zero,IntPtr.Zero,callback,IntPtr.Zero);
      var windows = Wallpapers(pid);
      if (windows.Count != monitors.Count || windows.Count == 0) return "Wallpaper count differs from monitor count.";
      foreach (var window in windows) {
        uint parent; GetWindowThreadProcessId(GetParent(window),out parent);
        if (parent == (uint)pid || parent == 0 || (ExpectedOwner != 0 ? parent != ExpectedOwner : System.Diagnostics.Process.GetProcessById((int)parent).ProcessName.ToLowerInvariant() != "explorer")) return "Wallpaper parent PID " + parent + " differs from expected host " + ExpectedOwner + ", app " + pid + ".";
        if ((Style(window,-16).ToInt64() & 0x40000000) == 0) return "Wallpaper is not a child window.";
        if ((Style(window,-20).ToInt64() & 0x08000020) != 0x08000020) return "Wallpaper is not click-through and non-activating.";
        Rect actual; if (!GetWindowRect(window,out actual)) return "Wallpaper bounds unavailable.";
        bool match = false; foreach (var rect in monitors) if (rect.Left==actual.Left && rect.Top==actual.Top && rect.Right==actual.Right && rect.Bottom==actual.Bottom) match=true;
        if (!match) return "Wallpaper does not cover a complete monitor.";
      }
      return "";
    } finally { SetThreadDpiAwarenessContext(previous); }
  }

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
    $application.Refresh()
    [AfterglowSmokeWindow]::SetForegroundWindow($application.MainWindowHandle) | Out-Null
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
    [AfterglowSmokeWindow]::SetForegroundWindow($application.MainWindowHandle) | Out-Null
    $script:button.SetFocus()
    Start-Sleep -Milliseconds 150
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
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
  $slider = $null
  for ($attempt = 0; $attempt -lt 65 -and $null -eq $slider; $attempt++) {
    Start-Sleep -Milliseconds 150
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($application.MainWindowHandle)
    $slider = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $sliderCondition)
    if ($null -eq $slider) { [System.Windows.Forms.SendKeys]::SendWait('{TAB}') }
  }
  if ($null -eq $slider) { throw 'Native accessible clock-size slider is missing.' }
  $range = $slider.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
  $baselineSaves = @((Get-Content $log) | Where-Object { $_ -like '*library-saved*' }).Count
  $range.SetValue(110)
  Wait-Until { @((Get-Content $log) | Where-Object { $_ -like '*library-saved*' }).Count -gt $baselineSaves } 'First native preference save failed.'
  $range.SetValue(120)
  Wait-Until { @((Get-Content $log) | Where-Object { $_ -like '*library-saved*' }).Count -gt ($baselineSaves + 1) } 'Replacing existing native preferences failed.'
  $libraryLine = @(Get-Content $log | Where-Object { $_ -like 'library-path:*' })[-1]
  if (-not $libraryLine) { throw 'Native save did not identify its persisted library.' }
  $libraryPath = $libraryLine.Substring('library-path:'.Length)
  $persisted = Get-Content $libraryPath -Raw | ConvertFrom-Json
  if ($persisted.settings.clockSize -ne 120) { throw 'Clock size 120 did not reach the library file.' }
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
  # A true process restart must reload the same preference, not retain in-memory state.
  Stop-Process -Id $application.Id -Force
  $application.WaitForExit(5000) | Out-Null
  if ($CheckDesktop) {
    $desktopLibrary = Get-Content $libraryPath -Raw | ConvertFrom-Json
    $desktopLibrary.settings.tint = '#22ccaa'
    $desktopLibrary.settings.albumColor = $false
    $desktopLibrary.settings.wallpaper = $null
    $desktopLibrary | ConvertTo-Json -Depth 50 | Set-Content $libraryPath -Encoding utf8NoBOM
  }
  $readyCount = @((Get-Content $log) | Where-Object { $_ -eq 'ui-ready' }).Count
  $application = Start-Process -FilePath $AppPath -PassThru
  Wait-Until { $application.Refresh(); $application.MainWindowHandle -ne [IntPtr]::Zero } 'Restarted native main window did not appear.'
  Wait-Until { @((Get-Content $log) | Where-Object { $_ -eq 'ui-ready' }).Count -gt $readyCount } 'Restarted WebView2 did not become ready.'
  Invoke-Button 'Controls'
  Invoke-Button 'Appearance'
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($application.MainWindowHandle)
  $reloaded = $null
  for ($attempt = 0; $attempt -lt 65 -and $null -eq $reloaded; $attempt++) {
    Start-Sleep -Milliseconds 150
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($application.MainWindowHandle)
    $reloaded = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $sliderCondition)
    if ($null -eq $reloaded) { [System.Windows.Forms.SendKeys]::SendWait('{TAB}') }
  }
  if ($null -eq $reloaded) { throw 'Clock-size slider is missing after restart.' }
  $range = $reloaded.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
  if ($range.Current.Value -ne 120) { throw 'Restarted app did not reload clock size 120.' }
  if ($CheckDesktop) {
    function Capture-DesktopSignal {
      Add-Type -AssemblyName System.Drawing
      $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
      $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
      $green = 0
      for ($y = [int]($bounds.Height * 0.15); $y -lt [int]($bounds.Height * 0.75); $y += 4) {
        for ($x = [int]($bounds.Width * 0.25); $x -lt [int]($bounds.Width * 0.75); $x += 4) {
          $pixel = $bitmap.GetPixel($x, $y)
          if ($pixel.G -gt 20 -and $pixel.G -gt ($pixel.R * 1.5) -and $pixel.G -gt ($pixel.B * 1.05)) { $green++ }
        }
      }
      $bitmap.Save((Join-Path $OutputDirectory 'desktop-native.png'))
      $graphics.Dispose(); $bitmap.Dispose()
      return $green
    }
    [AfterglowSmokeWindow]::SetForegroundWindow($application.MainWindowHandle) | Out-Null
    [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
    # Hosted CI has no supported interactive shell. Keep this explicitly a
    # native fixture test instead of racing a partially initialized Explorer.
    $hostedFixture = $env:GITHUB_ACTIONS -eq 'true'
    if ($hostedFixture) {
      $shellKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
      $originalShellRestart = (Get-ItemProperty $shellKey -Name AutoRestartShell -ErrorAction SilentlyContinue).AutoRestartShell
      Set-ItemProperty $shellKey -Name AutoRestartShell -Type DWord -Value 0
      $shellRestartChanged = $true
      Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
      Wait-Until { [AfterglowSmokeWindow]::FindByClass('Progman') -eq [IntPtr]::Zero } 'Hosted Explorer did not release its desktop.'
    } elseif ([AfterglowSmokeWindow]::FindByClass('Progman') -eq [IntPtr]::Zero) {
      Start-Process "$env:WINDIR/explorer.exe" | Out-Null
      Start-Sleep -Milliseconds 1500
    }
    if ($hostedFixture -or [AfterglowSmokeWindow]::FindByClass('Progman') -eq [IntPtr]::Zero) {
      $desktopHost = "native-$DesktopLayout-fixture"
      $desktopFixture = Start-Process (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile','-NonInteractive','-File',"$PSScriptRoot/desktop-host.ps1",'-Layout',$DesktopLayout) -NoNewWindow -RedirectStandardOutput (Join-Path $OutputDirectory 'fixture-stdout.log') -RedirectStandardError (Join-Path $OutputDirectory 'fixture-stderr.log') -PassThru
      [AfterglowSmokeWindow]::ExpectedOwner = [uint32]$desktopFixture.Id
      Write-Warning 'Testing a native desktop-host fixture; real Explorer remains unverified.'
      Wait-Until { if ($desktopFixture.HasExited) { throw ('Native desktop fixture exited: ' + (Get-Content (Join-Path $OutputDirectory 'fixture-stderr.log') -Raw)) }; ((Get-Content (Join-Path $OutputDirectory 'fixture-stdout.log') -Raw) -match 'fixture:ready') } 'The native desktop host fixture did not start.'
    } else { $desktopHost = 'Explorer'; [AfterglowSmokeWindow]::ExpectedOwner = 0 }
    $demoCount = @((Get-Content $log) | Where-Object { $_ -eq 'lyrics:demo' }).Count
    Invoke-Button 'Try the silent demo'
    Wait-Until { @((Get-Content $log) | Where-Object { $_ -eq 'lyrics:demo' }).Count -gt $demoCount } 'Desktop demo did not load.'
    $baselinePixels = Capture-DesktopSignal
    Invoke-Button 'Controls'
    Invoke-Button 'Desktop'
    Wait-Until { $reason = [AfterglowSmokeWindow]::ValidateDesktop($application.Id); if ($reason -ne $script:lastDesktopReason) { Write-Host ('Desktop validation: ' + $reason); $script:lastDesktopReason = $reason }; (Get-Content $log -Raw).Contains('desktop-ready') -and $reason -eq '' } 'Wallpaper did not become a full-monitor Explorer child.' 45
    Wait-Until { -not [AfterglowSmokeWindow]::IsWindowVisible($application.MainWindowHandle) } 'Desktop Mode did not hide its main window after readiness.'
    [AfterglowSmokeWindow]::RevealFixture()
    if ($baselinePixels -gt 40) {
      Wait-Until { (Capture-DesktopSignal) -gt 40 } 'Wallpaper windows exist but their lyric-colored pixels were not visible on the desktop.' 20
      $desktopPixelsVerified = $true
    } else {
      Write-Warning 'The hosted framebuffer does not expose the visible app pixels. Canvas first-frame readiness and native geometry are checked; desktop screenshot visibility remains unverified.'
    }
    $open = Start-Process $AppPath -PassThru
    $open.WaitForExit(10000) | Out-Null
    Wait-Until { [AfterglowSmokeWindow]::IsWindowVisible($application.MainWindowHandle) } 'Tray-style restore did not show controls over the wallpaper.'
    # Desktop was entered from Controls; its dialog remains open on restore.
    Invoke-Button 'Close controls'
    Invoke-Button 'Controls'
    if ([AfterglowSmokeWindow]::ValidateDesktop($application.Id) -ne '') { throw 'Opening Controls removed the desktop wallpaper.' }
    [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
    $readyCount = @((Get-Content $log) | Where-Object { $_ -eq 'desktop-ready' }).Count
    if ($desktopFixture) {
      Stop-Process -Id $desktopFixture.Id -Force
      $desktopFixture.WaitForExit(5000) | Out-Null
      $desktopFixture = Start-Process (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile','-NonInteractive','-File',"$PSScriptRoot/desktop-host.ps1",'-Layout',$DesktopLayout) -NoNewWindow -RedirectStandardOutput (Join-Path $OutputDirectory 'fixture-stdout.log') -RedirectStandardError (Join-Path $OutputDirectory 'fixture-stderr.log') -PassThru
      [AfterglowSmokeWindow]::ExpectedOwner = [uint32]$desktopFixture.Id
      Wait-Until { ((Get-Content (Join-Path $OutputDirectory 'fixture-stdout.log') -Raw) -match 'fixture:ready') } 'Restarted fixture did not become ready.'
    } else {
      Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
      Start-Process "$env:WINDIR/explorer.exe" | Out-Null
    }
    Wait-Until { @((Get-Content $log) | Where-Object { $_ -eq 'desktop-ready' }).Count -gt $readyCount -and [AfterglowSmokeWindow]::ValidateDesktop($application.Id) -eq '' } 'Wallpaper did not reconnect after Explorer restarted.' 45
    if (-not [AfterglowSmokeWindow]::IsWindowVisible($application.MainWindowHandle)) { throw 'Desktop recovery hid the controls the user had reopened.' }
    $restore = Start-Process $AppPath -ArgumentList '--action', 'desktop' -PassThru
    $restore.WaitForExit(10000) | Out-Null
    Wait-Until { [AfterglowSmokeWindow]::Wallpapers($application.Id).Count -eq 0 -and [AfterglowSmokeWindow]::IsWindowVisible($application.MainWindowHandle) } 'Stopping Desktop Mode left an orphan wallpaper or hidden controls.'
    Write-Host "PASS native full-monitor $desktopHost parenting, click-through styles, first-frame handshake, controls restore, host restart recovery and cleanup"
  }
  Start-Sleep -Milliseconds 500
  $contents = Get-Content $log -Raw
  if ($contents.Contains('client-error:')) { throw "Native UI reported an error: $contents" }
  $report = @{
    desktopChecked = [bool]$CheckDesktop
    desktopHost = $desktopHost; desktopPixelsVerified = $desktopPixelsVerified
    passed = $true; appPath = $AppPath; developerSwiftPathRemoved = $true
    helper = @('demo', 'unicode-lrc-offset', 'enhanced-lrc', 'yaml', 'txt', 'invalid-command')
    native = @('WebView2-ready', 'accessible-demo-button', 'native-lyrics-bridge', 'controls', 'appearance', 'save-replace-existing-preferences', 'process-restart-preference-reload', 'single-instance-action', 'close-to-tray-owner', 'restore-window')
    untested = @('real-Spotify-Apple-Music', 'process-audio-isolation', 'Explorer-wallpaper', 'physical-sleep-battery', 'native-clipboard-dialog', 'tray-menu-click')
  }
  $report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDirectory 'report.json') -Encoding utf8
  Write-Host 'PASS packaged Swift helper with stripped developer PATH, native WebView2 demo/controls, single-instance forwarding and close/restore lifecycle'
} catch {
  try {
    if ($application -and -not $application.HasExited) {
      $application.Refresh()
      $root = [System.Windows.Automation.AutomationElement]::FromHandle($application.MainWindowHandle)
      $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | ForEach-Object {
        [pscustomobject]@{ name=$_.Current.Name; control=$_.Current.ControlType.ProgrammaticName; enabled=$_.Current.IsEnabled; offscreen=$_.Current.IsOffscreen; bounds=$_.Current.BoundingRectangle.ToString() }
      } | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $OutputDirectory 'ui-tree.json')
      Add-Type -AssemblyName System.Drawing
      $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
      $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
      $bitmap.Save((Join-Path $OutputDirectory 'failure.png'))
      $graphics.Dispose(); $bitmap.Dispose()
    }
  } catch { Write-Warning "Could not capture failure diagnostics: $_" }
  throw
} finally {
  if ($application -and -not $application.HasExited) { Stop-Process -Id $application.Id -Force -ErrorAction SilentlyContinue }
  if ($desktopFixture -and -not $desktopFixture.HasExited) { Stop-Process -Id $desktopFixture.Id -Force -ErrorAction SilentlyContinue }
  if ($shellRestartChanged) {
    if ($null -eq $originalShellRestart) { Remove-ItemProperty $shellKey -Name AutoRestartShell -ErrorAction SilentlyContinue }
    else { Set-ItemProperty $shellKey -Name AutoRestartShell -Type DWord -Value $originalShellRestart }
  }
  $env:PATH = $originalPath
  $env:AFTERGLOW_SMOKE_LOG = $originalLog
  $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = $originalBrowserArguments
}
