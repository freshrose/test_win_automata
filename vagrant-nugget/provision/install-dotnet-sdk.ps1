<#
  install-dotnet-sdk.ps1 -- .NET 10 SDK 10.0.401 (same installer winget used on the host).
  Pure ASCII.
#>
$ErrorActionPreference = "Stop"
if ((Test-Path "C:\Program Files\dotnet\dotnet.exe") -and ((& "C:\Program Files\dotnet\dotnet.exe" --list-sdks) -match "^10\.0\.401")) {
  Write-Host ".NET SDK 10.0.401 already present."; exit 0
}
$ProgressPreference = "SilentlyContinue"
New-Item -ItemType Directory -Force C:\setup | Out-Null
$exe = "C:\setup\dotnet-sdk-10.0.401-win-x64.exe"
Invoke-WebRequest "https://download.microsoft.com/download/52d16011-1aa2-4a7e-a4be-769e1bdd32be/0b34e693-1985-449e-9c33-e32b7c3538e6/dotnet-sdk-10.0.401-win-x64.exe" -OutFile $exe -UseBasicParsing
$p = Start-Process $exe -ArgumentList "/install /quiet /norestart" -Wait -PassThru
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw ".NET SDK install failed: $($p.ExitCode)" }
Write-Host ".NET SDK installed (exit $($p.ExitCode))."
