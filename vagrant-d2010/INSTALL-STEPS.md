# Avensio e2e — D2010 reference worker

Parallel copy of `../vagrant`, tuned to run the **legacy Delphi 2010** `avensio.exe`
as a reference run alongside the new Delphi 13 worker (`avensio-test1`).

## What differs from the D13 worker
| | D13 worker (`../vagrant`) | D2010 worker (this) |
|---|---|---|
| worker name | `test1` | `d2010-test1` |
| Hyper-V VM | `avensio-test1` | `avensio-d2010-test1` |
| SUT exe | `_rsm\avensio\__bin` (D13 build) | staged D2010 build (`C:\avensio-d2010\__bin`) |
| build source | D13 container artifact | `var-D2010\avensio\avensio`, pushed over PowerShell Direct |
| selection | default `ExeDir` | `AVENSIO_EXEDIR` machine env (scripts honor it) |
| Firebird / DB | FB 2.5 + `SKOLA_test.FDB` | **identical** (FB 2.5 + `SKOLA_test.FDB`) |

Both workers are driven the same way: **PowerShell Direct over the VMBus** for both
control and file transfer (the host firewall scopes SMB to the Netbird overlay, so
the Default-Switch VMs do not use SMB). Per-worker inbox: `io/d2010-test1`.

## Stage the SUT (host, after `vagrant up` and after each rebuild)
The legacy build is pushed into the VM over PowerShell Direct -- no SMB, no firewall
change:
```powershell
cd C:\Users\rosa\_rsm\__automata\vagrant-d2010
powershell -ExecutionPolicy Bypass -File .\stage-d2010-build.host.ps1
```
This copies `avensio.exe` + `reporty\ skripty\ set\` to `C:\avensio-d2010\__bin` in
the VM and sets the `AVENSIO_EXEDIR` machine env var that the shared
`run-avensio.ps1` / `provision-test-db.ps1` read.

## Boot (elevated PowerShell)
```powershell
$env:VAGRANT_DEFAULT_PROVIDER = "hyperv"
cd C:\Users\rosa\_rsm\__automata\vagrant-d2010
vagrant up d2010-test1
vagrant snapshot save  d2010-test1 clean
```
Restore the clean state between runs: `vagrant snapshot restore d2010-test1 clean`.

## Control pipeline (driven EXACTLY like avensio-test1 — host over PowerShell Direct)
After `vagrant up`, install the VM-local control pieces (MCP, dvcl, vmact task) once:
```powershell
powershell -ExecutionPolicy Bypass -File .\setup-d2010-control.host.ps1
```
This pushes `delphi_vcl_mcp.py` / `dvcl.py` / `act-runner.ps1` to `C:\avensio`,
registers the `delphi-mcp` / `vmact` / `avensio-agent` scheduled tasks (interactive
session), and starts the delphi_vcl MCP on `127.0.0.1:8765`. The host then drives the
VM with the SAME scripts as test1, just `-VMName avensio-d2010-test1`:
```powershell
cd ..\agents
.\vmrun.ps1 -Tool delphi_connect_app -ArgsJson '{"process_name":"avensio.exe"}' -VMName avensio-d2010-test1
.\vmact.ps1 -Save shot.png -VMName avensio-d2010-test1     # raw click/type + screenshot
```

## Run a reference test (old avensio against a fresh DB)
1. Stage the DB template once (PSDirect): copy `SKOLA_test.FDB` to the VM's
   `C:\DB\_templates\` (the host scripts/`stage` do this; 547 MB over VMBus).
2. Provision a fresh per-run DB + `avensio.ini` (writes next to the staged exe via
   `AVENSIO_EXEDIR`):
   `C:\avensio\provision-test-db.ps1 -RunId <id> -TemplateFdb C:\DB\_templates\SKOLA_test.FDB`
3. Launch avensio **in the interactive session** (session 1, so the MCP/pywinauto can
   see it) via the `avensio-launch` scheduled task, then connect + drive via vmrun/vmact.
   Verified: launches to the **AVENSIO SW 3.4.6.17 login form** with the provisioned org.

## D2010-specific runtime gotchas (baked into provisioning)
- **gds32.dll** — old avensio uses the InterBase/IBX client, not FireDAC. `install-firebird.ps1`
  copies Firebird's `fbclient.dll` as `C:\Windows\SysWOW64\gds32.dll` (avensio is 32-bit).
- **VC++ runtime / pywin32** — `pywinauto` needs `win32ui` -> `mfc140u.dll`; `install-runtime.ps1`
  runs the pywin32 post-install and installs the VC++ 2015-2022 x64 redistributable.

## Authentication
`claude` must be authenticated once in the VM console (`claude login`) only if you use
the in-VM `avensio-agent` (autonomous operator). The host-driven vmrun/vmact path does
not require it.
