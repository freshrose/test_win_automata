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

# Legacy InterBase client gds32.dll: the OLD (Delphi 2010) avensio talks to the DB
# via IBX (gds32.dll), NOT FireDAC like the D13 build. Without it avensio dies with
# "EIBClientError ... InterBase library gds32.dll not found". Firebird's fbclient.dll
# is gds32-compatible -> copy it as gds32.dll into the WOW64 system dir (avensio is
# 32-bit). (The exe-dir copy is staged with the build.)
$fbclient = Get-ChildItem 'C:\Program Files (x86)\Firebird','C:\Program Files\Firebird' -Recurse -Filter fbclient.dll -ErrorAction SilentlyContinue | Select-Object -First 1
if ($fbclient) {
  Copy-Item $fbclient.FullName 'C:\Windows\SysWOW64\gds32.dll' -Force -ErrorAction SilentlyContinue
  Write-Host "gds32.dll (legacy IB client) installed from $($fbclient.FullName)"
} else {
  Write-Host "WARN: fbclient.dll not found -- gds32.dll not created (avensio DB connect will fail)"
}

# .FDB templates are staged via PowerShell Direct (see vagrant-d2010 host scripts).
Write-Host "Firebird ready (service Running)."
