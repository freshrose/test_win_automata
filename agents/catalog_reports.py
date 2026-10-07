import sys, csv, firebirdsql
from collections import defaultdict

db  = sys.argv[1]
out = sys.argv[2]

con = firebirdsql.connect(host='localhost', database=db,
                          user='UNI_OMEGA', password='omega')
cur = con.cursor()
cur.execute("SELECT OZNAC, NAZEV, SKUPINA, VERZE FROM S_REPORTY ORDER BY OZNAC, VERZE")

def dec(x):
    if x is None: return ''
    if isinstance(x, bytes): return x.decode('cp1250', 'replace')
    return str(x)

def vkey(s):
    try: return tuple(int(p) for p in s.replace(',', '.').split('.'))
    except Exception: return (0,)

best = {}
for oznac, nazev, skup, verze in cur.fetchall():
    o = dec(oznac).strip()
    ver = dec(verze).strip()
    nm = dec(nazev).strip()
    sk = skup if skup is not None else ''
    if o not in best or vkey(ver) > vkey(best[o][2]):
        best[o] = (nm, sk, ver)
con.close()

with open(out, 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow(['oznac', 'nazev', 'skupina', 'verze_aktivni'])
    for o in sorted(best):
        nm, sk, ver = best[o]
        w.writerow([o, nm, sk, ver])
print('wrote', len(best), 'reports to', out)
