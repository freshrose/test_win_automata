<#
.SYNOPSIS
  Provision a fresh, isolated avensio test database for one e2e run.

.DESCRIPTION
  Each parallel test needs its own .FDB (Firebird locks the file). This script:
    1. Copies a template .FDB to a unique per-run path.
    2. Writes an avensio.ini NEXT TO the exe with a single ORGANIZACE1 section
       pointing FileDB at that fresh copy.
  Avensio reads its organization list from avensio.ini in the exe directory
  (verified in Phase 0 spike: a missing ini -> "Nelze nacist seznam organizaci").
  The ini keys are exactly NAZEV1 / FileDB / hidden (baseEnvC.pas).

  Pure ASCII on purpose (PS 5.1 reads .ps1 as ANSI; see windows-powershell-gotchas).

.EXAMPLE
  .\provision-test-db.ps1 -RunId AVE-12-a1b2c3 -TemplateFdb C:\Users\rosa\DB\_templates\SKOLA_test.FDB
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $RunId,
  [Parameter(Mandatory)] [string] $TemplateFdb,
  # ExeDir: the D2010 reference worker sets AVENSIO_EXEDIR (machine env) to its
  # staged legacy build; unset -> D13 default. avensio.ini is written here.
  [string] $ExeDir   = $(if ($env:AVENSIO_EXEDIR) { $env:AVENSIO_EXEDIR } else { "C:\Users\rosa\_rsm\avensio\__bin" }),
  [string] $DbDir    = "C:\Users\rosa\DB\_runs",
  [string] $OrgLabel = "TEST"
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $TemplateFdb)) { throw "Template .FDB not found: $TemplateFdb" }
if (-not (Test-Path $ExeDir))      { throw "Exe dir not found: $ExeDir" }
New-Item -ItemType Directory -Force -Path $DbDir | Out-Null

# 1. fresh per-run copy of the database
$freshFdb = Join-Path $DbDir ("{0}.FDB" -f $RunId)
Copy-Item -LiteralPath $TemplateFdb -Destination $freshFdb -Force
Write-Host "DB  : $freshFdb"

# 2. avensio.ini next to the exe, single org -> fresh DB
$iniPath = Join-Path $ExeDir "avensio.ini"
$lines = @(
  "[ORGANIZACE1]",
  ("NAZEV1={0} ({1})" -f $OrgLabel, $RunId),
  ("FileDB={0}" -f $freshFdb),
  "hidden=0"
)
# ANSI/Win-1250 is what avensio expects for the ini; ASCII content here is safe in both.
[System.IO.File]::WriteAllLines($iniPath, $lines, [System.Text.Encoding]::Default)
Write-Host "INI : $iniPath"

# emit a small JSON result for the caller (orchestrator / agent)
[pscustomobject]@{
  runId   = $RunId
  fdb     = $freshFdb
  ini     = $iniPath
  org     = "$OrgLabel ($RunId)"
} | ConvertTo-Json -Compress
