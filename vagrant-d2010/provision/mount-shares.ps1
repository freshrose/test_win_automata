<#
  mount-shares.ps1 -- machine-wide access to the host shares from inside the VM.

  vagrant's per-session SMB mount gave "Access denied" from other sessions
  (a logon-at-task runs in a different session). New-SmbGlobalMapping with stored
  creds is machine-wide and persistent, so the bootstrap scheduled task and the
  interactive desktop both see it. Symlinks keep the existing C:\automata paths
  (and /c/automata in Git Bash) working unchanged.

  Pure ASCII.
#>
$ErrorActionPreference = "Stop"

# the VM's default gateway on the Hyper-V Default Switch IS the host.
$gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } |
       Select-Object -First 1).IPv4DefaultGateway.NextHop
if (-not $gw) { throw "could not determine host (default gateway) IP" }
Write-Host "host (gateway): $gw"

$sec  = ConvertTo-SecureString "avensio26A" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("avensio_smb", $sec)

$maps = @(
  @{ share = "avensio-automata"; link = "C:\automata" },
  @{ share = "avensio-db";       link = "C:\db_share" }
)
foreach ($m in $maps) {
  $remote = "\\$gw\$($m.share)"
  Get-SmbGlobalMapping -RemotePath $remote -ErrorAction SilentlyContinue | Remove-SmbGlobalMapping -Force -ErrorAction SilentlyContinue
  New-SmbGlobalMapping -RemotePath $remote -Credential $cred -Persistent $true -RequirePrivacy $true | Out-Null
  if (Test-Path $m.link) { cmd /c rmdir "$($m.link)" 2>$null }
  cmd /c mklink /D "$($m.link)" "$remote" | Out-Null
  Write-Host "mapped $remote -> $($m.link)"
}

# stage .FDB templates locally (clone per test at run time from here)
New-Item -ItemType Directory -Force -Path "C:\DB\_templates","C:\DB\_runs" | Out-Null
Copy-Item "C:\db_share\SKOLA_test.FDB" "C:\DB\_templates\" -Force
Write-Host "templates staged: " + ((Get-ChildItem 'C:\DB\_templates\*.FDB' | Measure-Object).Count)
