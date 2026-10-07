<# start-capture.ps1 -- (WinRM) writes capture.ps1 and runs it as a vagrant batch
   task (net use works in-session, avoiding New-SmbGlobalMapping error 1312).
   Captures the Delphi install + license slip + registry to the host share.
   Pure ASCII. #>
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force C:\delphi-setup | Out-Null

$cap = @'
$ErrorActionPreference = "Continue"
$log = "C:\delphi-setup\capture.log"
function L($m){ "$(Get-Date -Format s) $m" | Out-File $log -Append -Encoding ascii }
"=== capture $(Get-Date -Format s) ===" | Out-File $log -Encoding ascii
$gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } |
       Select-Object -First 1).IPv4DefaultGateway.NextHop
$share = "\\$gw\delphi-share"
L "host=$gw share=$share"
cmd /c "net use $share /user:avensio_smb avensio26A" 2>&1 | Out-File $log -Append -Encoding ascii
$out = "$share\out"
New-Item -ItemType Directory -Force "$out\studio37","$out\bdscommon" | Out-Null

# registry (32-bit Embarcadero hive + per-user config incl. library paths)
reg export "HKLM\SOFTWARE\WOW6432Node\Embarcadero" "$out\hklm-wow-embarcadero.reg" /y 2>&1 | Out-File $log -Append -Encoding ascii
reg export "HKCU\SOFTWARE\Embarcadero" "$out\hkcu-embarcadero.reg" /y 2>&1 | Out-File $log -Append -Encoding ascii

# license slip
Copy-Item "C:\ProgramData\Embarcadero\*.slip" "$out\" -Force -ErrorAction SilentlyContinue

# BDSCOMMONDIR (small)
robocopy "C:\Users\Public\Documents\Embarcadero\Studio\37.0" "$out\bdscommon" /E /R:1 /W:1 /NFL /NDL /NP | Out-Null

# main install tree
L "robocopy studio37 start"
robocopy "C:\Program Files (x86)\Embarcadero\Studio\37.0" "$out\studio37" /E /R:1 /W:1 /NFL /NDL /NP /MT:8 | Out-Null
L "robocopy studio37 rc=$LASTEXITCODE"

"DONE rc=$LASTEXITCODE $(Get-Date -Format s)" | Out-File "$out\CAPTURE_DONE.txt" -Encoding ascii
cmd /c "net use $share /delete /y" 2>&1 | Out-File $log -Append -Encoding ascii
L "complete"
'@
Set-Content -Path C:\delphi-setup\capture.ps1 -Value $cap -Encoding ascii

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\delphi-setup\capture.ps1"
Register-ScheduledTask -TaskName "capture" -Action $action -User "vagrant" -Password "vagrant" -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName "capture"
Write-Host "capture task started; watch host out\ for CAPTURE_DONE.txt"
