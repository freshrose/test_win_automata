import sys, firebirdsql
db = sys.argv[1] if len(sys.argv) > 1 else r'C:\DB\_runs\crossload.FDB'
con = firebirdsql.connect(host='localhost', database=db, user='UNI_OMEGA', password='omega')
cur = con.cursor()
# NaplnDataSum SELECT, ROVINA_CELY_SOUBOR variant (CIS_PRAC=0, NAZ_ROVINY=''), no org/rovina joins
sql = """
SELECT 0 AS CIS_PRAC, '' AS NAZ_ROVINY,
 SUM(M.VZ_ZP + M.VZ_ZP_NV + M.VZ_ZP_NVO + M.VZ_ZP_NVP) AS VZ_ZP, SUM(M.VZ_SP) AS VZ_SP,
 SUM(M.ZP_ORG) AS ZP_ORG, SUM(M.SP_ORG) AS SP_ORG,
 SUM(M.SP_PRAC) AS SP_PRAC, SUM(M.ZP_PRAC) AS ZP_PRAC,
 SUM(M.VYZIVNE) AS VYZIVNE, SUM(M.EXEKUCE) AS EXEKUCE,
 SUM(M.POJISTNE) AS POJISTNE,
 SUM(M.DAN-M.DAN_OPRAVA-M.DAN_ROKZUCT-M.DAN_OPR_MR-M.DAN_OPR_SLEVA_MR-M.DANSOL-M.BONUS*100) AS DAN,
 SUM(M.CISTA) AS CISTA,
 SUM(M.SLEVA_D) * 100 AS SLEVA_D, SUM(M.SLEVA) * 100 AS SLEVA,
 SUM(M.DOPLATEK_KC) AS DOPLATEK_KC
FROM M_SUM M
LEFT JOIN P_PRIM PP ON PP.ID_ZAM = M.ID_ZAM
WHERE M.ID_ZAM > -1
GROUP BY CIS_PRAC, NAZ_ROVINY
"""
cur.execute(sql)
desc = cur.description
rows = cur.fetchall()
print("rowcount:", len(rows))
print("columns (name, type_code, internal_size, precision, scale):")
for d in desc:
    print("  ", d[0], "| type=", d[1], "| size=", d[3], "| prec=", d[4], "| scale=", d[5])
if rows:
    print("first row values:")
    for d, v in zip(desc, rows[0]):
        print(f"  {d[0]:14s} = {v!r}")
con.close()
