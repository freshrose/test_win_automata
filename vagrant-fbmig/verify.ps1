# verify.ps1 -- ověření stavu PO migraci (běží uvnitř VM).
$ErrorActionPreference = "Continue"
Write-Host "=== Firebird služby ==="
Get-Service | Where-Object { $_.Name -like "Firebird*" } | ForEach-Object {
  $bin = (Get-CimInstance Win32_Service -Filter ("Name='" + $_.Name + "'")).PathName
  Write-Host ("{0,-32} {1,-9} {2}" -f $_.Name, $_.Status, $bin)
}

Write-Host ""
Write-Host "=== TCP 3050 listener ==="
$t = Get-NetTCPConnection -LocalPort 3050 -State Listen -ErrorAction SilentlyContinue
if ($t) { Write-Host "naslouchá na 3050 (PID $($t[0].OwningProcess))" } else { Write-Host "nikdo nenaslouchá na 3050" }

Write-Host ""
Write-Host "=== UNI_OMEGA -> migrovaná DB přes FB5 službu (jako Avensio) ==="
$q = "C:\migrate\_v.sql"
Set-Content $q "SELECT rdb`$get_context('SYSTEM','ENGINE_VERSION') AS ENGINE FROM rdb`$database;" -Encoding ASCII
& "C:\migrate\fb50\isql.exe" -user UNI_OMEGA -password omega -i $q "localhost:C:\AvensioData\avensio.fdb" 2>&1 | Out-Host
Write-Host ("isql exit=" + $LASTEXITCODE)

Write-Host ""
Write-Host "=== soubory v C:\AvensioData (avensio.fdb + .bak25 záloha) ==="
Get-ChildItem C:\AvensioData | ForEach-Object { Write-Host ("{0,-28} {1,12:N0} B" -f $_.Name, $_.Length) }
