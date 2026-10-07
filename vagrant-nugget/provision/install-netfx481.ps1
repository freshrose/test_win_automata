<#
  install-netfx481.ps1 -- .NET Framework 4.8.1 runtime (Win10 22H2 ships 4.8).
  Release key >= 533320 means 4.8.1 is present. Pure ASCII.
#>
$ErrorActionPreference = "Stop"
$rel = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release
if ($rel -ge 533320) { Write-Host "NetFx 4.8.1 already present ($rel)."; exit 0 }
$ProgressPreference = "SilentlyContinue"
New-Item -ItemType Directory -Force C:\setup | Out-Null
$exe = "C:\setup\ndp481-x86-x64-allos-enu.exe"
Invoke-WebRequest "https://go.microsoft.com/fwlink/?linkid=2203305" -OutFile $exe -UseBasicParsing
$p = Start-Process $exe -ArgumentList "/q /norestart" -Wait -PassThru
# 3010 = success, reboot required
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "NetFx 4.8.1 install failed: $($p.ExitCode)" }
Write-Host "NetFx 4.8.1 installed (exit $($p.ExitCode))."
