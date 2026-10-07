# -*- coding: utf-8 -*-
"""Create the first e2e smoke issue in YouTrack and tag it. Run inside the VM
(has Python 3.12 + httpx + auth.env on the C:\\automata share). Prints idReadable."""
import sys
sys.path.insert(0, r"C:\automata\orchestrator")
from yt_client import YouTrackClient

SUMMARY = "[e2e smoke] avensio login + hlavni okno (SKOLA_test, VM test1)"

DESCRIPTION = """\
Smoke test celeho e2e pipeline pres VM agenta: provision DB -> launch avensio ->
login -> screenshot -> report. Toto jsou kroky 1-2 plneho scenare
scenarios/skola-test-payroll.md.

Kroky:
1. Spusteni: launch avensio.exe (run-avensio.ps1 start), zavri pripadne DevExpress
   trial dialogy (titlebar "Zavrit"), pripadne vicekrat.
2. Login na TLoginForm (pokud build neautologuje):
   - Uzivatel = UNI_OMEGA
   - Heslo = 4592   (av-heslo pro 2026-05-29; v DEBUG buildu projde i 0000)
   - OK. DB ucet UNI_OMEGA/omega se aplikuje interne z ini.
3. Dojet na hlavni okno (titulek obsahuje "AVENSIO SW"). Pokud naskoci modal
   "Kontrola dat", zavri ho (Zavrit/OK) a pokracuj.
4. delphi_screenshot hlavniho okna -> C:\\automata\\runs\\<issue>\\<build>\\01-main.png
5. Report: yt_attach_file ten screenshot; yt_post_comment kratke pass/fail shrnuti
   (titulek okna, prihlaseny uzivatel); yt_set_state passed/failed.
6. Cleanup: run-avensio.ps1 stop; smaz per-run .FDB.

Pozn.: av-heslo algoritmus + login detaily viz scenarios/skola-test-payroll.md.
"""

c = YouTrackClient()
iss = c.create_issue(SUMMARY, DESCRIPTION)
rid = iss.get("idReadable")
try:
    c.add_tag(rid, c.label)
except Exception as e:
    print("WARN add_tag:", e)
print("ISSUE", rid)
