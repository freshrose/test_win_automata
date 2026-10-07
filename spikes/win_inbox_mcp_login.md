# Phase 0 Spike — findings (Windows)

Stav: probíhá. Hotová je nejtěžší část — **mapování login sekvence avensio.exe**
přes `delphi_vcl` MCP. Zbývá: inbox/Monitor test, yt-mcp registrace, Vagrant.

## Lokální inventář (host)
- `avensio.exe` postaven: `C:\Users\rosa\_rsm\avensio\__bin\avensio.exe` (29 MB, 22.05.2026). `.bpl` jsou vedle (běží).
- **Žádná `.FDB`** v `C:\Users\rosa\DB\` → plný login (otevření DB) zatím nejde dokončit; login FORM ale renderuje.
- **Vagrant není nainstalován** (Phase 3+).
- `delphi_vcl` MCP běží na `127.0.0.1:8765` (plain HTTP).

## GUI login sekvence — OVĚŘENO end-to-end (po form)

Spuštění `avensio.exe` projde třemi okny v tomto pořadí:

### 1. DevExpress trial dialog `TfrmNewTrialDialog`
- Objeví se **při každém spuštění** (trial licence). Čistě informační ("VCL Subscription / TRIAL VERSION").
- UIA **nevidí vnitřní tlačítka** (DevExpress skin) — jediný ovladatelný prvek je
  zavírací **X** na titlebaru: `[Button] name="Zavřít"` (rect ~1287,193).
- `{ENTER}` ho NEzavře. **Recept: klikni titlebar `Zavřít`** →
  `delphi_click(ctrl_name="Zavřít", ctrl_type="Button")`. Tím se pokračuje do appky.

### 2. (jen když chybí ini) error MessageBox
- Pokud `avensio.exe` nenajde `avensio.ini` → `#32770` box:
  *„Nelze načíst seznam organizací! Nebyl nalezen ini soubor…"*. → app dál nepokračuje.
- **Požadavek na provisioning:** `avensio.ini` **musí ležet vedle exe** (`__bin\avensio.ini`).
  Zdroj: `C:\Users\rosa\_rsm\avensio\avensio\avensio.ini`. Formát:
  ```ini
  [ORGANIZACE1]
  NAZEV1=SKOLA_test (04.2026)
  FileDB=C:\Users\rosa\DB\SKOLA_test.FDB
  hidden=0
  ```
  `provision-test-db.ps1` tedy zapisuje per-test org (cestu k čerstvé `.FDB`) do tohoto ini.

### 3. Login form `TLoginForm` ("AVENSIO SW … | Přihlášení k databázi")
Ověřená mapa controls (DevExpress cx):

| Pole | Třída | auto_id | Inner edit auto_id | Pozn. |
|---|---|---|---|---|
| **Organizace** (combo) | `TcxComboBox` | `2033826` | `526510` | předvybraná 1. org z ini |
| `…` browse DB | `TcxButtonEdit` (`btnEdit1`) | `1640424` | — | výběr .FDB souboru |
| **Uživatel** (vlevo) | `TcxTextEdit` | `526630` | `592170` | app user (T_UZIV) |
| **Heslo** (vpravo) | `TcxTextEdit` | `4456538` | `526642` | maskované |
| **OK** | `TBitBtn` | `919558` | — | name renderován jako "0K" |
| **Storno** | `TBitBtn` | `1705686` | — | cancel |

**Login recept pro test-operator:**
1. `delphi_click(ctrl_name="Zavřít", ctrl_type="Button")` — zavři trial dialog.
2. (org je předvybraná; jinak `delphi_select_item` na `TcxComboBox` auto_id 2033826)
3. `delphi_set_text` / `delphi_type_text` do Uživatel (auto_id 526630).
4. `delphi_type_text` do Heslo (auto_id 4456538) — pro maskované pole preferuj type_text.
5. `delphi_click` OK (auto_id 919558).
- DB creds (`sysdba`/`masterkey`) řeší `openDB` interně přes cestu z ini; app user je z `T_UZIV`.

## Gotchas (potvrzené)
- **MCP bug `work_dir`**: `delphi_launch_app(work_dir=…)` selže
  (`Application.__init__() got an unexpected keyword argument 'work_dir'`) — server
  předává `work_dir` do `Application()` místo `.start()`. Workaround: nepoužívat
  work_dir; spoléhat na exe-dir lookup (proto `avensio.ini` + `.bpl` vedle exe).
  **TODO fix** v `delphi_vcl_mcp.py` (přesunout work_dir do `.start()`).
- **Úklid procesu**: WM_CLOSE (`delphi_close_app`) na login formu NEUKONČÍ proces a
  zamkne exe → další build/launch selže. **Vždy `Stop-Process -Force`** (ověřeno).
- Czech accenty v UIA name stringách chodí korektně (UTF-8); pozor ale na U+FFFD
  v `.pas` string literálech (viz paměť) u textových assertů.

## Artefakty
- `runs\trial-dialog.png`, `runs\login-form.png` — vizuální reference.

## Inbox transport — OVĚŘENO end-to-end
- `tail -n +1 -F <inbox.ndjson>` přes **Monitor** tool: všechny 3 řádky (1 seed +
  2 appended) dorazily jako samostatné eventy interaktivnímu claudovi. Pattern z
  reference funguje 1:1.
- **GOTCHA (nový): zápis do inboxu musí být shared-write.** PowerShell `Add-Content`
  selže, dokud `tail -F` drží soubor: *„soubor je využíván jiným procesem"*.
  Bash `>>` funguje; Python `open(path,"a")` na Windows taky (povoluje sdílené
  čtení) → **daemon (inbox_pump.py) bude appendovat v Pythonu, ne přes PowerShell.**
- Cesty: Git Bash používá `/c/Users/...`; Monitor běží v Git Bash/cygwin prostředí.

## Tooling — OVĚŘENO
- Vagrant **2.4.9** nainstalován (`C:\Program Files\Vagrant\bin\vagrant.exe`).
  Hyper-V feature **Enabled**, služba `vmms` **Running** → provider Hyper-V je k dispozici.
- `yt_client.py` + `yt_mcp.py` napsány; importují se a registrují tools (offline
  syntax/import OK). `provision-test-db.ps1` + `run-avensio.ps1` parsují OK.
- ini key konstanty potvrzeny v `baseEnvC.pas`: `FileDB`, `NAZEV1` (+ `hidden`).

## Provisioning skripty — OVĚŘENO na reálných artefaktech
- `provision-test-db.ps1 -RunId spike-0 -TemplateFdb db_versions\SKOLA_test.FDB`
  → zkopíruje 573MB `.FDB` do `C:\Users\rosa\DB\_runs\spike-0.FDB` a zapíše
  korektní `avensio.ini` (NAZEV1/FileDB/hidden) vedle exe. ✓
- `run-avensio.ps1 -Action start` spustí appku; `-Action stop` ji force-stopne
  (WM_CLOSE by neukončil) a odemkne exe. ✓
- **Template k dispozici:** `C:\Users\rosa\_rsm\db_versions\SKOLA_test.FDB` (573 MB)
  odpovídá orgu `SKOLA_test`. Druhá: `20260424_AVENSIO_54610.FDB` (730 MB, ostrá data).
- **Plný login přes DB nešel dokončit na hostu** — `openDB` (FireDAC TCPIP
  127.0.0.1:3050) potřebuje běžící **Firebird server**, který na hostu není.
  → Firebird patří do test VM (Phase 3). Na hostu projde provision→launch→trial→form.

## DVA potvrzené důvody pro izolovaný desktop (jádro architektury)
1. **Dva trial dialogy** za sebou (ne jeden) — DevExpress nag se může objevit
   vícekrát; test-operator musí `Zavřít` klikat ve smyčce, dokud nezůstane `TLoginForm`.
2. **Sdílený desktop krade kliky:** během spiku uživatel otevřel **File Explorer**,
   který překryl trial dialog → MCP `click_input` (klik na obrazovkové souřadnice)
   trefoval Explorer, ne dialog. **Toto je přesně důvod, proč 1 worker = 1 VM
   desktop.** Na hostu cizí okna rozbíjejí GUI automatizaci → flaky testy.

## yt-mcp + YouTrack — OVĚŘENO LIVE
- `auth.env` doplněn reálnými hodnotami: `https://freshflow.youtrack.cloud`,
  projekt **AVE**, label `avensio-e2e`. Auth OK jako `jan_rosa`.
- `yt_mcp.py` přes oficiálního MCP stdio klienta: handshake OK, `tools/list`
  vrací všech 5 nástrojů, `yt_get_issue` reálně zavolal YouTrack (404 na
  neexistující issue ošetřen jako `{success:false}`). → `claude --mcp-config
  yt-mcp.json` to zaregistruje.
- `poll_pipeline()` je tolerantní: na greenfieldu (tag `avensio-e2e` zatím
  neexistuje) vrací `[]` místo 400. Smoke skript: `mcp\_smoke_yt_mcp.py`.

## Phase 0 — ZÁVĚR
Hotové a ověřené stavební kameny: **inbox/Monitor**, **login mapping**,
**provisioning skripty na reálných .FDB**, **yt-mcp live**, **Vagrant+Hyper-V
nainstalováno**. Zbytek je už náplň Phase 3 (běžící VM):
- [ ] `vagrant up` 1 Windows VM (base box + GUI session + autologon + SMB synced folder + snapshot).
- [ ] Firebird ve VM → plný login přes `openDB` (na hostu Firebird není; form ale renderuje).
- [ ] (volitelně) založit test issue AVE-1 s tagem `avensio-e2e` → vznikne tag + ověří write-path (mutace YouTracku — potřeba souhlas).
