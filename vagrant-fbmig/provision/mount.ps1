# mount.ps1 -- namapuj host shares (avensio-db, avensio-automata) machine-wide.
# Host = default gateway na Hyper-V Default Switch. Stejné creds jako vagrant/ setup.
$ErrorActionPreference = "Stop"

$gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } |
       Select-Object -First 1).IPv4DefaultGateway.NextHop
if (-not $gw) { throw "nelze zjistit host (gateway) IP" }
Write-Host "host (gateway): $gw"

$sec  = ConvertTo-SecureString "avensio26A" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("avensio_smb", $sec)

$maps = @(
  @{ share = "avensio-db";       link = "C:\db_share" },
  @{ share = "avensio-automata"; link = "C:\automata" }
)
foreach ($m in $maps) {
  $remote = "\\$gw\$($m.share)"
  Get-SmbGlobalMapping -RemotePath $remote -ErrorAction SilentlyContinue |
    Remove-SmbGlobalMapping -Force -ErrorAction SilentlyContinue
  New-SmbGlobalMapping -RemotePath $remote -Credential $cred -Persistent $true -RequirePrivacy $true | Out-Null
  if (Test-Path $m.link) { cmd /c rmdir "$($m.link)" 2>$null }
  cmd /c mklink /D "$($m.link)" "$remote" | Out-Null
  Write-Host "mapped $remote -> $($m.link)"
}
