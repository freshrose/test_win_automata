<#
  stage-host.ps1 -- (runs over WinRM) registers a scheduled task that runs as
  vagrant with a STORED PASSWORD (batch logon => real logon session), so
  New-SmbGlobalMapping works without depending on an interactive autologon
  desktop (WinRM's own network session hits Windows error 1312). Then starts the
  task and waits for the installer to be staged locally.
  Pure ASCII.
#>
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force C:\delphi-setup | Out-Null

$mount = @'
$ErrorActionPreference = "Stop"
$log = "C:\delphi-setup\mount.log"
"=== mount-host run $(Get-Date -Format s) ===" | Out-File $log -Append -Encoding ascii
try {
  $gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } |
         Select-Object -First 1).IPv4DefaultGateway.NextHop
  $sec  = ConvertTo-SecureString "avensio26A" -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential("avensio_smb", $sec)
  $remote = "\\$gw\delphi-share"
  Get-SmbGlobalMapping -RemotePath $remote -ErrorAction SilentlyContinue | Remove-SmbGlobalMapping -Force -ErrorAction SilentlyContinue
  New-SmbGlobalMapping -RemotePath $remote -Credential $cred -Persistent $true -RequirePrivacy $true | Out-Null
  if (Test-Path C:\host) { cmd /c rmdir C:\host 2>$null }
  cmd /c mklink /D C:\host $remote | Out-Null
  New-Item -ItemType Directory -Force "$remote\out" | Out-Null
  if (-not (Test-Path C:\delphi-setup\setup.exe)) { Copy-Item "$remote\in\setup.exe" C:\delphi-setup\setup.exe -Force }
  $ws = New-Object -ComObject WScript.Shell
  $lnk = $ws.CreateShortcut("C:\Users\Public\Desktop\Install Delphi 13.1.lnk")
  $lnk.TargetPath = "C:\delphi-setup\setup.exe"; $lnk.Save()
  "OK host=$gw setup=$(Test-Path C:\delphi-setup\setup.exe)" | Out-File $log -Append -Encoding ascii
} catch {
  "ERROR: $($_.Exception.Message)" | Out-File $log -Append -Encoding ascii
}
'@
Set-Content -Path C:\delphi-setup\mount-host.ps1 -Value $mount -Encoding ascii

$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\delphi-setup\mount-host.ps1"
$trigger = New-ScheduledTaskTrigger -AtLogOn
# stored-password principal => batch logon session (not the WinRM network session)
Register-ScheduledTask -TaskName "mount-host" -Action $action -Trigger $trigger `
  -User "vagrant" -Password "vagrant" -RunLevel Highest -Force | Out-Null
Write-Host "registered task 'mount-host' (vagrant batch logon)"

Start-ScheduledTask -TaskName "mount-host"
$deadline = (Get-Date).AddSeconds(180)
while ((Get-Date) -lt $deadline -and -not (Test-Path C:\delphi-setup\setup.exe)) { Start-Sleep -Seconds 5 }
Write-Host "setup staged: $(Test-Path C:\delphi-setup\setup.exe) ; host map: $(Test-Path C:\host)"
