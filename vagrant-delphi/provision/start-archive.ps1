<# start-archive.ps1 -- (WinRM) writes archive.ps1 and runs it as a vagrant batch
   task (no WinRM timeout). Bundles the Delphi install + license slip + registry
   + BDSCOMMONDIR into ONE local .tgz, which the host then pulls over WinRM.
   Pure ASCII. #>
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force C:\delphi-setup | Out-Null

$arc = @'
$ErrorActionPreference = "Continue"
$log = "C:\delphi-setup\archive.log"
function L($m){ "$(Get-Date -Format s) $m" | Out-File $log -Append -Encoding ascii }
"=== archive $(Get-Date -Format s) ===" | Out-File $log -Encoding ascii
$cap = "C:\cap"
Remove-Item $cap -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$cap\reg","$cap\bdscommon" | Out-Null
reg export "HKLM\SOFTWARE\WOW6432Node\Embarcadero" "$cap\reg\hklm-wow-embarcadero.reg" /y 2>&1 | Out-File $log -Append -Encoding ascii
reg export "HKCU\SOFTWARE\Embarcadero"            "$cap\reg\hkcu-embarcadero.reg"     /y 2>&1 | Out-File $log -Append -Encoding ascii
Copy-Item "C:\ProgramData\Embarcadero\*.slip" "$cap\" -Force -ErrorAction SilentlyContinue
robocopy "C:\Users\Public\Documents\Embarcadero\Studio\37.0" "$cap\bdscommon" /E /R:1 /W:1 /NFL /NDL /NP | Out-Null
L "meta staged; starting tar"
$tgz = "C:\delphi-capture.tgz"
Remove-Item $tgz -Force -ErrorAction SilentlyContinue
& tar.exe -czf $tgz -C "C:\Program Files (x86)\Embarcadero\Studio" "37.0" -C "C:\" "cap"
$rc = $LASTEXITCODE
$gb = if (Test-Path $tgz) { [math]::Round((Get-Item $tgz).Length/1GB,2) } else { 0 }
L "tar rc=$rc size=${gb}GB"
"DONE rc=$rc size=${gb}GB $(Get-Date -Format s)" | Out-File "C:\delphi-setup\ARCHIVE_DONE.txt" -Encoding ascii
L "complete"
'@
Set-Content -Path C:\delphi-setup\archive.ps1 -Value $arc -Encoding ascii

Remove-Item C:\delphi-setup\ARCHIVE_DONE.txt -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\delphi-setup\archive.ps1"
Register-ScheduledTask -TaskName "archive" -Action $action -User "vagrant" -Password "vagrant" -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName "archive"
Write-Host "archive task started (local tar; no network)"
