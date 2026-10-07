param(
  [Parameter(Mandatory=$true)][string]$In,
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$X = 0, [int]$Y = 0, [int]$W = -1, [int]$H = -1,
  [double]$Scale = 2.0
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$dir = 'C:\Users\rosa\_rsm\__automata\runs\skola-payroll\licensed-20260604'
$src = if (Test-Path $In) { $In } else { Join-Path $dir $In }
$dst = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $dir $Out }
$img = [System.Drawing.Image]::FromFile($src)
if ($W -lt 0) { $W = $img.Width - $X }
if ($H -lt 0) { $H = $img.Height - $Y }
$rect = New-Object System.Drawing.Rectangle($X, $Y, $W, $H)
$crop = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($crop)
$g.DrawImage($img, (New-Object System.Drawing.Rectangle(0,0,$W,$H)), $rect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$nw = [int]($W * $Scale); $nh = [int]($H * $Scale)
$big = New-Object System.Drawing.Bitmap($nw, $nh)
$g2 = [System.Drawing.Graphics]::FromImage($big)
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g2.DrawImage($crop, 0, 0, $nw, $nh)
$g2.Dispose()
$big.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose(); $crop.Dispose(); $big.Dispose()
Write-Host "saved $dst ($nw x $nh from ${W}x${H}@${X},${Y})"
