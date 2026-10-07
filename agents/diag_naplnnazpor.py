import sys, firebirdsql
db = sys.argv[1] if len(sys.argv) > 1 else r'C:\DB\_runs\crossload.FDB'
con = firebirdsql.connect(host='localhost', database=db, user='UNI_OMEGA', password='omega')
cur = con.cursor()

# column type of T_CISELNIK.NAZEV
cur.execute("""SELECT f.RDB$FIELD_NAME, t.RDB$TYPE_NAME, f2.RDB$FIELD_LENGTH, f2.RDB$CHARACTER_LENGTH
  FROM RDB$RELATION_FIELDS f
  JOIN RDB$FIELDS f2 ON f2.RDB$FIELD_NAME = f.RDB$FIELD_SOURCE
  JOIN RDB$TYPES t ON t.RDB$TYPE = f2.RDB$FIELD_TYPE AND t.RDB$FIELD_NAME='RDB$FIELD_TYPE'
  WHERE f.RDB$RELATION_NAME='T_CISELNIK' AND f.RDB$FIELD_NAME IN ('NAZEV','S4','S5','P5')""")
print("== T_CISELNIK column types ==")
for r in cur.fetchall():
    print("  ", [str(x).strip() if isinstance(x,str) else x for x in r])

# NaplnNazPorSum query (period 2026-04-01)
sql = """
SELECT T.ID, T.NAZEV, T.P5, T.S4, T.S5, C.MD, C.DAL
FROM T_CISELNIK T
LEFT OUTER JOIN T_UCTU_GRPO O ON O.ID_UDAJ = T.ID AND O.TYP_GRP = 5
LEFT OUTER JOIN T_UCTU_MZD U ON O.ID_GRP = U.ID_GRP
LEFT OUTER JOIN T_UCTU C ON U.UM_IDUCT = C.ID_UCT
WHERE T.ID_CISELNIK = 27
  AND T.PLATI_OD <= '2026-04-01' AND T.PLATI_DO >= '2026-04-01'
  AND P5 > 0
"""
cur.execute(sql)
rows = cur.fetchall()
print(f"\n== NaplnNazPorSum rows: {len(rows)} ==")
for r in rows:
    print(f"  P5={r[2]:>4}  NAZEV={r[1]!r:24}  S4={r[3]!r}")
con.close()
