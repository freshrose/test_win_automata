param(
  [int]$X=-1,[int]$Y=-1,[int]$Count=1,[switch]$Right,
  [string]$Keys='',[int]$Wait=700,[string]$Save='',
  [string]$IP='172.20.134.239'
)
$ErrorActionPreference='Stop'
$sec=ConvertTo-SecureString 'vagrant' -AsPlainText -Force
$cred=New-Object System.Management.Automation.PSCredential('vagrant',$sec)
$s=New-PSSession -ComputerName $IP -Credential $cred -Authentication Basic
try {
  $act=@{x=$X;y=$Y;count=$Count;right=[bool]$Right;keys=$Keys;wait=$Wait}|ConvertTo-Json -Compress
  Invoke-Command -Session $s -ArgumentList $act -ScriptBlock {
    param($act)
    $enc=New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText('C:\gui\_act.json',$act,$enc)
    [System.IO.File]::Delete('C:\gui\_screen.png')
    Start-ScheduledTask -TaskName vmact
    $d=(Get-Date).AddSeconds(25); while((Get-Date) -lt $d -and -not (Test-Path C:\gui\_screen.png)){Start-Sleep 1}
  }
  if ($Save) {
    $dst='C:\Users\rosa\_rsm\__automata\runs\delphi-build-install'
    New-Item -ItemType Directory -Force $dst | Out-Null
    Copy-Item -FromSession $s -Path 'C:\gui\_screen.png' -Destination (Join-Path $dst $Save) -Force
    Write-Host "saved $Save"
  }
} finally { Remove-PSSession $s }
