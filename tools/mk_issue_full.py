# -*- coding: utf-8 -*-
"""Create the FULL 12-step payroll scenario issue (AVE-4) for the VM agent."""
import sys
sys.path.insert(0, r"C:\automata\orchestrator")
from yt_client import YouTrackClient

SUMMARY = "[e2e full] SKOLA_test mzdova agenda - 12 kroku (VM test1)"

DESCRIPTION = """\
Plny e2e scenar nad SKOLA_test. Referencni soubor (na share): C:\\automata\\scenarios\\skola-test-payroll.md
Po KAZDEM kroku: delphi_screenshot -> C:\\automata\\runs\\<issue>\\<build>\\NN-<krok>.png, prubezne yt_post_comment.

LOGIN (overeno; pozor build-specificke control auto_id -> namapuj pres get_window_tree/screenshot):
- Po startu TLoginForm. UNI_OMEGA UZ EXISTUJE v T_UZIV (ID 3) i jako Firebird ucet.
- Prihlas se: Uzivatel = UNI_OMEGA (nebo abc), Heslo = av-heslo 4592 (pro 2026-05-29; DEBUG bere i 0000),
  submit {TAB}->{ENTER}. Muze byt DVOUKROKOVE: prvni OK -> "Information" modal -> OK -> druhy {TAB}{ENTER}.
- CIL: hlavni okno musi byt PRIHLASENO k DB. Pokud status bar hlasi "Databaze neprihlasena /
  Uzivatel neprihlasen", klikni v ribbonu akci "Prihlaseni" a dokonci prihlaseni (UNI_OMEGA + 4592),
  dokud title NEni "SKOLA ... (MM.RRRR)" a status NEhlasi neprihlasen.
- Pokud po loginu naskoci modal "Kontrola dat", zavri ho (Zavrit/OK) a pokracuj (znamy bug).

KROKY:
1. Spusteni programu + login (viz vyse) -> hlavni okno, prihlaseno.
2. Tisk rekapitulace uplne z rozpracovaneho mesice (Tiskove sestavy -> Rekapitulace -> Uplna -> Tisk; nahled screenshot).
3. Tisk rekapitulace uplne z rozpracovaneho + jednoho zavreneho mesice s prenosem do historie (obdobi od=zavreny mesic, do=rozpracovany).
4. Zadani noveho zamestnance - vsechny zakladni udaje, deti, kontakty.
5. Zadani pomeru novemu zamestnanci.
6. Zadani uvazku novemu zamestnanci vcetne pausalu.
7. Tisk rekapitulace uplne s kontrolou zmeny o noveho zamestnance a jeho vyplaty.
8. Generovani P1-04.
9. Tisk mzdoveho listku hromadne i jednotlive.
10. Zaverka mesice, zaloha a obnoveni dat.
11. Vytvorit soubor odvodu.
12. Zalozeni nove funkce a pracoviste v ciselniku vcetne parametru.

POZN.: kazdy krok co nejvic samostatne; pokud krok selze, zaznamenej do komentare a pokracuj dalsim
(neprerusuj cely beh kvuli jednomu kroku). Na konci yt_post_comment souhrn pass/fail po krocich,
yt_attach_file klicove screenshoty + transcript, yt_set_state passed/failed. Cleanup: run-avensio.ps1 stop + smaz per-run .FDB.
"""

c = YouTrackClient()
iss = c.create_issue(SUMMARY, DESCRIPTION)
rid = iss.get("id")
try:
    c.add_tag(rid, c.label)
    print("ISSUE", rid, "tagged", c.label)
except Exception as e:
    print("ISSUE", rid, "tag WARN:", e)
