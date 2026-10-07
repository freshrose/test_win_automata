<#
  vm-bootstrap.ps1 -- the VM's logon entrypoint (scheduled task, interactive session).
  A LOCAL copy lives at C:\avensio\vm-bootstrap.ps1 so it does not depend on the
  share being mounted yet. Steps:
    1. mount the host shares IN THIS interactive session (net use -> no WinRM 1312),
       symlink C:\automata + C:\db_share, stage .FDB templates,
    2. start the delphi_vcl MCP (localhost),
    3. launch the interactive claude test-operator (its first prompt seeds the
       tail+Monitor loop). No tmux/send-keys: the prompt is claude's first message.
  Pure ASCII.

  NOTE: claude must be AUTHENTICATED once in the VM console (claude login).
#>
$ErrorActionPreference = "Continue"
$worker = [Environment]::GetEnvironmentVariable("AVENSIO_WORKER","Machine")
if (-not $worker) { $worker = $env:COMPUTERNAME }

# --- 1. mount host shares in THIS session ---
$gw = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } |
       Select-Object -First 1).IPv4DefaultGateway.NextHop
foreach ($m in @(@{s="avensio-automata"; l="C:\automata"}, @{s="avensio-db"; l="C:\db_share"})) {
  $remote = "\\$gw\$($m.s)"
  cmd /c "net use $remote /user:avensio_smb avensio26A /persistent:yes" | Out-Null
  if (-not (Test-Path $m.l)) { cmd /c mklink /D "$($m.l)" "$remote" | Out-Null }
}
New-Item -ItemType Directory -Force -Path "C:\DB\_templates","C:\DB\_runs" | Out-Null
Copy-Item "C:\db_share\SKOLA_test.FDB" "C:\DB\_templates\" -Force -ErrorAction SilentlyContinue

# --- 2. delphi_vcl MCP (localhost, plain HTTP) from the share ---
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
$env:DELPHI_MCP_API_KEY = "anyone-can-vibe-now"
$env:DELPHI_MCP_HOST    = "127.0.0.1"
if ($py) { Start-Process $py -ArgumentList "C:\automata\delphi_vcl_mcp.py" -WorkingDirectory "C:\automata" -WindowStyle Hidden }

# --- 3. per-worker inbox + interactive claude test-operator ---
$inbox = "C:\automata\io\$worker\inbox.ndjson"
New-Item -ItemType Directory -Force -Path (Split-Path $inbox) | Out-Null
if (-not (Test-Path $inbox)) { New-Item -ItemType File -Path $inbox | Out-Null }

# operator instructions as CLAUDE.md in a LOCAL working dir (claude auto-loads it;
# more robust than --append-system-prompt with a path).
$agentDir = "C:\avensio\agent"
New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
# CLAUDE.md is uploaded locally by the claudemd-file provisioner (fresh, not the
# stale SMB copy). Only fall back to the share copy if the local one is missing.
if (-not (Test-Path "$agentDir\CLAUDE.md")) {
  Copy-Item "C:\automata\agents\test-operator.md" "$agentDir\CLAUDE.md" -Force -ErrorAction SilentlyContinue
}
# worker name in a file (the prompt is a single word 'boot' -- a multi-word prompt
# arg gets truncated at the first space through claude.cmd/wt; CLAUDE.md reads this).
Set-Content "$agentDir\worker.txt" $worker -Encoding ascii
$bootstrap = "boot"

# Launch claude.cmd DIRECTLY: its own console window IS the TTY claude's TUI needs
# (the Windows analog of tmux). Pass the bootstrap prompt as its OWN argument --
# NOT inside a powershell -Command string: the prompt contains single quotes
# ('test1') that would terminate the string and silently break the launch (this
# was why node never spawned). Full path: the Run-key PowerShell may lack
# %APPDATA%\npm on PATH. --strict-mcp-config: only yt + delphi_vcl (skip the host
# account's ~15 claude.ai connectors). --dangerously-skip-permissions: unattended
# agent in an isolated VM (authorized).
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
$log = "C:\avensio\bootstrap.log"
"[{0}] worker={1} python={2} agent_pty={3} automata={4}" -f (Get-Date -Format o), $worker, [bool]$py, (Test-Path 'C:\avensio\agent_pty.py'), (Test-Path 'C:\automata\mcp\agent-mcp.json') | Out-File $log -Append -Encoding utf8
# agent_pty.py hosts claude in a real ConPTY (pywinpty = the Windows analog of tmux),
# answers the first-run trust/bypass prompts, and keeps the interactive agent alive.
# Runs in this interactive logon session (Run key), so it persists across turns.
Start-Process -FilePath $py -ArgumentList "C:\avensio\agent_pty.py" -WorkingDirectory $agentDir -WindowStyle Hidden
Write-Host "vm-bootstrap '$worker': shares mounted, MCP started, agent_pty launched (claude in ConPTY)."
