"""Compare report-template definitions (REP blob sha256) between two AVENSIO
installs (D13 vs D2010). Input: two CSVs from hash_reports.py.
Emits a markdown report + machine summary to stdout."""
import sys, csv
from collections import defaultdict

def load(path):
    rows = []
    with open(path, newline='', encoding='ascii') as f:
        for r in csv.DictReader(f):
            rows.append(r)
    return rows

d13 = load(sys.argv[1])
d20 = load(sys.argv[2])

def by_pair(rows):
    m = {}
    for r in rows:
        m[(r['oznac'], r['verze'])] = r['sha256']
    return m

def versions(rows):
    v = defaultdict(set)
    for r in rows:
        v[r['oznac']].add(r['verze'])
    return v

def vermax(rows):
    """latest version string per oznac (lexical on dotted-int tuple)."""
    def key(s):
        try:
            return tuple(int(x) for x in s.replace(',', '.').split('.'))
        except Exception:
            return (0,)
    best = {}
    for r in rows:
        o, ver = r['oznac'], r['verze']
        if o not in best or key(ver) > key(best[o][0]):
            best[o] = (ver, r['sha256'])
    return best

p13, p20 = by_pair(d13), by_pair(d20)
o13, o20 = set(versions(d13)), set(versions(d20))
allo = o13 | o20
both_o = o13 & o20

# (oznac,verze) pairs present in both
common_pairs = set(p13) & set(p20)
ident = [k for k in common_pairs if p13[k] == p20[k]]
diff  = [k for k in common_pairs if p13[k] != p20[k]]

only13_o = sorted(o13 - o20)
only20_o = sorted(o20 - o13)

# active (latest) version per oznac, compare for reports present in both
m13, m20 = vermax(d13), vermax(d20)
active_match = []      # same active version AND same hash
active_verdiff = []    # different active version
active_hashdiff = []   # same active version but different hash (real divergence!)
for o in sorted(both_o):
    v13, h13 = m13[o]
    v20, h20 = m20[o]
    if v13 == v20:
        if h13 == h20:
            active_match.append(o)
        else:
            active_hashdiff.append((o, v13))
    else:
        active_verdiff.append((o, v13, v20))

print("# Porovnani definic sestav (REP sablona) — D13 vs D2010\n")
print(f"- Radku (oznac,verze) v D13: **{len(d13)}**, v D2010: **{len(d20)}**")
print(f"- Distinct sestav (oznac) v D13: **{len(o13)}**, v D2010: **{len(o20)}**, spolecnych: **{len(both_o)}**")
print(f"- Spolecnych (oznac,verze) paru: **{len(common_pairs)}** — z toho **bytove identickych: {len(ident)}**, lisicich se: **{len(diff)}**")
print()
print("## Aktivni (nejvyssi) verze per sestava — pro sestavy pritomne v obou instalacich")
print(f"- Stejna aktivni verze A identicka sablona: **{len(active_match)}**")
print(f"- Stejna aktivni verze, ale ODLISNA sablona (skutecny rozdil!): **{len(active_hashdiff)}**")
print(f"- Odlisna aktivni verze (jiny version-set v DB): **{len(active_verdiff)}**")
print()
if active_hashdiff:
    print("### !!! Sestavy se shodnou verzi ale odlisnou sablonou (vyzaduji pozornost):")
    for o, v in active_hashdiff:
        print(f"  - {o} (verze {v})")
    print()
if diff:
    print("### (oznac,verze) pary pritomne v obou, ale s odlisnym hashem:")
    for o, v in sorted(diff):
        print(f"  - {o} v{v}: d13={p13[(o,v)][:12]} d20={p20[(o,v)][:12]}")
    print()
print(f"### Sestavy jen v D13 ({len(only13_o)}): " + (", ".join(only13_o) if only13_o else "—"))
print(f"### Sestavy jen v D2010 ({len(only20_o)}): " + (", ".join(only20_o) if only20_o else "—"))
print()
if active_verdiff:
    print("### Sestavy s odlisnou aktivni verzi (D13 ver / D2010 ver):")
    for o, v13, v20 in active_verdiff:
        same = "identicka-sablona-pres-verze" if m13[o][1]==m20[o][1] else "ruzna-sablona"
        print(f"  - {o}: D13={v13}  D2010={v20}  ({same})")
