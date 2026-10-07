# Scan avensio sources for remaining mojibake. Pure ASCII source on purpose
# (PowerShell 5.1 parses .ps1 as ANSI). Garbage codepoints given as hex.
param(
    [string]$Root = "C:\Users\rosa\_rsm\avensio-dbg\avensio\src",
    [string]$Out  = "C:\Users\rosa\_rsm\fb-migrate-avensio\PRPs\encoding-corruption-remaining.md"
)
$ErrorActionPreference = "Stop"

# Codepoints that never legitimately appear in correct Czech Delphi source,
# plus d-caron (010F/010E) which corruption uses as a catch-all for r/a/z.
$garbageCp = 0x010F,0x010E,0x02DD,0x2122,0x0139,0x013A,0x017C,0x017B,0xFFFD,
             0x02D8,0x02C7,0x00B8,0x00A6,0x00A8,0x00B5,0x00B7,0x0155,0x0154,
             0x02DB,0x00AF,0x00B4
$garbage = New-Object System.Collections.Generic.HashSet[int]
foreach ($c in $garbageCp) { [void]$garbage.Add($c) }

$utf8 = New-Object System.Text.UTF8Encoding($false)
$cp1250 = [System.Text.Encoding]::GetEncoding(1250)

$matches = New-Object System.Collections.Generic.List[object]
$fileCount = @{}

$files = Get-ChildItem -Path $Root -Recurse -Include *.pas,*.dfm -File
foreach ($f in $files) {
    $raw = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) {
        $raw = $raw[3..($raw.Length-1)]
    }
    try   { $text = $utf8.GetString($raw) }
    catch { $text = $cp1250.GetString($raw) }
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\').Replace('\','/')
    $lines = $text -split "`r`n|`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $hit = $false; $hitChars = New-Object System.Collections.Generic.HashSet[int]
        foreach ($ch in $line.ToCharArray()) {
            $cp = [int][char]$ch
            if ($garbage.Contains($cp)) { $hit = $true; [void]$hitChars.Add($cp) }
        }
        if ($hit) {
            $snippet = $line.Trim()
            if ($snippet.Length -gt 160) { $snippet = $snippet.Substring(0,157) + "..." }
            $hexes = ($hitChars | Sort-Object | ForEach-Object { "U+{0:X4}" -f $_ }) -join " "
            $matches.Add([pscustomobject]@{ rel=$rel; ln=($i+1); snip=$snippet; hits=$hexes })
            if ($fileCount.ContainsKey($rel)) { $fileCount[$rel]++ } else { $fileCount[$rel]=1 }
        }
    }
}

$matches = $matches | Sort-Object rel, ln
$total = $matches.Count
$nfiles = $fileCount.Keys.Count

$sb = New-Object System.Text.StringBuilder
$nl = "`r`n"
[void]$sb.Append("# Encoding corruption -- texty, ktere fix/source-encoding-utf8 NEopravil$nl$nl")
[void]$sb.Append("> Vygenerovano: scan_mojibake.ps1 - Vetev: debug/autologin-skipupdate (postaveno na fix/source-encoding-utf8, commit 76394437)$nl")
[void]$sb.Append("> Sken: avensio/src/**/*.{pas,dfm}, soubory dekodovany jako UTF-8 (maji BOM).$nl$nl")
[void]$sb.Append("## Shrnuti$nl$nl")
[void]$sb.Append("- Celkem zasazenych radku: $total$nl")
[void]$sb.Append("- Celkem souboru: $nfiles$nl$nl")
[void]$sb.Append("Detekce: radek je oznacen, pokud obsahuje znak, ktery se v korektnim ceskem Delphi zdrojaku nevyskytuje (U+02DD, U+2122, U+0139, U+017C, U+FFFD, ...) nebo d-caron (U+010F/U+010E), ktere korupce pouziva jako nahradu za r/a/z. Korupce je bytova a ZTRATOVA (napr. a->d-caron i r->d-caron i 'as'->U+02DD), proto neni spolehlive automaticky rekonstruovatelna -- nutna rucni oprava dle kontextu.$nl$nl")
[void]$sb.Append("## Soubory dle poctu zasazenych radku$nl$nl")
[void]$sb.Append("| Soubor | Radku |$nl|---|---:|$nl")
foreach ($rel in ($fileCount.Keys | Sort-Object { -$fileCount[$_] })) {
    [void]$sb.Append("| ``$rel`` | $($fileCount[$rel]) |$nl")
}
[void]$sb.Append("$nl## Vsechny zasazene radky$nl")
$cur = $null
foreach ($m in $matches) {
    if ($m.rel -ne $cur) { [void]$sb.Append("$nl### ``$($m.rel)```$nl$nl"); $cur = $m.rel }
    $s = $m.snip.Replace('`','').Replace('|','/')
    [void]$sb.Append("- L$($m.ln) [$($m.hits)]: ``$s``$nl")
}

[System.IO.File]::WriteAllText($Out, $sb.ToString(), $utf8)
Write-Host ("DONE total_lines={0} files={1} out={2}" -f $total, $nfiles, $Out)
