# install-fb25.ps1 -- Firebird 2.5.9 jako Windows služba (simulace zákazníka).
# Stejný postup jako vagrant/provision/install-firebird.ps1.
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
  Start-Process $fb -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /TASKS=`"UseServiceTask`"" -Wait
}
Start-Service "FirebirdServerDefaultInstance" -ErrorAction SilentlyContinue
$svc = Get-Service -Name "FirebirdServerDefaultInstance" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") { throw "FB2.5 služba neběží po instalaci" }
Write-Host "FB2.5 služba běží."
