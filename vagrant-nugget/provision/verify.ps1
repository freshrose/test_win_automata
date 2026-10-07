<#
  verify.ps1 -- report the installed toolchain (runs on every `vagrant up/provision`).
  Pure ASCII.
#>
Write-Host "HOSTNAME=$env:COMPUTERNAME"
Write-Host ("NETFX_RELEASE=" + (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release)
Write-Host ("IIS_W3SVC=" + (Get-Service W3SVC -ErrorAction SilentlyContinue).Status)
Write-Host ("ASPNET45=" + (Get-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET45).State)
if (Test-Path "C:\Program Files\dotnet\dotnet.exe") { Write-Host ("DOTNET_SDKS=" + ((& "C:\Program Files\dotnet\dotnet.exe" --list-sdks) -join "; ")) } else { Write-Host "DOTNET_SDKS=none" }
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
  Write-Host ("VS=" + (& $vswhere -all -property displayName) + " " + (& $vswhere -all -property installationVersion))
  $req = "Microsoft.VisualStudio.Workload.NetWeb","Microsoft.Net.Component.4.8.TargetingPack","Microsoft.Net.Component.4.8.1.TargetingPack","Microsoft.Net.Component.4.8.SDK","Microsoft.VisualStudio.Component.Wcf.Tooling"
  Write-Host ("VS_COMPONENTS_OK=" + [bool](& $vswhere -all -requires $req -property instanceId))
  $msb = & $vswhere -all -find "MSBuild\Current\Bin\MSBuild.exe" | Select-Object -First 1
  if ($msb) { Write-Host ("MSBUILD=" + (& $msb -version -nologo)) }
} else { Write-Host "VS=none" }
Write-Host ("ASPNET_COMPILER=" + (Test-Path "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\aspnet_compiler.exe"))
Write-Host ("C_FREE_GB=" + [math]::Round((Get-PSDrive C).Free/1GB,1))
