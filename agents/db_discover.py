import sys, firebirdsql
db = sys.argv[1]
con = firebirdsql.connect(host='localhost', database=db, user='UNI_OMEGA', password='omega')
cur = con.cursor()
cur.execute("""SELECT TRIM(RDB$RELATION_NAME) FROM RDB$RELATIONS
               WHERE RDB$SYSTEM_FLAG=0 AND RDB$VIEW_BLR IS NULL
               ORDER BY 1""")
tabs = [r[0] for r in cur.fetchall()]
pat = ('OSOB','PRPOMER','MZPOL','MZDP','POLOZK','MZDA','MZDY','VYPL','POJIST','ZAMEST','KMEN')
hit = [t for t in tabs if any(p in t for p in pat)]
print("TOTAL tables:", len(tabs))
print("candidate tables:")
for t in hit:
    try:
        cur.execute(f"SELECT COUNT(*) FROM {t}")
        n = cur.fetchone()[0]
    except Exception as e:
        n = f"err:{e}"
    print(f"  {t:30s} rows={n}")
con.close()
