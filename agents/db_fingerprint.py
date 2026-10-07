import sys, csv, firebirdsql
db, out = sys.argv[1], sys.argv[2]
con = firebirdsql.connect(host='localhost', database=db, user='UNI_OMEGA', password='omega')
cur = con.cursor()
cols = ['VZ_SP','SP','VZ_ZP','POJ','DAN','CISTA','ZP_ORG','SP_ORG']
sums = ", ".join(f"SUM({c}) AS S_{c}" for c in cols)
cur.execute(f"SELECT OBDOBI, COUNT(*) AS N, {sums} FROM H_SUM GROUP BY OBDOBI ORDER BY OBDOBI")
rows = cur.fetchall()
hdr = ['obdobi','n'] + [f'sum_{c.lower()}' for c in cols]
with open(out, 'w', newline='', encoding='ascii') as f:
    w = csv.writer(f); w.writerow(hdr)
    for r in rows:
        w.writerow([str(x) if x is not None else '' for x in r])
print('periods:', len(rows))
con.close()
