param(
  [Parameter(Mandatory)][string]$Tool,
  [string]$ArgsJson = '{}',
  [string]$Out = '',                 # VM path for screenshot PNG (optional)
  [string]$VMName = 'avensio-test1'
)
$ErrorActionPreference = 'Stop'
$pw = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('vagrant', $pw)
$s = New-PSSession -VMName $VMName -Credential $cred
try {
  $res = Invoke-Command -Session $s -ArgumentList $Tool, $ArgsJson, $Out -ScriptBlock {
    param($Tool, $ArgsJson, $Out)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText('C:\avensio\_args.json', $ArgsJson, $enc)
    $a = @('C:\avensio\dvcl.py', $Tool, '@C:\avensio\_args.json')
    if ($Out) { $a += $Out }
    & 'C:\Program Files\Python312\python.exe' @a 2>&1
  }
  $res
  # auto-pull screenshot to host runs mirror
  if ($Out -and $Out -match '\.png$') {
    $hostDir = 'C:\Users\rosa\_rsm\__automata\runs\skola-payroll\licensed-20260604'
    New-Item -ItemType Directory -Force $hostDir | Out-Null
    $base = Split-Path $Out -Leaf
    Copy-Item -FromSession $s -Path $Out -Destination (Join-Path $hostDir $base) -Force -ErrorAction SilentlyContinue
  }
} finally { Remove-PSSession $s }
