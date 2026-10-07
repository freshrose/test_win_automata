<#
  stage-d2010-build.host.ps1 -- push the legacy (Delphi 2010) avensio build into the
  d2010 worker VM over PowerShell Direct (VMBus), the SAME control/file-transfer
  channel used for avensio-test1. No SMB / no host firewall change: the overlay-only
  SMB posture stays intact.

  Run on the HOST (elevated). Re-run after every D2010 rebuild to refresh the SUT.

  Usage:
    powershell -ExecutionPolicy Bypass -File .\stage-d2010-build.host.ps1
#>
[CmdletBinding()]
param(
  [string] $VMName  = "avensio-d2010-test1",
  [string] $BuildRoot = "C:\Users\rosa\_rsm\var-D2010\avensio\avensio",  # has __bin\avensio.exe + reporty/skripty/set
  [string] $ExeDir  = "C:\avensio-d2010\__bin",                          # VM-local target
  [string] $GuestUser = "vagrant",
  [string] $GuestPass = "vagrant"
)
$ErrorActionPreference = "Stop"

$exe = Join-Path $BuildRoot "__bin\avensio.exe"
if (-not (Test-Path $exe)) { throw "avensio.exe not found: $exe (build it first)" }

$cred = New-Object System.Management.Automation.PSCredential(
  $GuestUser, (ConvertTo-SecureString $GuestPass -AsPlainText -Force))
$s = New-PSSession -VMName $VMName -Credential $cred
try {
  Invoke-Command -Session $s -ScriptBlock { param($d) New-Item -ItemType Directory -Force -Path $d | Out-Null } -ArgumentList $ExeDir

  Write-Host "push avensio.exe ..."
  Copy-Item $exe -Destination "$ExeDir\" -ToSession $s -Force

  foreach ($d in @("reporty","skripty","set")) {
    $srcDir = Join-Path $BuildRoot $d
    if (Test-Path $srcDir) {
      Write-Host "push $d\ ..."
      Copy-Item $srcDir -Destination "$ExeDir\" -ToSession $s -Recurse -Force
    }
  }

  $info = Invoke-Command -Session $s -ScriptBlock {
    param($d)
    [Environment]::SetEnvironmentVariable("AVENSIO_EXEDIR", $d, "Machine")
    if (-not (Test-Path (Join-Path $d 'avensio.exe'))) { throw "avensio.exe missing after stage" }
    [pscustomobject]@{
      exe    = (Get-Item (Join-Path $d 'avensio.exe')).Length
      dirs   = (Get-ChildItem $d -Directory).Name -join ', '
      exedir = [Environment]::GetEnvironmentVariable('AVENSIO_EXEDIR','Machine')
    }
  } -ArgumentList $ExeDir
  Write-Host ("staged OK: avensio.exe={0:N0} bytes; resources=[{1}]; AVENSIO_EXEDIR={2}" -f $info.exe,$info.dirs,$info.exedir)
}
finally { Remove-PSSession $s }
