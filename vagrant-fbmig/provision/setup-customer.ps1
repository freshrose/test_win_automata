# setup-customer.ps1 -- "produkční" Avensio DB + účet UNI_OMEGA + bundle.
# Soubory z host shares kopírujeme JEDNORÁZOVĚ přes transientní `net use`
# (New-SmbGlobalMapping selhává v neinteraktivní WinRM session - error 1312).
$ErrorActionPreference = "Stop"

$gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } |
       Select-Object -First 1).IPv4DefaultGateway.NextHop
if (-not $gw) { throw "nelze zjistit host (gateway) IP" }
Write-Host "host (gateway): $gw"

# --- transientní připojení host shares (explicitní creds, žádný global mapping) ---
cmd /c "net use \\$gw\avensio-db /user:avensio_smb avensio26A" 2>&1 | Out-Host
cmd /c "net use \\$gw\avensio-automata /user:avensio_smb avensio26A" 2>&1 | Out-Host
try {
  # --- 1) lokální produkční DB (kopie SKOLA_test.FDB) ---
  New-Item -ItemType Directory -Force "C:\AvensioData" | Out-Null
  Copy-Item "\\$gw\avensio-db\SKOLA_test.FDB" "C:\AvensioData\avensio.fdb" -Force
  Write-Host "produkční DB: C:\AvensioData\avensio.fdb"

  # --- 4) rozbal migrační bundle ze share ---
  $zip = "\\$gw\avensio-automata\vagrant-fbmig\migrate-bundle.zip"
  if (Test-Path "C:\migrate") { Remove-Item "C:\migrate" -Recurse -Force }
  Expand-Archive $zip -DestinationPath "C:\migrate"
  Write-Host ("bundle rozbalen do C:\migrate (" + (Get-ChildItem C:\migrate -Recurse -File).Count + " souborů)")
}
finally {
  cmd /c "net use \\$gw\avensio-db /delete" 2>&1 | Out-Null
  cmd /c "net use \\$gw\avensio-automata /delete" 2>&1 | Out-Null
}

# --- 2) účet UNI_OMEGA/omega ve FB2.5 (jako u zákazníka) ---
$gsec = Get-ChildItem "C:\Program Files*\Firebird\*\bin\gsec.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
if ($gsec) {
  & $gsec -user sysdba -password masterkey -add UNI_OMEGA -pw omega 2>&1 | Out-Host
  Write-Host "UNI_OMEGA založen ($gsec)"
} else { Write-Host "VAROVÁNÍ: gsec.exe nenalezen" }

# --- 3) avensio.ini (realismus; test ale použije --src) ---
New-Item -ItemType Directory -Force "C:\Avensio" | Out-Null
@"
[ORGANIZACE1]
NAZEV1=ZAKAZNIK_TEST (05.2026)
FileDB=C:\AvensioData\avensio.fdb
hidden=0
"@ | Set-Content "C:\Avensio\avensio.ini" -Encoding ASCII

Write-Host ""
Write-Host "=== ZAKAZNIK PRIPRAVEN ==="
Write-Host "Migrace:  C:\migrate\avensioMigrate.exe --src C:\AvensioData\avensio.fdb"
