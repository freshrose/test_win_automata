param([int]$X, [int]$Y)
$sig = @"
using System;
using System.Runtime.InteropServices;
public class Clk {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
}
"@
if (-not ("Clk" -as [type])) { Add-Type -TypeDefinition $sig }
[void][Clk]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 150
[Clk]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)  # LEFTDOWN
Start-Sleep -Milliseconds 60
[Clk]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)  # LEFTUP
Write-Output "CLICKED $X $Y"
