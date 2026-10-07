<#
  push-assign.host.ps1 -- deliver one inbox event to a worker VM over PowerShell
  Direct (VMBus), since the host firewall scopes SMB to the Netbird overlay and the
  worker reads a VM-LOCAL inbox.

  Appends one NDJSON event to C:\automata\io\<Worker>\inbox.ndjson inside the VM.
  The operator's polling watcher (re-reads + tracks line count) picks it up.

  Event kinds (see agents/test-operator.md):
    bootstrap  -- issue context only; operator acknowledges, no action (safe ping)
    assign     -- a build is ready to test: needs a REAL YouTrack issue (the operator
                  calls yt_claim/yt_set_state/yt_get_issue), drives avensio, reports.
    comment    -- a human message on the issue; operator treats as instructions.

  Run on the HOST (elevated).

  Examples:
    # safe delivery ping:
    .\push-assign.host.ps1 -Kind bootstrap -Issue D2010-SMOKE -Body "delivery test"
    # real reference run against an existing issue:
    .\push-assign.host.ps1 -Kind assign -Issue AVE-12 -Build d2010-ref -Body "run payroll scenario"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('assign','comment','bootstrap')] [string] $Kind,
  [string] $Issue = '',
  [string] $Build = '',
  [string] $Body  = '',
  [string] $VMName    = 'avensio-d2010-test1',
  [string] $Worker    = 'd2010-test1',
  [string] $GuestUser = 'vagrant',
  [string] $GuestPass = 'vagrant'
)
$ErrorActionPreference = 'Stop'
$cred = New-Object System.Management.Automation.PSCredential(
  $GuestUser, (ConvertTo-SecureString $GuestPass -AsPlainText -Force))
$s = New-PSSession -VMName $VMName -Credential $cred
try {
  $evt = Invoke-Command -Session $s -ArgumentList $Worker,$Kind,$Issue,$Build,$Body -ScriptBlock {
    param($Worker,$Kind,$Issue,$Build,$Body)
    $inbox = "C:\automata\io\$Worker\inbox.ndjson"
    New-Item -ItemType Directory -Force -Path (Split-Path $inbox) | Out-Null
    if (-not (Test-Path $inbox)) { New-Item -ItemType File -Path $inbox | Out-Null }
    $n = ([IO.File]::ReadAllLines($inbox) | Measure-Object).Count
    $obj = [ordered]@{ id = $n + 1; kind = $Kind }
    if ($Issue) { $obj['issue'] = $Issue }
    if ($Build) { $obj['build'] = $Build }
    if ($Body)  { $obj['body']  = $Body }
    $json = $obj | ConvertTo-Json -Compress
    # append like the orchestrator (UTF-8, LF); the polling watcher re-reads by line.
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::AppendAllText($inbox, $json + "`n", $enc)
    $json
  }
  Write-Host "delivered -> $Worker inbox: $evt"
}
finally { Remove-PSSession $s }
