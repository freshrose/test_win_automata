# Full-featured session-N GUI action runner: posts an arbitrary act JSON to
# C:\avensio\_act.json and triggers the `vmact` scheduled task, then pulls the
# resulting screen capture to the host.
#
# act-runner.ps1 understands: fg, wclose, dlg2, probe, dlgbtn, kill, launch,
# x/y/count/right, x2/y2/count2, keys, wait.  vmact.ps1 only exposes the click
# subset -- this one passes anything.
#
# Pure ASCII (PS 5.1 reads .ps1 as ANSI).
param(
  [Parameter(Mandatory)][string]$ActJson,
  [string]$Save = '',                       # host path to copy the capture to
  [int]$SettleSec = 6,
  [string]$VMName = 'avensio-test1'
)
$ErrorActionPreference = 'Stop'
$cred = New-Object System.Management.Automation.PSCredential('vagrant', (ConvertTo-SecureString 'vagrant' -AsPlainText -Force))
$s = New-PSSession -VMName $VMName -Credential $cred
try {
  Invoke-Command -Session $s -ArgumentList $ActJson -ScriptBlock {
    param($act)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText('C:\avensio\_act.json', $act, $enc)
    New-Item -ItemType Directory -Force 'C:\avensio\shots' | Out-Null
    schtasks /Run /TN vmact 2>&1 | Out-Null
  }
  Start-Sleep -Seconds $SettleSec
  if ($Save) {
    New-Item -ItemType Directory -Force (Split-Path $Save) | Out-Null
    Copy-Item -FromSession $s -Path 'C:\avensio\shots\_screen.png' -Destination $Save -Force
    Write-Host "saved -> $Save"
  }
  # surface the probe output when one was requested
  if ($ActJson -match '"probe"') {
    Invoke-Command -Session $s -ScriptBlock { Get-Content 'C:\avensio\_probe.txt' -ErrorAction SilentlyContinue }
  }
} finally { Remove-PSSession $s }
