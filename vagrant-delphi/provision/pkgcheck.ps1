<# pkgcheck.ps1 -- report which bundled Embarcadero packages avensio needs are
   present/missing in this (lean) install's Win32 release lib. Pure ASCII. #>
$lib = "C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\Win32\release"
$bin = "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin"
# bundled packages from avensio.dproj DCC_UsePackage (excludes DevExpress dx*/cx*, FastReport frx*/fs*)
$pkgs = @('vclx','vcl','vclimg','dbrtl','rtl','vcldb','TeeUI','TeeDB','Tee',
          'vclactnband','vcltouch','xmlrtl','dsnap','dsnapcon','adortl',
          'IndyCore','IndySystem','IndyProtocols','inet','VclSmp','vclie','inetdb','soaprtl')
$present=@(); $missing=@()
foreach ($p in $pkgs) {
  if (Test-Path (Join-Path $lib "$p.dcp")) { $present += $p } else { $missing += $p }
}
Write-Host ("PRESENT ($($present.Count)): " + ($present -join ', '))
Write-Host ("MISSING ($($missing.Count)): " + ($missing -join ', '))
Write-Host "--- IBX ---"
Write-Host ("ibxpress.dcp: " + (Test-Path (Join-Path $lib 'ibxpress.dcp')))
Write-Host ("IBX*.dcu count: " + (Get-ChildItem (Join-Path $lib 'IBX*.dcu') -ErrorAction SilentlyContinue).Count)
Write-Host ("legacy IBDatabase.dcu: " + (Test-Path (Join-Path $lib 'IBDatabase.dcu')))
Write-Host "--- TeeChart files actually in lib (any name) ---"
Get-ChildItem (Join-Path $lib '*ee*.dcp') -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
