<#
  install-vs.ps1 -- Visual Studio Enterprise 2026 (current 18.x stable channel)
  with the same workload/components as the host. Licensing = sign in inside the VM.
  Pure ASCII.
#>
$ErrorActionPreference = "Stop"
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if ((Test-Path $vswhere) -and (& $vswhere -products Microsoft.VisualStudio.Product.Enterprise -version "[18.0,19.0)" -property installationPath)) {
  Write-Host "VS Enterprise 2026 already installed."; exit 0
}
$ProgressPreference = "SilentlyContinue"
New-Item -ItemType Directory -Force C:\setup | Out-Null
$exe = "C:\setup\vs_enterprise.exe"
Invoke-WebRequest "https://aka.ms/vs/18/stable/vs_enterprise.exe" -OutFile $exe -UseBasicParsing
$vsArgs = @(
  "--quiet", "--wait", "--norestart",
  "--add", "Microsoft.VisualStudio.Workload.NetWeb",
  "--add", "Microsoft.Net.Component.4.8.TargetingPack",
  "--add", "Microsoft.Net.Component.4.8.1.TargetingPack",
  "--add", "Microsoft.Net.Component.4.8.SDK",
  "--add", "Microsoft.VisualStudio.Component.Wcf.Tooling",
  "--includeRecommended"
)
$p = Start-Process $exe -ArgumentList $vsArgs -Wait -PassThru
# 3010 = success, reboot required
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
  Get-ChildItem $env:TEMP -Filter "dd_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Tail 40 | Write-Host
  throw "VS install failed: $($p.ExitCode)"
}
Write-Host "VS Enterprise 2026 installed (exit $($p.ExitCode))."
