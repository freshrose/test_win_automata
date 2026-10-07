# avensio e2e — build & test process flow

End-to-end flow of the avensio.exe continuous build+test pipeline as actually
implemented under `__automata\`. **Edit+build** is a single serialized queue on
the host; **e2e GUI tests** run in parallel, one isolated Hyper-V VM per worker.
YouTrack is both the work queue and the message bus; everything is auditable
(build log + transcript + screenshots) per issue.

Transport rule (mirrors the jcw-worker pattern): **inbound = files** (per-worker
NDJSON inboxes on the SMB share), **outbound = MCP** (agents post comments /
state / attachments straight to YouTrack via `yt-mcp`). The orchestrator is an
inbound pump only — it never spawns `claude`.

---

## 1. Architecture (components + transport)

```mermaid
flowchart TB
    subgraph cloud["☁ YouTrack (cloud)"]
        YT["Project AVE<br/>lifecycle via tags state:*<br/>queued→building→built→testing→passed/failed/needs-fix"]
    end

    subgraph host["🖥 Host (Docker engine + Hyper-V)"]
        PUMP["inbox_pump.py<br/>poll YT 60s · route by state<br/>vm_pool.py (vagrant CLI) · yt_client.py (REST)"]
        BUILD["Build operator<br/>long-lived interactive claude<br/>+ yt-mcp"]
        DOCKER["Delphi 13 container<br/>build-avensio.ps1 + resolve-bpl.ps1"]
        ART["\\share\artifacts\&lt;issue&gt;-&lt;commit&gt;\<br/>avensio.exe + .bpl"]
        VIEW["server.js (Node) :8088<br/>gallery + YT state badges"]
        RUNS[("__automata\runs\<br/>screenshots + logs")]
    end

    subgraph vm["💻 Test VM #1..N (Hyper-V, gusztavvargadr/windows-10)"]
        AGENT["agent_pty.py → interactive claude<br/>CLAUDE.md = test-operator.md"]
        DVCL["delphi_vcl MCP<br/>127.0.0.1:8765 (single app, serialized)"]
        FB["Firebird 2.5 + .FDB templates"]
        EXE["avensio.exe (from artifact)"]
    end

    YT -- "poll REST" --> PUMP
    PUMP -- "append NDJSON<br/>io/build/inbox.ndjson" --> BUILD
    PUMP -- "append NDJSON<br/>io/test1/inbox.ndjson (SMB)" --> AGENT
    PUMP -- "vagrant up/snapshot" --> vm

    BUILD --> DOCKER --> ART
    BUILD -- "comment/state/attach (yt-mcp)" --> YT
    ART -- "test VM pulls build" --> EXE

    AGENT --> DVCL --> EXE
    EXE --> FB
    AGENT -- "screenshots (SMB)" --> RUNS
    AGENT -- "comment/state/attach (yt-mcp)" --> YT

    RUNS --> VIEW
    YT -- "state tags" --> VIEW
    VIEW -- "Netbird 100.54.7.101:8088" --> USER([Operator browser])
```

---

## 2. Issue lifecycle (state machine)

State lives as `state:*` tags on the YouTrack issue (see `yt_client.set_lifecycle`).
The pump routes purely off these tags + a small per-issue JSON in `state/`.

```mermaid
stateDiagram-v2
    [*] --> queued: opt-in issue (label avensio-e2e)
    queued --> building: pump → BUILD inbox {kind:assign}<br/>build agent yt_claim
    building --> built: container build OK<br/>artifact published
    building --> needs_fix: build fails
    needs_fix --> building: code fixed, re-assigned
    built --> testing: pump → free test VM {kind:assign,build}<br/>test agent yt_claim
    testing --> passed: scenario OK
    testing --> failed: defect / crash
    failed --> queued: fix requested (new build)
    passed --> [*]
```

---

## 3. Build cycle (build operator, on `assign`)

One build at a time — shared working tree + heavy container build are never
parallelized.

```mermaid
sequenceDiagram
    participant P as inbox_pump
    participant B as Build operator (host)
    participant YT as YouTrack (yt-mcp)
    participant R as avensio repo
    participant D as Delphi13 container
    participant A as \\share\artifacts

    P->>B: append {kind:assign, issue, summary}
    Note over B: tail -F io/build/inbox.ndjson + Monitor
    B->>YT: yt_claim(issue,"build") · set_state(building)
    B->>YT: yt_get_issue (understand change)
    B->>R: edit on issue branch (ASCII-safe, beware U+FFFD)
    B->>D: build-avensio.ps1 (UsePackages=true, NO_MADEXCEPT)
    B->>D: resolve-bpl.ps1 (gather runtime .bpl)
    alt build OK
        B->>A: copy avensio.exe + .bpl → artifacts/issue-commit/
        B->>YT: attach build log · comment summary
        B->>YT: set_state(built) → triggers test workers
    else build fails
        B->>YT: attach log · comment error
        B->>YT: set_state(needs-fix)
    end
    Note over B: ensure no avensio.exe running (locks __bin\avensio.exe)
```

---

## 4. Test cycle (test operator in VM, on `assign`)

```mermaid
sequenceDiagram
    participant P as inbox_pump
    participant T as Test operator (VM)
    participant YT as YouTrack (yt-mcp)
    participant DB as provision-test-db.ps1
    participant V as delphi_vcl MCP
    participant E as avensio.exe
    participant R as runs (SMB to host)

    P->>T: append kind=assign (issue, build) via SMB inbox
    Note over T: poll wc -l + sed, not tail -F (SMB appends invisible)
    T->>YT: yt_claim(issue,worker) then set_state(testing)
    T->>DB: copy clean .FDB + write avensio.ini
    T->>E: run-avensio.ps1 -Action start
    T->>V: delphi_connect_app avensio.exe
    loop while top window is TfrmNewTrialDialog
        T->>V: click Zavrit (dismiss DevExpress trial nag)
    end
    Note over T,E: TLoginForm, DB connects UNI_OMEGA/omega internally
    T->>V: type Uzivatel + Heslo (av-heslo), click OK
    Note over E: __bin/skripty must hold av_NNN.sql or fatal exit
    loop each scenario step (yt_get_issue)
        T->>V: drive GUI
        T->>R: delphi_screenshot to runs/issue/build/NN-step.png
    end
    T->>YT: attach screenshots + transcript, comment pass/fail
    T->>YT: set_state passed OR failed
    T->>E: run-avensio.ps1 -Action stop (force; WM_CLOSE wont kill at login)
    T->>DB: delete per-run .FDB
```

---

## 5. VM provisioning & agent boot

```mermaid
flowchart TB
    UP["vagrant up test1<br/>(provider hyperv, linked_clone)"] --> SETW["set-worker: AVENSIO_WORKER=test1 (machine env)"]
    SETW --> AUTO["autologon.ps1<br/>autologon + never lock (interactive desktop for UIA)"]
    AUTO --> FILES["upload LOCAL copies (avoid stale SMB):<br/>vm-bootstrap.ps1, agent_pty.py, CLAUDE.md=test-operator.md"]
    FILES --> RT["install-runtime.ps1<br/>Python, delphi_vcl MCP, Claude Code"]
    RT --> FBI["install-firebird.ps1 + .FDB templates"]
    FBI --> LOGON["logon scheduled task →<br/>mount-shares.ps1 (New-SmbGlobalMapping → C:\automata)"]
    LOGON --> PTY["agent_pty.py (pywinpty ConPTY)<br/>keeps interactive claude alive"]
    PTY --> BOOT["sends single word: boot"]
    BOOT --> POLL["claude: CLAUDE.md drives rest →<br/>poll inbox + Monitor, wait for assign"]
```

Key constraints baked in: GUI automation needs an **active interactive desktop**
(autologon, no screen lock); the SMB share is mounted machine-wide via
`New-SmbGlobalMapping` (the per-session vagrant SMB mount isn't visible to the
logon task's session); bootstrap files are uploaded to local `C:\avensio\`
because SMB can serve stale copies at boot.

---

## 6. Viewer / dashboard data flow

```mermaid
flowchart LR
    RUNS[("runs/issue/build/*.png + logs")] --> WALK["server.js walk()<br/>group folders w/ images"]
    AUTHENV["config\auth.env<br/>(YT base + token, gitignored)"] --> YTS["ytState() fetch tags<br/>(state:*, 30s cache)"]
    WALK --> API["/api/runs JSON<br/>runs[] {key,label,state,when,shots,files}"]
    YTS --> API
    API --> IDX["index.html gallery<br/>humanized captions · lightbox · PASS/FAIL/TESTING badges"]
    IDX -. "bind 0.0.0.0:8088" .-> NB["Netbird 100.54.7.101:8088<br/>(private mesh)"]
    NB --> BROWSER([Operator browser])
```

---

## Notes / non-goals
- **No `claude -p`** and no Agent SDK — only long-lived interactive `claude`
  sessions that poll their inbox and reply via `yt-mcp`.
- **Build is intentionally serialized** (one queue, one container build).
- Tests parallelize by **VM isolation only** — `delphi_vcl` is a single global
  app with `ThreadPoolExecutor(max_workers=1)` and drives the physical desktop,
  so 1 VM = 1 desktop = 1 worker.
- DB isolation = fresh `.FDB` copy per test; deep reset = `vagrant snapshot restore`.
- See memory: `avensio-e2e-pipeline`, `avensio-login-runtime`,
  `avensio-encoding-corruption`, `avensio-container-build`.
```
