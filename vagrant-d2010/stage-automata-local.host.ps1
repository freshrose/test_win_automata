<#
  stage-automata-local.host.ps1 -- give avensio-d2010-test1 a LOCAL C:\automata
  mirror of the __automata parts the in-VM claude operator needs (no SMB).

  The operator (agent_pty -> claude --mcp-config C:\automata\mcp\agent-mcp.json) and
  test-operator.md reference C:\automata\... . The host firewall scopes SMB to the
  Netbird overlay, so we cannot mount the share; instead we copy the needed subset
  VM-local over PowerShell Direct:
     C:\automata\mcp\         agent-mcp.json, yt_mcp.py
     C:\automata\orchestrator yt_client.py   (yt_mcp imports it; reads ../config/auth.env)
     C:\automata\config\      auth.env        (YouTrack creds)
     C:\automata\agents\      run-avensio.ps1, screencap.ps1, ... (operator helpers)
     C:\automata\db\          provision-test-db.ps1
     C:\automata\scenarios\   test scenarios
     C:\automata\io\<worker>\ inbox.ndjson   (assignments; host appends via PSDirect)
     C:\automata\delphi_vcl_mcp.py
  yt_mcp resolves auth.env as parents[1]/config/auth.env, so the layout above makes
  the YouTrack MCP work unchanged.

  Run on the HOST (elevated). Idempotent. Re-run after editing scenarios/auth.
#>
[CmdletBinding()]
param(
  [string] $VMName    = "avensio-d2010-test1",
  [string] $Worker    = "d2010-test1",
  [string] $Automata  = "C:\Users\rosa\_rsm\__automata",
  [string] $GuestUser = "vagrant",
  [string] $GuestPass = "vagrant"
)
$ErrorActionPreference = "Stop"
$cred = New-Object System.Management.Automation.PSCredential(
  $GuestUser, (ConvertTo-SecureString $GuestPass -AsPlainText -Force))
$s = New-PSSession -VMName $VMName -Credential $cred
try {
  # make C:\automata a REAL local dir (drop any dead SMB symlink), create subdirs
  Invoke-Command -Session $s -ArgumentList $Worker -ScriptBlock {
    param($Worker)
    $a = 'C:\automata'
    $it = Get-Item $a -ErrorAction SilentlyContinue
    if ($it -and ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)) { cmd /c rmdir "$a" | Out-Null }
    foreach ($d in 'mcp','orchestrator','config','agents','db','scenarios','runs',"io\$Worker") {
      New-Item -ItemType Directory -Force -Path (Join-Path $a $d) | Out-Null
    }
    $inbox = Join-Path $a "io\$Worker\inbox.ndjson"
    if (-not (Test-Path $inbox)) { New-Item -ItemType File -Path $inbox | Out-Null }
  }

  # push files (UNC-free, over VMBus)
  $copies = @(
    @{ src="$Automata\mcp\agent-mcp.json";          dst='C:\automata\mcp\agent-mcp.json' },
    @{ src="$Automata\mcp\yt_mcp.py";               dst='C:\automata\mcp\yt_mcp.py' },
    @{ src="$Automata\orchestrator\yt_client.py";   dst='C:\automata\orchestrator\yt_client.py' },
    @{ src="$Automata\config\auth.env";             dst='C:\automata\config\auth.env' },
    @{ src="$Automata\db\provision-test-db.ps1";    dst='C:\automata\db\provision-test-db.ps1' },
    @{ src="$Automata\delphi_vcl_mcp.py";           dst='C:\automata\delphi_vcl_mcp.py' }
  )
  foreach ($c in $copies) {
    if (-not (Test-Path $c.src)) { throw "missing source: $($c.src)" }
    Copy-Item $c.src -Destination $c.dst -ToSession $s -Force
    Write-Host "pushed -> $($c.dst)"
  }
  # whole dirs
  foreach ($d in 'agents','scenarios') {
    if (Test-Path "$Automata\$d") {
      Copy-Item "$Automata\$d\*" -Destination "C:\automata\$d\" -ToSession $s -Recurse -Force
      Write-Host "pushed dir -> C:\automata\$d\"
    }
  }

  # verify the operator's prerequisites
  $chk = Invoke-Command -Session $s -ArgumentList $Worker -ScriptBlock {
    param($Worker)
    [pscustomobject]@{
      agentmcp = Test-Path 'C:\automata\mcp\agent-mcp.json'
      ytmcp    = Test-Path 'C:\automata\mcp\yt_mcp.py'
      ytclient = Test-Path 'C:\automata\orchestrator\yt_client.py'
      authenv  = Test-Path 'C:\automata\config\auth.env'
      inbox    = Test-Path "C:\automata\io\$Worker\inbox.ndjson"
    }
  }
  Write-Host ("prereqs: agent-mcp={0} yt_mcp={1} yt_client={2} auth.env={3} inbox={4}" -f `
    $chk.agentmcp,$chk.ytmcp,$chk.ytclient,$chk.authenv,$chk.inbox)
}
finally { Remove-PSSession $s }
