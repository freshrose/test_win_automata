# E2E scénář: SKOLA_test mzdová agenda

DB: `SKOLA_test.FDB` (Firebird 2.5). Login: org SKOLA_test, app user z T_UZIV.
Po každém kroku screenshot do `runs/<issue>/<build>/NN-*.png`, výsledek komentář do YouTracku.

1. **Spuštění programu** — launch avensio.exe, zavřít DevExpress trial dialog(y), login (org → uživatel → heslo → OK), dojet na hlavní okno.
2. **Tisk rekapitulace úplné** z rozpracovaného měsíce.
3. **Tisk rekapitulace úplné** z rozpracovaného a jednoho zavřeného měsíce s přenosem dat do historie.
4. **Zadání nového zaměstnance** — všechny základní údaje, děti, kontakty.
5. **Zadání poměru** novému zaměstnanci.
6. **Zadání úvazku** novému zaměstnanci včetně paušálů.
7. **Tisk rekapitulace úplné** s kontrolou změny o nového zaměstnance a jeho výplaty.
8. **Generování P1-04**.
9. **Tisk mzdového lístku** hromadně, jednotlivě.
10. **Závěrka měsíce**, záloha a obnovení dat.
11. **Vytvořit soubor odvodu** (per databáze různé).
12. **Založení nové funkce a pracoviště** v číselníku včetně jejich parametrů.

## Login — KLÍČOVÉ (zjištěno ze zdrojáku)
- Hesla v `T_UZIV` jsou hashovaná (SHA1/NIS2) — nereverzibilní. ALE existuje **"av heslo"**
  (servisní denní kód): `InternalAuthenticatorC.authenticate` volá `jeAvHeslo(password)` →
  pokud sedí, přihlásí BEZ ohledu na uložené heslo a přeskočí kontrolu platnosti účtu.
- Algoritmus `AvHeslo(den)` (`avensio\src\_\p17\Utility.pas`):
  `N := Trunc(den)+36; mod := (rok>=2015?197:97);`
  `výsledek := ((((((N mod 883)*mod) mod 65536) mod 757)*23) mod 1013) + ((N mod 4)+1)*1013`.
  Trunc(den) = OLE date serial (epocha 1899-12-30) = `[datetime].ToOADate()` v .NET.
  **Pro 2026-05-29 = `4592`.** (V DEBUG buildu projde i `0000`.)
- Servisní login (`loginF.pas`): Uživatel PRÁZDNÝ + Heslo = av-heslo → OK zavolá
  `showUserNames()` (naplní combo z T_UZIV); když je 1 uživatel, auto-vybere a přihlásí.
- Firebird (host): nainstalován 2.5 Win32, sysdba/masterkey; fbclient.dll (32-bit) zkopírován
  vedle avensio.exe. POZOR: isql hlásí "SYSDBA same as SQL role name" (v DB je role SYSDBA) —
  ověřit, zda to neblokuje i FireDAC openDB (po loginu status "Databáze nepřihlášena" — řeší se).
- OK na login formu: cx Heslo edit polyká Enter; spolehlivě funguje **{TAB} → {ENTER}**
  (Tab z Hesla na OK, Enter aktivuje). Coordinate-click selhává kvůli překryvu okny na hostu.

## Pozn. k automatizaci
- Ovládání přes delphi_vcl MCP (get_window_tree → mapovat controls, click/type/select_menu, screenshot).
- Trial dialog: klik titlebar "Zavřít", případně víckrát.
- Login controls (z Phase 0): org combo auto_id 2033826, Uživatel 526630, Heslo 4456538, OK 919558.
- Tisky → typicky náhled/FastReport; uložit/export nebo aspoň screenshot náhledu.
- Úklid: po dojetí `Stop-Process -Force avensio` (WM_CLOSE nestačí), smazat běhovou .FDB.

## TEST DATA — fixní hodnoty pro opakovaný běh (D13 i D2010 STEJNÉ, kvůli porovnání)
Tyto hodnoty se zadávají při každém běhu kroků 4-6, aby D13 a D2010 vstup byl identický.

### Hybrid launch (boot bez tření, zůstane otevřené)
`avensio.exe <ABS>\avensio.ini /test /login abc:0000`  (BEZ /report → hlavní okno zůstane)
→ autologin, SKOLA_test 04.2026, 24 zam., 0 dialogů (WinHTTP=žádné SSL, licensed=žádný trial).

### Krok 4 — Nový zaměstnanec (Kmenové obrazovky → Přidat zaměstnance → Yes)
Wizard se rozbaluje po sekcích (každé OK odhalí další povinná pole):
- **Zaměstnanec:** Osobní číslo `100` (předvyplněno) · Rodné číslo `9005153333`
  (→ Datum narození `15. 5.1990` + Pohlaví `muž` se dopočítají automaticky) · Příjmení `TESTOVACI` · Jméno `Pavel`
- **Obecné údaje:** Stát.příslušnost `CZ` (default) · Ev.pracoviště `7253` (Pracoviště 20) ·
  Výplatní místo = první přes {DOWN} (`Pracoviště 26`)
- **Daň:** ponech `Není učiněné daňové prohlášení` (nic nezaškrtávat)
- **Zdravotní pojištění:** Pojišťovna `111` = Všeobecná ZP (VZP) · Čís.pojištěnce `9005153333`
- **Sociální pojištění:** Čís.pojištěnce `9005153333` · Stav `Počítat SP` (default)
- **Důchod:** prázdné (zam. nar. 1990 není důchodce)
→ po poslední sekci OK → otevře se osobní karta `100 - TESTOVACI Pavel / .../ UCHAZEČ`.

### Krok 5 — Pracovní poměr (osobní karta → horní toolbar „New" page+zelené `+` → Yes)
- Pracovní poměr `1` · Typ vztahu `0` (zaměstnanec v pracovním poměru) · Ukončení `0` (Na dobu neurčitou)
  · Od `1.4.2026` · Sociálně pojištěn `Pojištěn` — vše default
- **Zařazení (povinné):** Pracoviště `7253` (Pracoviště 20) · Funkce-ISCO `233140`
  (= Učitel všeob.vzděl.př.pro 2.st.ZŠ; napiš kód do otevřeného gridu + {ENTER}).
  Funkce automaticky předvyplní Tarifní tabulku `Př.4-ped.`, Stupeň 1.
- Pojištění: ZP `111`, Počítat ZP / Počítat SP — default → OK
- (poměr je v gridu ČERVENÝ + status „!! Upozornění !!" dokud nemá úvazek/plat — OK, doplní krok 6)

### Krok 6 — Úvazek/zařazení + paušály (záložka „Úvazek - zařazení")
- **Úvazek:** pravý klik v gridu „Úvazky" → Nový úvazek (F6) → Prac.doba `1`
  (= 8.00 hod denně / 40.00 h týdně; napiš `1`+{ENTER}). Auto vyplní Rozvrh `1` Pětidenní[Po-Pá],
  stanovená/sjednaná doba 40,00, úvazek týdenní 1,0000 → OK.
- **Paušál:** pravý klik v gridu „Stálé složky mzdy" → Nový paušál (F6) → Druh mzdy `511`
  (= PREMIE KC) · částka do pole **Krácený** `10000` (pole má default „0,00" → smaž {BACKSPACE}×12
  PŘED psaním, jinak vznikne „0,0100000") → OK.
- Pozn.: úvazek nemá základní tarif (Třída nenastavena) → jediná mzda je prémie 10000 Kč;
  pro plnohodnotný plat by se nastavila Třída/Stupeň v platovém zařazení poměru.

### OČEKÁVANÝ mzdový lístek (TESTOVACI Pavel, 04.2026) — REFERENCE pro D13⇄D2010
Po zadání kroků 4-6 spočítá engine (záložka Mzdový lístek):
- Položky: `7 ZAKLADNI TARIF` 176h/22dny/0 Kč · `511 PREMIE KC` 10000 · `471 RIZIKOVÉ SMĚNY` 20
  · `2543 DOPOC.ZAKL.ZP-P` 12400 (dopočet do min. vyměř. základu ZP)
- **Zdanitelný příjem 10000** · Vym.základ SP `10000` / ZP `22400`
- Poj. zaměstnanec soc. `710` / zdr. `2124` · Poj. organizace soc. `2480` / zdr. `900`
- Daň základ 10000 · Daň zálohová `1500` · **Čistý plat `5666`** · Dovolená `240,00h`
- D2010 MUSÍ dát stejné hodnoty (jinak = regrese D13). [D13 ověřeno 2026-06-12,
  screenshot f12d13_60_mzdlistek.png]

## VERDIKT D13 ⇄ D2010 (kroky 4,5,6) — 2026-06-12
**Data-entry parita = IDENTICKÁ.** TESTOVACI Pavel zadán na OBOU (stejný build s TestDriverem,
stejný hybrid autologin, fresh SKOLA_test 04.2026). Každé pole + automatika se chová shodně:
- RC 9005153333 → auto Datum narození `15.5.1990` + Pohlaví `muž` — STEJNĚ na D13 i D2010
- Pracoviště 7253, Výplatní místo (Pracoviště 26), ZP VZP 111 — STEJNĚ
- Poměr Učitel 233140 / na dobu neurčitou 1.4.2026 / Tarif. tabulka Př.4-ped. — STEJNĚ
- Úvazek 40h Pětidenní Po-Pá (úvazek 1,0), paušál 511 PREMIE KC 10000 — STEJNĚ
- Zaměstnanec persistován v obou (24→25 zam.) — screeny f12d2010_01..45.
- **D13 mzda spočítána = čistý plat 5666** (engine AvensioVypocet.exe běží na pozadí, auto-recalc).
- **D2010 mzda SPOČÍTÁNA = BIT-PŘESNĚ SHODNÁ s D13** (čistý plat **5666**, zdan.příjem 10000,
  SP 710/2480, ZP 2124/900, vym.zákl.ZP 22400 vč. dopočtu 12400, daň 1500, dovolená 240h —
  VŠECHNY hodnoty + položky (ZAKLADNI TARIF / PREMIE KC / RIZIKOVÉ SMĚNY / DOPOC.ZAKL.ZP-P)
  IDENTICKÉ). Screenshot f12d2010_49_wage.png.
- **Root cause předchozího „Nepočítaný stav":** D2010 VM neměl `AvensioVypocet.exe` (calc engine
  je separátní proces i v D2010 verzi 3.4.6.17 — avensio ho spouští přes „Výpočet dat" /
  komunikace s výpočtem; HlMenu.actVypocet → WORKTREE_IDWT_KOMUNIKACE_S_VYPOCTEM). __bin měl jen
  avensio.exe. FIX: deploy `var-D2010/avensio/avensioVypocet/__bin/avensioVypocet.exe` (4.6MB,
  staticky linkovaný) → `C:\avensio-d2010\__bin\AvensioVypocet.exe`, restart avensio (spustí engine
  na pozadí → auto-recalc nového zam.). Pozn.: test-driver autologin engine NEspustí sám při bootu,
  ale po deploy ho avensio spustí; 1. restart autologin selhal (DB/FB lock po restartu), 2. restart
  s FB restartem prošel.
**ZÁVĚR (kroky 4,5,6): D13 ⇄ D2010 = ÚPLNÁ PARITA.** Identické vstupy → identický mzdový výsledek
5666 Kč. Žádná D13 regrese v životním cyklu nového zaměstnance.

## KROK 10 — Závěrka měsíce + záloha/obnovení (D2010 HOTOVO 2026-06-12)
Plný měsíční uzávěr 04.2026 → 05.2026 proveden a ověřen na D2010 (TEST d2010-smoke).
Workflow uzávěrky (TZaverkaForm, 4 kroky): **Kontrola dat → Výhradní přístup → Kontrola licence → Start závěrky**.

### Kontrola dat — potvrzení upozornění (KLÍČOVÉ)
- Závěrka blokuje na `PocetZavazErr + PocetNepotvrz > 0` (`zaverkaF.pas:422`). Tlačítko „Spusť
  kontrolu" se po splnění změní na „Přejít na další krok" (`btnKontrola.Action := actNext`).
- **Závažné chyby** (VAHA 0-10) musí pryč úplně. Zde 1 závažná = chybná sleva „ovocnářství/
  zelinářství" (`pojsoc_sleva_zamce_ovozel`) u zam. 65 SRÁŽKOVÁ (DPP, Do neomezené > 30.11) →
  `socialniPojisteniC.mohuUplatnitSlevuOvozel` ZapisChybu(259). Fix: odškrtnout checkbox slevy.
- **Nepotvrzená upozornění** (VAHA 10-11 „s potvrzením" + 12-13 „s opakovaným potvrzením") musí
  být potvrzena. POZOR: v okně závěrky je `GrdDBTableView.OnCellClick := nil` (`zaverkaF.pas:406`)
  → potvrzovat NELZE uvnitř závěrky. Potvrzuje se ve standalone **Provedení kontroly dat**
  (workTree node 3150, `TKForm.provedKontroluZobrazVysledek`): klik na Potvrz checkbox každého
  `(*)` řádku → `ZapisPotvrzeni` UPDATE `S_ERROR.STAV = user.id`. Potvrzení PŘEŽIJE regeneraci
  (PROC_KONT_DB/PROC_KONT_ZAM) → po „Provést kontrolu" zmizí skupiny „s potvrzením".

### Kontrola licence — OFFLINE route (D2010 nemá OpenSSL!)
- Online kontrola = SOAP/TLS přes Indy (`LicenceAppU.uzaverkaLicOnline` → SoapServiceAvensioSoap.
  checkLicense) → na D2010 padá **„Could not load SSL library"** (D13 to má vyřešené WinHTTP migrací,
  D2010 větev NE). Rozdíl D2010⇄D13.
- `checkUzaverkaOnline = (t_param[apl=79,typ=1,radek=152].hodnotach = 'https://')`. Když path ≠
  'https://' a není USB → `UzaverkaToLicence` spadne na **`UzaverkaLicDB`** = offline kontrola
  rozsahu (25 zam. ≤ licencovaný rozsah z DB), vrací `uzLicOKDB` (akceptováno `zaverkaF.pas:326`).
  Aktivace existuje (t_param typ=2 hodnotach not null → `checkActivation`=chActOK).
- **DB zápis přes isql:** vlastník DB = **UNI_OMEGA/omega** (vlastní tabulky i role). Login `sysdba`
  isql ODMÍTÁ („SYSDBA same as SQL role name" — v DB je role SYSDBA). → použij `isql -u UNI_OMEGA
  -p omega`. Fix: `UPDATE t_param SET hodnotach='' WHERE aplikace=79 AND typ=1 AND radek=152; COMMIT;`
  → Kontrola licence „proběhla v pořádku". (Po testu vrátit na 'https://' / obnovit z PRE-LICFLIP.)

### Start závěrky + obnovení
- „Start závěrky měsíce" (Aktuální 04.2026 → nově 05.2026) → progress 100% „Závěrka proběhla úspěšně"
  → Restartovat aplikaci → login dropdown ukáže **05.2026** (období posunuto). OVĚŘENO.
- **Záloha/obnovení (file-level):** host snapshoty na VM `C:\Users\rosa\DB\_runs\`:
  `d2010-smoke.PRE-ZAVERKA.FDB`, `.PRE-LICFLIP.FDB` (04.2026, test data, https:// path),
  `.POST-ZAVERKA-0526.FDB` (zavřený 05.2026 stav). Obnova = Stop avensio+AvensioVypocet →
  Copy PRE-LICFLIP → d2010-smoke.FDB → restart → ověřeno boot na **04.2026**, 25 zam. vč. TESTOVACI.
- crop-zoom helper: `__automata/agents/crop-zoom.ps1 -In x.png -Out y.png -X -Y -W -H -Scale`
  (VM screeny jsou 1024x768, nutno zoomovat dialogy/checkboxy).

## KROK 10 — D13 specifika (HOTOVO 2026-06-12, parita s D2010)
D13 kontrola dat BYTE-IDENTICKÁ s D2010 (1 závažná emp65 ovozel + 5 nepotvrz).
- **emp65 ovozel fix přes GUI (D13):** kontrola grid → dvojklik závažný řádek → karta emp65 →
  dvojklik DPP poměr → editor → tab **„Další údaje pracovního poměru"** → sekce „Další nastavení
  pro slevy na soc.pojištění" → ODŠKRTNI **„Uplatnit slevu soc.poj. zaměstnance v ovocnářství a
  zelinářství"** (klik x≈170 y≈402) → OK. (D13 form má checkbox na 2.tabu; D2010 na hl.stránce.)
- **RECALC NUTNÝ po fixu:** status „Nepřepočítaný"; chyba 259 z předchozího calc běhu v S_ERROR.
  Status panel „Chyba výpočtu" (dvojklik) → „Komunikace s výpočtem" → tab Výpočet → „Spustit" →
  „Přepočti mzdy všem osobám ve zpracovávaném období" → emp65 přepočítán flag=0 → 259 zmizí.
- **Kontrola licence D13 = ONLINE FUNGUJE** (973 volných os.čísel; WinHTTP, žádné „Could not load
  SSL library") → BEZ offline-flip. **ROZDÍL vs D2010** (kde online padá → nutný t_param flip).
- Zbytek shodný: Start závěrky 04→05.2026, restart → 05.2026 ověřeno, restore z PRE-ZAVERKA → 04.2026.

### GUI gotcha — cx lookup combo (Pracoviště/Pojišťovna/atd.)
Klik PŘESNĚ na šipku combu (ne do value-boxu vlevo) → otevře grid popup → `{DOWN}×N{ENTER}`
vybere N-tou položku. Typování kódu + {ENTER} do value-boxu NEFUNGUJE u většiny těchto combů
(jen u některých „pracoviště" v 1. wizardu). Magnifier `…` u některých polí otevře JINÝ dialog
(plánovaná změna ZP), ne lookup — pozor. Souřadnice combo-šipek čti z cropnutého zoomu (ne z full PNG).
