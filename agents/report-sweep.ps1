<#
  report-sweep.ps1 -- headless report generation sweep, runs in the VM interactive
  session (scheduled task, LogonType Interactive). Iterates every report mark in
  C:\testdrv\marks.txt, launches avensio.exe with the test-driver /report /out
  switches, dismisses FastScript/DevExpress trial nags inline, and records the
  outcome per mark to C:\testdrv\sweep.csv.

  Outcome classes:
    OK      - non-empty PDF produced (report rendered headless)
    EMPTY   - PDF created but 0 bytes
    FORM    - app booted to main menu, no PDF (report needs a GUI form / FS vars)
    TIMEOUT - neither PDF nor menu detected within budget (unknown block)

  Pure ASCII (PS 5.1 reads .ps1 as ANSI). Self-contained: no module deps.
#>
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms

$sig = @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class SW {
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
 public delegate bool EnumProc(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,IntPtr e);
 [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
 public static List<IntPtr> Find(uint pid){var res=new List<IntPtr>();EnumWindows((h,l)=>{uint p;GetWindowThreadProcessId(h,out p);if(p==pid&&IsWindowVisible(h))res.Add(h);return true;},IntPtr.Zero);return res;}
}
"@
if (-not ("SW" -as [type])) { Add-Type -TypeDefinition $sig }

# --- config (overridable via C:\testdrv\sweep.cfg : key=value) ---
$exe   = 'C:\Users\rosa\_rsm\avensio\__bin\avensio.exe'
$ini   = 'C:\Users\rosa\_rsm\avensio\__bin\avensio.ini'
$cfg   = 'C:\testdrv\sweep.cfg'
if (Test-Path $cfg) {
  foreach ($line in Get-Content $cfg) {
    if ($line -match '^\s*exe\s*=\s*(.+)$') { $exe = $Matches[1].Trim() }
    if ($line -match '^\s*ini\s*=\s*(.+)$') { $ini = $Matches[1].Trim() }
  }
}
$outDir = 'C:\testdrv\out'
[System.IO.Directory]::CreateDirectory($outDir) | Out-Null
$csv  = 'C:\testdrv\sweep.csv'
$prog = 'C:\testdrv\sweep.progress'
$perMaxSec = 22      # hard per-mark budget
$bootGrace = 8       # seconds after which a bare main-menu (no pdf, no nag) == FORM

function Kill-Av { Get-Process avensio -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 400 }

function Dismiss-Nags([uint32]$pid) {
  foreach ($h in [SW]::Find($pid)) {
    $sb = New-Object System.Text.StringBuilder 256; [SW]::GetWindowText($h,$sb,256) | Out-Null; $t = $sb.ToString()
    $r = New-Object SW+RECT; [SW]::GetWindowRect($h,[ref]$r) | Out-Null; $w = $r.R-$r.L; $ht = $r.B-$r.T
    if ($t -match 'AVENSIO SW' -and $w -lt 600 -and $ht -lt 260 -and $ht -gt 40) {
      [SW]::BringWindowToTop($h)|Out-Null; [SW]::SetForegroundWindow($h)|Out-Null; Start-Sleep -Milliseconds 100
      [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    } elseif ($w*$ht -gt 50000 -and $t.Trim() -eq '') {
      [SW]::BringWindowToTop($h)|Out-Null; [SW]::SetForegroundWindow($h)|Out-Null; Start-Sleep -Milliseconds 100
      [SW]::SetCursorPos($r.R-16,$r.T+16)|Out-Null; Start-Sleep -Milliseconds 60
      [SW]::mouse_event(0x2,0,0,0,[IntPtr]::Zero); [SW]::mouse_event(0x4,0,0,0,[IntPtr]::Zero)
    }
  }
}

function Has-Menu([uint32]$pid) {
  foreach ($h in [SW]::Find($pid)) {
    $sb = New-Object System.Text.StringBuilder 256; [SW]::GetWindowText($h,$sb,256) | Out-Null; $t = $sb.ToString()
    if ($t -match 'Hlavn.* nab.dka' -or $t -eq 'Seznam osob') { return $true }
  }
  return $false
}

$marks = Get-Content 'C:\testdrv\marks.txt' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d{6}$' }
"mark,status,size,seconds" | Set-Content $csv -Encoding ASCII
$n = $marks.Count; $idx = 0
foreach ($mark in $marks) {
  $idx++
  "$idx/$n $mark $(Get-Date -Format HH:mm:ss)" | Set-Content $prog -Encoding ASCII
  Kill-Av
  $pdf = Join-Path $outDir "$mark.pdf"
  if ([System.IO.File]::Exists($pdf)) { [System.IO.File]::Delete($pdf) }
  $args = @($ini,'/test','/login','abc:0000','/report',$mark,'/out',$pdf)
  $p = Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory (Split-Path $exe) -PassThru
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $status = 'TIMEOUT'
  while ($sw.Elapsed.TotalSeconds -lt $perMaxSec) {
    Start-Sleep -Milliseconds 600
    $proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    if ([System.IO.File]::Exists($pdf)) {
      $len = (Get-Item $pdf).Length
      if ($len -gt 0) { $status = 'OK'; break }
    }
    if (-not $proc) {
      if ([System.IO.File]::Exists($pdf) -and (Get-Item $pdf).Length -gt 0) { $status='OK' }
      elseif ([System.IO.File]::Exists($pdf)) { $status='EMPTY' }
      else { $status='FORM' }   # terminated without pdf
      break
    }
    Dismiss-Nags ([uint32]$p.Id)
    if ($sw.Elapsed.TotalSeconds -gt $bootGrace -and (Has-Menu ([uint32]$p.Id))) {
      # booted to main menu, report did not auto-run/terminate -> needs a form
      if (-not [System.IO.File]::Exists($pdf)) { $status='FORM'; break }
    }
  }
  $size = if ([System.IO.File]::Exists($pdf)) { (Get-Item $pdf).Length } else { 0 }
  "{0},{1},{2},{3:N1}" -f $mark,$status,$size,$sw.Elapsed.TotalSeconds | Add-Content $csv -Encoding ASCII
  Kill-Av
}
"DONE $n marks $(Get-Date -Format HH:mm:ss)" | Set-Content $prog -Encoding ASCII
