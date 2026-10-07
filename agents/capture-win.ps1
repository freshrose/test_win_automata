param(
  [int]$Pid_ = 0,
  [string]$ClassName = "",
  [string]$Out
)
# Capture a top-level window of avensio (by PID, optionally filtered by class) to a PNG via PrintWindow.
Add-Type -AssemblyName System.Drawing
$sig = @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinCap {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
if (-not ("WinCap" -as [type])) { Add-Type -TypeDefinition $sig }

$script:found = [IntPtr]::Zero
$script:foundArea = 0
$cb = [WinCap+EnumWindowsProc]{
  param($h,$l)
  if (-not [WinCap]::IsWindowVisible($h)) { return $true }
  $wpid = 0; [void][WinCap]::GetWindowThreadProcessId($h, [ref]$wpid)
  if ($Pid_ -ne 0 -and $wpid -ne $Pid_) { return $true }
  $sb = New-Object System.Text.StringBuilder 256
  [void][WinCap]::GetClassName($h, $sb, 256)
  $cn = $sb.ToString()
  if ($ClassName -ne "" -and $cn -ne $ClassName) { return $true }
  $r = New-Object WinCap+RECT
  [void][WinCap]::GetWindowRect($h, [ref]$r)
  $area = ($r.Right - $r.Left) * ($r.Bottom - $r.Top)
  if ($area -gt $script:foundArea) { $script:foundArea = $area; $script:found = $h }
  return $true
}
[void][WinCap]::EnumWindows($cb, [IntPtr]::Zero)

if ($script:found -eq [IntPtr]::Zero) { Write-Output "NO_WINDOW"; exit 2 }
$h = $script:found
[void][WinCap]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 250
$r = New-Object WinCap+RECT
[void][WinCap]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
if ($w -le 0 -or $ht -le 0) { Write-Output "BAD_RECT"; exit 3 }
$bmp = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [WinCap]::PrintWindow($h, $hdc, 2)  # PW_RENDERFULLCONTENT
$g.ReleaseHdc($hdc)
if (-not $ok) {
  # fallback: screen copy of the window rect
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $ht)))
}
$dir = Split-Path -Parent $Out
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output ("SAVED " + $Out + " " + $w + "x" + $ht)
