param([int]$Hwnd, [int]$X, [int]$Y, [string]$Keys, [int]$ClickCount = 1)
Add-Type -AssemblyName System.Windows.Forms
$sig = @"
using System;using System.Runtime.InteropServices;
public class CT {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,IntPtr e);
}
"@
if (-not ("CT" -as [type])) { Add-Type -TypeDefinition $sig }
if ($Hwnd -ne 0) { [void][CT]::SetForegroundWindow([IntPtr]$Hwnd); Start-Sleep -Milliseconds 350 }
if ($X -ge 0 -and $Y -ge 0) {
  [void][CT]::SetCursorPos($X, $Y)
  Start-Sleep -Milliseconds 120
  for ($i = 0; $i -lt $ClickCount; $i++) {
    [CT]::mouse_event(0x2, 0, 0, 0, [IntPtr]::Zero)
    [CT]::mouse_event(0x4, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 70
  }
  Start-Sleep -Milliseconds 150
}
if ($Keys -ne "") { [System.Windows.Forms.SendKeys]::SendWait($Keys) }
Write-Output "OK click=($X,$Y)x$ClickCount keys=[$Keys]"
