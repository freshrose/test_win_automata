<#
  setup-d2010-control.host.ps1 -- make avensio-d2010-test1 drivable EXACTLY like
  avensio-test1: host drives the VM over PowerShell Direct via vmrun.ps1 / vmact.ps1.

  Replicates test1's VM-local pieces (no SMB):
    C:\avensio\delphi_vcl_mcp.py   the FastMCP GUI server (pywinauto), :8765
    C:\avensio\dvcl.py             one-shot MCP client (vmrun.ps1 calls it)
    C:\avensio\act-runner.ps1      raw click/type + screenshot (vmact task target)
    C:\avensio\run-mcp.bat         MCP launcher (env + python), interactive session
    C:\avensio\run-agent.bat       claude agent launcher (agent_pty.py)
    scheduled tasks: delphi-mcp (AtLogon+on-demand), vmact (on-demand),
                     avensio-agent (AtLogon)  -- all InteractiveToken as vagrant
  Then starts the MCP in the interactive desktop session.

  Run on the HOST (elevated). Idempotent.
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
  # --- dirs ---
  Invoke-Command -Session $s -ScriptBlock {
    New-Item -ItemType Directory -Force -Path 'C:\avensio','C:\avensio\shots','C:\avensio\agent','C:\avensio\runs' | Out-Null
  }

  # --- push VM-local helper files ---
  $push = @{
    "$Automata\delphi_vcl_mcp.py"   = 'C:\avensio\delphi_vcl_mcp.py'
    "$Automata\agents\dvcl.py"      = 'C:\avensio\dvcl.py'
    "$Automata\agents\act-runner.ps1" = 'C:\avensio\act-runner.ps1'
    "$Automata\agents\agent_pty.py" = 'C:\avensio\agent_pty.py'
  }
  foreach ($src in $push.Keys) {
    if (-not (Test-Path $src)) { throw "missing source: $src" }
    Copy-Item $src -Destination $push[$src] -ToSession $s -Force
    Write-Host "pushed -> $($push[$src])"
  }

  # --- launcher bats + worker.txt (write in-guest, ASCII) ---
  Invoke-Command -Session $s -ArgumentList $Worker -ScriptBlock {
    param($Worker)
    $mcp = @"
@echo off
set DELPHI_MCP_API_KEY=anyone-can-vibe-now
set DELPHI_MCP_HOST=127.0.0.1
set DELPHI_MCP_PORT=8765
"C:\Program Files\Python312\python.exe" C:\avensio\delphi_vcl_mcp.py
"@
    Set-Content 'C:\avensio\run-mcp.bat' $mcp -Encoding Ascii
    $agent = @"
@echo off
"C:\Program Files\Python312\python.exe" C:\avensio\agent_pty.py
"@
    Set-Content 'C:\avensio\run-agent.bat' $agent -Encoding Ascii
    Set-Content 'C:\avensio\agent\worker.txt' $Worker -Encoding Ascii
  }

  # --- scheduled tasks (re-created under THIS vm's vagrant; interactive session) ---
  Invoke-Command -Session $s -ScriptBlock {
    $prin = New-ScheduledTaskPrincipal -UserId 'vagrant' -LogonType Interactive -RunLevel Highest
    function Reg($name, $exec, $arg, $atLogon) {
      $act = if ($arg) { New-ScheduledTaskAction -Execute $exec -Argument $arg }
             else       { New-ScheduledTaskAction -Execute $exec }
      $trg = if ($atLogon) { New-ScheduledTaskTrigger -AtLogOn -User 'vagrant' } else { $null }
      if ($trg) { Register-ScheduledTask -TaskName $name -Action $act -Principal $prin -Trigger $trg -Force | Out-Null }
      else      { Register-ScheduledTask -TaskName $name -Action $act -Principal $prin -Force | Out-Null }
    }
    Reg 'delphi-mcp'    'C:\avensio\run-mcp.bat'   $null  $true
    Reg 'vmact'         'powershell' '-WindowStyle Hidden -NoProfile -File C:\avensio\act-runner.ps1' $false
    Reg 'avensio-agent' 'C:\avensio\run-agent.bat' $null  $true
    'tasks: ' + ((Get-ScheduledTask | Where-Object { $_.TaskName -in 'delphi-mcp','vmact','avensio-agent' }).TaskName -join ', ')
  }

  # --- start the MCP in the interactive desktop session, verify :8765 ---
  $mcpState = Invoke-Command -Session $s -ScriptBlock {
    Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*Python312*' } |
      ForEach-Object { if ((Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -like '*delphi_vcl_mcp.py*') { Stop-Process -Id $_.Id -Force } }
    Start-ScheduledTask -TaskName 'delphi-mcp'
    Start-Sleep -Seconds 6
    $p = Get-NetTCPConnection -State Listen -LocalPort 8765 -ErrorAction SilentlyContinue
    [pscustomobject]@{ listening = [bool]$p; addr = ($p.LocalAddress -join ',') }
  }
  Write-Host ("delphi_vcl MCP listening on 8765 = {0} ({1})" -f $mcpState.listening, $mcpState.addr)
}
finally { Remove-PSSession $s }
