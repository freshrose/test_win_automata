import sys, hashlib, csv, firebirdsql

db  = sys.argv[1]
out = sys.argv[2]

con = firebirdsql.connect(host='localhost', database=db,
                          user='UNI_OMEGA', password='omega')
cur = con.cursor()
cur.execute("""
  SELECT ID_REP, OZNAC, VERZE, SKUPINA, OCTET_LENGTH(REP) AS L, REP
  FROM S_REPORTY
  ORDER BY OZNAC, VERZE
""")
rows = []
for r in cur.fetchall():
    id_rep, oznac, verze, skup, blen, rep = r
    if rep is None:
        h, blen = '', 0
    else:
        if isinstance(rep, str):
            b = rep.encode('cp1250', 'replace')
        else:
            b = bytes(rep)
        h = hashlib.sha256(b).hexdigest()
        blen = len(b)
    rows.append((str(oznac).strip() if oznac else '',
                 str(verze).strip() if verze else '',
                 skup if skup is not None else '',
                 blen, h))
con.close()

with open(out, 'w', newline='', encoding='ascii') as f:
    w = csv.writer(f)
    w.writerow(['oznac', 'verze', 'skupina', 'replen', 'sha256'])
    for row in rows:
        w.writerow(row)
print('wrote', len(rows), 'rows to', out)
