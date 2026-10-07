<#
.SYNOPSIS
  Start or force-stop avensio.exe for an e2e run.

.DESCRIPTION
  Thin lifecycle helper around the built avensio.exe. The delphi_vcl MCP drives
  the GUI; this script only handles start and the hard cleanup.

  CLEANUP IS CRITICAL: WM_CLOSE (delphi_close_app) does NOT terminate avensio at
  the login form -- a leftover process keeps __bin\avensio.exe locked and breaks
  the next build/launch (Phase 0 spike + avensio-container-build memory).
  Always force-stop by PID/name.

  Pure ASCII (PS 5.1 reads .ps1 as ANSI).

.EXAMPLE
  .\run-avensio.ps1 -Action start
  .\run-avensio.ps1 -Action stop
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [ValidateSet("start","stop")] [string] $Action,
  # ExeDir selects the avensio build under test. The D2010 reference worker sets
  # AVENSIO_EXEDIR (machine env) to its staged legacy build; unset -> D13 default.
  [string] $ExeDir = $(if ($env:AVENSIO_EXEDIR) { $env:AVENSIO_EXEDIR } else { "C:\Users\rosa\_rsm\avensio\__bin" })
)
$ErrorActionPreference = "Stop"
$exe = Join-Path $ExeDir "avensio.exe"

function Stop-Avensio {
  $procs = Get-Process -Name avensio -ErrorAction SilentlyContinue
  if ($procs) {
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
  }
  $left = Get-Process -Name avensio -ErrorAction SilentlyContinue
  if ($left) { throw "avensio still running after force-stop: $($left.Id -join ',')" }
}

switch ($Action) {
  "stop" {
    Stop-Avensio
    Write-Host "avensio stopped; exe unlocked."
  }
  "start" {
    if (-not (Test-Path $exe)) { throw "avensio.exe not found: $exe" }
    if (-not (Test-Path (Join-Path $ExeDir "avensio.ini"))) {
      throw "avensio.ini missing in $ExeDir -- run provision-test-db.ps1 first."
    }
    # ensure a clean slate (a stale instance would lock the exe)
    Stop-Avensio
    $p = Start-Process -FilePath $exe -WorkingDirectory $ExeDir -PassThru
    Write-Host "avensio started, PID $($p.Id)"
    [pscustomobject]@{ pid = $p.Id; exe = $exe } | ConvertTo-Json -Compress
  }
}
