<#
  install-iis.ps1 -- IIS + ASP.NET 4.8, same feature set as the host.
  Pure ASCII (PS reads .ps1 as ANSI).
#>
$ErrorActionPreference = "Stop"
$f = 'IIS-WebServerRole','IIS-WebServer','IIS-CommonHttpFeatures','IIS-DefaultDocument',
     'IIS-StaticContent','IIS-HttpErrors','IIS-RequestFiltering','IIS-NetFxExtensibility45',
     'IIS-ISAPIExtensions','IIS-ISAPIFilter','IIS-ASPNET45','NetFx4Extended-ASPNET45',
     'IIS-ManagementConsole','IIS-HttpLogging'
Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart | Out-Null
Write-Host "IIS + ASP.NET 4.8 enabled."
