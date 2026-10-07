# -*- coding: utf-8 -*-
"""Scan avensio sources for remaining mojibake (encoding corruption) that the
fix/source-encoding-utf8 normalization failed to recover. Writes a markdown
catalog. Files are now UTF-8 (with BOM) on disk, so we decode as UTF-8 and flag
any line containing a 'garbage' codepoint that does not belong in legitimate
Czech Delphi source.
"""
import os, sys, io, json

ROOT = r"C:\Users\rosa\_rsm\avensio-dbg\avensio\src"
OUT  = r"C:\Users\rosa\_rsm\fb-migrate-avensio\PRPs\encoding-corruption-remaining.md"

# Glyphs that NEVER legitimately appear in Czech source string literals, plus
# 'd-with-caron' (U+010F / U+010E) which the corruption uses as a catch-all
# substitute for r/a/z and is extremely rare as a genuine Czech letter here.
GARBAGE = set("ďĎ˝™ĹĺżŻŁł˘¤¦¨ˇ¸µ¶·ŕŔ�")
# additional double-encoding artefacts (CP1250 bytes read as UTF-8 etc.)
GARBAGE |= set("ĂăĄąÄÅÆÇČ".replace("Č",""))  # keep real Č out

# But some of the above (Ä Å Ć ...) can be false. Restrict to a tight, observed set:
GARBAGE = set("ďĎ˝™ĹĺżŻ�˘ˇ¸¦¨µ·ŕŔ")

exts = (".pas", ".dfm")
matches = []  # (relpath, lineno, line)
filecount = {}

for dirpath, dirs, files in os.walk(ROOT):
    for fn in files:
        if not fn.lower().endswith(exts):
            continue
        full = os.path.join(dirpath, fn)
        rel = os.path.relpath(full, ROOT).replace("\\", "/")
        try:
            with open(full, "rb") as f:
                raw = f.read()
        except Exception as e:
            continue
        # strip BOM
        if raw[:3] == b"\xef\xbb\xbf":
            raw = raw[3:]
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            text = raw.decode("cp1250")
        for i, line in enumerate(text.splitlines(), 1):
            hits = [c for c in line if c in GARBAGE]
            if hits:
                matches.append((rel, i, line.rstrip(), "".join(sorted(set(hits)))))
                filecount[rel] = filecount.get(rel, 0) + 1

# write report
matches.sort(key=lambda m: (m[0], m[1]))
total = len(matches)
nfiles = len(filecount)

with io.open(OUT, "w", encoding="utf-8") as o:
    o.write("# Encoding corruption — texty, ktere fix/source-encoding-utf8 NEopravil\n\n")
    o.write("> **Vygenerovano:** scan_mojibake.py · **Vetev:** debug/autologin-skipupdate "
            "(postaveno na fix/source-encoding-utf8, commit 76394437)\n")
    o.write("> **Sken:** `avensio/src/**/*.{pas,dfm}`, soubory dekodovany jako UTF-8 (maji BOM).\n\n")
    o.write("## Shrnuti\n\n")
    o.write("- **Celkem zasazenych radku:** %d\n" % total)
    o.write("- **Celkem souboru:** %d\n\n" % nfiles)
    o.write("Detekce: radek je oznacen, pokud obsahuje znak, ktery se v korektnim ceskem "
            "Delphi zdrojaku nevyskytuje (`˝ ™ Ĺ ĺ ż Ż \\ufffd ˘ ˇ ...`) nebo `ď/Ď`, ktere "
            "korupce pouziva jako nahradu za `r/a/z`. Korupce je bytova a ZTRATOVA "
            "(napr. `á`->`ď` i `ř`->`ď` i `áš`->`˝`), proto neni spolehlive automaticky "
            "rekonstruovatelna — nutna rucni oprava dle kontextu.\n\n")
    o.write("## Soubory dle poctu zasazenych radku\n\n")
    o.write("| Soubor | Radku |\n|---|---:|\n")
    for rel in sorted(filecount, key=lambda k: -filecount[k]):
        o.write("| `%s` | %d |\n" % (rel, filecount[rel]))
    o.write("\n## Vsechny zasazene radky\n\n")
    cur = None
    for rel, ln, line, hits in matches:
        if rel != cur:
            o.write("\n### `%s`\n\n" % rel)
            cur = rel
        snippet = line.strip()
        if len(snippet) > 160:
            snippet = snippet[:157] + "..."
        o.write("- **L%d** [`%s`]: `%s`\n" % (ln, hits, snippet))

print(json.dumps({"total_lines": total, "files": nfiles, "out": OUT}, ensure_ascii=False))
