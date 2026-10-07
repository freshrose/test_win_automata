<#
  install-runtime.ps1 -- Python + MCP deps + Node/Claude Code inside the test VM.
  Idempotent; safe to re-run with `vagrant provision`. Pure ASCII.

  Robustness lesson (first vagrant up): after a silent installer, the new PATH is
  NOT visible in the same provisioner session, so `python`/`node` aren't found by
  name. -> locate the .exe by absolute path and call it directly; verify it exists.

  NOTE: Claude Code in the VM must be AUTHENTICATED out of band (claude login /
  ANTHROPIC creds). See test-operator.md.
#>
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tmp = "C:\Windows\Temp"

function Get-File($url, $out) {
  if (-not (Test-Path $out)) { Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing }
}

function Find-Exe([string[]]$candidates, [string]$globRoot, [string]$leaf) {
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  if ($globRoot -and (Test-Path $globRoot)) {
    $hit = Get-ChildItem $globRoot -Recurse -Filter $leaf -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}

# --- Python 3.12 (silent, all users, add to PATH) ---
$py = Find-Exe @("C:\Program Files\Python312\python.exe") "C:\Program Files" "python.exe"
if (-not $py) {
  $inst = "$tmp\python-3.12.10-amd64.exe"
  Get-File "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe" $inst
  $p = Start-Process $inst -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "Python installer exit $($p.ExitCode)" }
  $py = Find-Exe @("C:\Program Files\Python312\python.exe") "C:\Program Files" "python.exe"
}
if (-not $py) { throw "python.exe not found after install" }
Write-Host "python: $py"

# --- MCP + GUI automation deps + pywinpty (ConPTY host for the interactive agent) ---
& $py -m pip install --upgrade pip
& $py -m pip install "mcp[cli]" pywinauto pywin32 comtypes pillow uvicorn httpx pywinpty
if ($LASTEXITCODE -ne 0) { throw "pip install failed ($LASTEXITCODE)" }

# --- Node LTS + Claude Code (absolute paths; PATH not refreshed mid-session) ---
$node = Find-Exe @("C:\Program Files\nodejs\node.exe") $null $null
if (-not $node) {
  $msi = "$tmp\node-lts.msi"
  Get-File "https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi" $msi
  $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "Node MSI exit $($p.ExitCode)" }
  $node = Find-Exe @("C:\Program Files\nodejs\node.exe") $null $null
}
if (-not $node) { throw "node.exe not found after install" }
$npm = Join-Path (Split-Path $node) "npm.cmd"
Write-Host "node: $node"
# claude-code's postinstall runs `node install.cjs` by NAME -> node's dir must be
# on PATH for this session (WinRM PATH isn't refreshed after the Node MSI).
$env:Path = (Split-Path $node) + ";" + $env:Path
& $npm install -g @anthropic-ai/claude-code
if ($LASTEXITCODE -ne 0) { throw "npm install claude-code failed ($LASTEXITCODE)" }

# --- autostart vm-bootstrap at logon via the HKCU Run key ---
# A scheduled task is session-fragile for GUI apps; the Run key is processed by
# Explorer in the INTERACTIVE session at logon, giving claude a real desktop console.
# LOCAL copy (uploaded by the file provisioner): it mounts the share itself.
$boot = "C:\avensio\vm-bootstrap.ps1"
$run  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty $run -Name "avensio-bootstrap" `
  -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$boot`""
# remove any prior scheduled-task attempt to avoid a double launch
Unregister-ScheduledTask -TaskName "avensio-vm-bootstrap" -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "runtime installed; vm-bootstrap set in HKCU Run."
