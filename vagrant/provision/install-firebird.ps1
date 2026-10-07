<#
  install-firebird.ps1 -- Firebird 2.5 server in the test VM.
  avensio connects via FireDAC TCPIP 127.0.0.1:3050, user sysdba / pass masterkey,
  charset WIN1250 (baseDMC.pas). The .FDB templates are copied from the synced
  folder so each test can clone a fresh DB locally (no host round-trip per test).
  Pure ASCII.

  NOTE (verify on first run): exact Firebird 2.5 installer URL/version. 2.5 chosen
  to match the production engine (avensio-e2e-pipeline memory). Silent install flags
  are Inno Setup style.
#>
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tmp = "C:\Windows\Temp"

$svc = Get-Service -Name "FirebirdServerDefaultInstance" -ErrorAction SilentlyContinue
if (-not $svc) {
  $fb = "$tmp\firebird-2.5.exe"
  if (-not (Test-Path $fb)) {
    Invoke-WebRequest -UseBasicParsing -OutFile $fb `
      -Uri "https://github.com/FirebirdSQL/firebird/releases/download/R2_5_9/Firebird-2.5.9.27139_0_Win32.exe"
  }
  # Inno Setup silent: install as a service, classic->super, no reboot.
  Start-Process $fb -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /TASKS=`"UseServiceTask`"" -Wait
}
Start-Service "FirebirdServerDefaultInstance" -ErrorAction SilentlyContinue
$svc = Get-Service -Name "FirebirdServerDefaultInstance" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") { throw "Firebird service not running after install" }
# .FDB templates are staged by mount-shares.ps1 (from the avensio-db share).
Write-Host "Firebird ready (service Running)."
