# Session-7 GUI action runner. Reads C:\avensio\_act.json, performs an optional
# coordinate click and/or SendKeys on the interactive desktop, then captures the
# full virtual screen to C:\avensio\shots\_screen.png. Driven by host via a
# scheduled task (/IT, session 7). Execution policy on this VM is Bypass.
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$sig = @"
using System;using System.Runtime.InteropServices;
public class Act {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,IntPtr e);
}
"@
if (-not ("Act" -as [type])) { Add-Type -TypeDefinition $sig }

$j = Get-Content 'C:\avensio\_act.json' -Raw | ConvertFrom-Json

# Optional: kill any running avensio (unlock exe before relaunch).
if ($j.kill) {
  Get-Process avensio -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 500
}

# Optional: launch an app in this interactive session, then wait for it to boot.
if ($j.launch) {
  $le = [string]$j.launch.exe
  $la = @()
  if ($j.launch.args) { $la = @($j.launch.args) }
  if ($la.Count -gt 0) { Start-Process -FilePath $le -ArgumentList $la -WorkingDirectory (Split-Path $le) }
  else                 { Start-Process -FilePath $le -WorkingDirectory (Split-Path $le) }
  $bw = if ($j.launch.bootwait) { [int]$j.launch.bootwait } else { 6000 }
  Start-Sleep -Milliseconds $bw
}

if ($null -ne $j.x -and $j.x -ge 0) {
  $cnt = if ($null -ne $j.count) { [int]$j.count } else { 1 }
  [void][Act]::SetCursorPos([int]$j.x, [int]$j.y)
  Start-Sleep -Milliseconds 150
  for ($i = 0; $i -lt $cnt; $i++) {
    if ($j.right) { [Act]::mouse_event(0x8,0,0,0,[IntPtr]::Zero); [Act]::mouse_event(0x10,0,0,0,[IntPtr]::Zero) }
    else          { [Act]::mouse_event(0x2,0,0,0,[IntPtr]::Zero); [Act]::mouse_event(0x4,0,0,0,[IntPtr]::Zero) }
    Start-Sleep -Milliseconds 80
  }
  Start-Sleep -Milliseconds 200
}
if ($null -ne $j.x2 -and $j.x2 -ge 0) {
  Start-Sleep -Milliseconds 350
  [void][Act]::SetCursorPos([int]$j.x2, [int]$j.y2)
  Start-Sleep -Milliseconds 200
  $c2 = if ($j.count2) { [int]$j.count2 } else { 1 }
  for ($k = 0; $k -lt $c2; $k++) {
    [Act]::mouse_event(0x2,0,0,0,[IntPtr]::Zero); [Act]::mouse_event(0x4,0,0,0,[IntPtr]::Zero)
    Start-Sleep -Milliseconds 80
  }
  Start-Sleep -Milliseconds 200
}
if ($j.keys) { [System.Windows.Forms.SendKeys]::SendWait([string]$j.keys); Start-Sleep -Milliseconds 300 }
$wait = if ($j.wait) { [int]$j.wait } else { 400 }
Start-Sleep -Milliseconds $wait

$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$bmp.Save('C:\avensio\shots\_screen.png', [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
