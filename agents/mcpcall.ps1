param(
  [Parameter(Mandatory)][string]$VM,
  [Parameter(Mandatory)][string]$Tool,
  [string]$ArgsJson = '{}',
  [string]$Shot = '',          # if set: take a screenshot after, pull to run _shots as this name
  [int]$Pause = 0
)
$ErrorActionPreference = 'Stop'
$run = 'C:\Users\rosa\_rsm\__automata\runs\2026-06-17_crossload-pdf\_shots'
New-Item -ItemType Directory -Force $run | Out-Null
$pw = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('vagrant', $pw)
$s = New-PSSession -VMName $VM -Credential $cred
try {
  $enc = New-Object System.Text.UTF8Encoding($false)
  Invoke-Command -Session $s -ArgumentList $ArgsJson -ScriptBlock {
    param($a); [System.IO.File]::WriteAllText('C:\avensio\_mcp.json', $a, (New-Object System.Text.UTF8Encoding($false)))
  }
  $out = Invoke-Command -Session $s -ArgumentList $Tool -ScriptBlock {
    param($t)
    $env:PYTHONUTF8 = '1'
    & 'C:\Program Files\Python312\python.exe' 'C:\avensio\dvcl.py' $t '@C:\avensio\_mcp.json' 2>&1
  }
  Write-Output ($out -join "`n")
  if ($Pause -gt 0) { Start-Sleep -Milliseconds $Pause }
  if ($Shot) {
    Invoke-Command -Session $s -ScriptBlock {
      $env:PYTHONUTF8 = '1'
      & 'C:\Program Files\Python312\python.exe' 'C:\avensio\dvcl.py' delphi_screenshot '{}' 'C:\avensio\shots\_m.png' 2>&1 | Out-Null
    }
    Copy-Item -FromSession $s -Path 'C:\avensio\shots\_m.png' -Destination (Join-Path $run $Shot) -Force -EA SilentlyContinue
    Write-Output "SHOT $Shot"
  }
} finally { Remove-PSSession $s }
