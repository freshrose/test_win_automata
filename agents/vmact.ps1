param(
  [int]$X = -1,
  [int]$Y = -1,
  [int]$Count = 1,
  [switch]$Right,
  [string]$Keys = '',
  [int]$Wait = 400,
  [int]$X2 = -1,
  [int]$Y2 = -1,
  [int]$Count2 = 1,
  [string]$Save = '',            # host filename to save the resulting screen capture as
  [string]$VMName = 'avensio-test1'
)
$ErrorActionPreference = 'Stop'
$pw = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('vagrant', $pw)
$s = New-PSSession -VMName $VMName -Credential $cred
try {
  $act = @{ x = $X; y = $Y; count = $Count; right = [bool]$Right; keys = $Keys; wait = $Wait; x2 = $X2; y2 = $Y2; count2 = $Count2 } | ConvertTo-Json -Compress
  Invoke-Command -Session $s -ArgumentList $act -ScriptBlock {
    param($act)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText('C:\avensio\_act.json', $act, $enc)
    schtasks /Run /TN vmact 2>&1 | Out-Null
  }
  Start-Sleep -Seconds ([math]::Max(4, [int]($Wait/1000) + 3))
  if ($Save) {
    $hostDir = 'C:\Users\rosa\_rsm\__automata\runs\skola-payroll\licensed-20260604'
    New-Item -ItemType Directory -Force $hostDir | Out-Null
    Copy-Item -FromSession $s -Path 'C:\avensio\shots\_screen.png' -Destination (Join-Path $hostDir $Save) -Force
    Write-Host "saved $Save"
  }
} finally { Remove-PSSession $s }
