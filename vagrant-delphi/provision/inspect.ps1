<# inspect.ps1 -- verify Delphi install, license, and locate registration. Pure ASCII. #>
$ErrorActionPreference = "Continue"
$studio = "C:\Program Files (x86)\Embarcadero\Studio\37.0"
$bin    = "$studio\bin"

Write-Host "=== install presence ==="
Write-Host "studio exists : $(Test-Path $studio)"
Write-Host "dcc32 : $(Test-Path "$bin\dcc32.exe")   dcc64 : $(Test-Path "$bin\dcc64.exe")"

Write-Host "=== dcc32 --version ==="
& "$bin\dcc32.exe" --version 2>&1 | Select-Object -First 2

Write-Host "=== real compile (proves license + RTL) ==="
$t = "C:\bt"
Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $t | Out-Null
Set-Content "$t\hello.dpr" -Encoding ascii -Value @'
program hello;
{$APPTYPE CONSOLE}
begin
  Writeln('compiled-ok');
end.
'@
Push-Location $t
& "$bin\dcc32.exe" -B -U"$studio\lib\Win32\release" hello.dpr 2>&1 | Select-Object -Last 5
Write-Host "compile exit: $LASTEXITCODE   exe present: $(Test-Path "$t\hello.exe")"
if (Test-Path "$t\hello.exe") { Write-Host ("run output: " + (& "$t\hello.exe")) }
Pop-Location

Write-Host "=== license / registration location ==="
Write-Host "-- slip/reg files under ProgramData --"
Get-ChildItem 'C:\ProgramData\Embarcadero' -Recurse -ErrorAction SilentlyContinue -Include *.slip,reg*.txt |
  Select-Object FullName,Length | Format-Table -AutoSize | Out-String
Write-Host "-- registry keys --"
Write-Host "HKLM\...\Embarcadero\BDS\37.0     : $(Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Embarcadero\BDS\37.0')"
Write-Host "HKCU\...\Embarcadero\BDS\37.0     : $(Test-Path 'HKCU:\SOFTWARE\Embarcadero\BDS\37.0')"
Write-Host "HKCU\...\Embarcadero\Personalities: $(Test-Path 'HKCU:\SOFTWARE\Embarcadero\BDS\37.0\Personalities')"
$lic = 'HKLM:\SOFTWARE\WOW6432Node\Embarcadero\Licenses'
Write-Host "HKLM Licenses key                 : $(Test-Path $lic)"

Write-Host "=== install tree size ==="
$sz = (Get-ChildItem $studio -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
Write-Host ("Studio 37.0 size: {0:N1} GB" -f ($sz/1GB))
