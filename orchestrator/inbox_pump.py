"""inbox_pump.py -- the orchestrator / I/O pump for the avensio e2e pipeline.

Mirror of the reference `inbox_pump.py`: poll YouTrack, append NDJSON events to
per-worker inboxes, route work, reap. NO `subprocess(claude, ...)` anywhere --
agents are long-lived interactive `claude` sessions that tail+Monitor their inbox
and reply via yt-mcp.

Routing (lifecycle is tag-based; see yt_client.set_lifecycle):
  - opt-in issue with no state, or state:queued, not yet handed to build
        -> append {kind:assign} to the BUILD inbox (build agent edits+builds).
  - state:built, not yet handed to a test worker
        -> pick a free test VM, append {kind:assign, build} to its inbox.
  - any new comment on an owned issue
        -> append {kind:comment} to the owner's inbox.

State is a small JSON file per issue under __automata/state/.
"""
from __future__ import annotations
import json
import time
from pathlib import Path

import vm_pool
from yt_client import YouTrackClient

ROOT = Path(__file__).resolve().parents[1]
IO_DIR = ROOT / "io"
STATE_DIR = ROOT / "state"
BUILD_WORKER = "build"
POLL_SECONDS = 60


def _append_inbox(worker: str, event: dict) -> None:
    """Append one NDJSON event. Python text-append uses a shared handle on Windows,
    so an agent's `tail -F` keeps reading (Phase 0: PowerShell Add-Content does NOT)."""
    inbox_dir = IO_DIR / worker
    inbox_dir.mkdir(parents=True, exist_ok=True)
    with (inbox_dir / "inbox.ndjson").open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(event, ensure_ascii=False) + "\n")


def _load_state(issue_id: str) -> dict:
    p = STATE_DIR / f"{issue_id}.json"
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    return {"issue": issue_id, "phase": None, "owner": None, "last_comment_id": None, "next_event_id": 1}


def _save_state(st: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    (STATE_DIR / f"{st['issue']}.json").write_text(
        json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def _lifecycle(issue: dict) -> str | None:
    for t in issue.get("tags", []):
        if t.startswith("state:"):
            return t.split(":", 1)[1]
    return None


def _free_test_worker(workers: list[str], busy: set[str]) -> str | None:
    for w in workers:
        if w in busy:
            continue
        if vm_pool.is_alive(w):
            return w
    return None


def tick(yt: YouTrackClient, workers: list[str]) -> None:
    issues = yt.poll_pipeline()
    if not issues:
        return

    # which test workers are currently committed to an issue
    busy: set[str] = set()
    states: dict[str, dict] = {}
    for iss in issues:
        st = _load_state(iss["id"])
        states[iss["id"]] = st
        if st.get("owner") and st["owner"] != BUILD_WORKER and st.get("phase") not in ("passed", "failed"):
            busy.add(st["owner"])

    for iss in issues:
        iid = iss["id"]
        st = states[iid]
        life = _lifecycle(iss)

        # 1) hand fresh/queued issues to the build agent
        if life in (None, "queued") and st.get("phase") not in ("building", "built", "testing"):
            st["next_event_id"] += 1
            _append_inbox(BUILD_WORKER, {
                "id": st["next_event_id"], "kind": "assign", "issue": iid,
                "summary": iss.get("summary"),
            })
            st["phase"] = "building"
            st["owner"] = BUILD_WORKER

        # 2) hand built issues to a free test worker
        elif life == "built" and st.get("phase") != "testing":
            w = _free_test_worker(workers, busy)
            if w:
                build_id = iss.get("fields", {}).get("Build") or f"{iid}-latest"
                st["next_event_id"] += 1
                _append_inbox(w, {
                    "id": st["next_event_id"], "kind": "assign", "issue": iid,
                    "build": build_id, "summary": iss.get("summary"),
                })
                st["phase"] = "testing"
                st["owner"] = w
                busy.add(w)

        # 3) forward any new comments to the current owner
        if st.get("owner"):
            comments = iss.get("comments", [])
            last = st.get("last_comment_id")
            new_seen = last
            for c in comments:
                if last is None or (c.get("id") and c["id"] > (last or "")):
                    st["next_event_id"] += 1
                    _append_inbox(st["owner"], {
                        "id": st["next_event_id"], "kind": "comment", "issue": iid,
                        "author": c.get("author"), "body": c.get("text"),
                    })
                    new_seen = c.get("id")
            st["last_comment_id"] = new_seen

        _save_state(st)


def main() -> None:
    import os
    workers = vm_pool.worker_names(int(os.environ.get("AVENSIO_WORKERS", "1")))
    yt = YouTrackClient()
    print(f"inbox_pump up. project={yt.project} label={yt.label} workers={workers}", flush=True)
    try:
        while True:
            try:
                tick(yt, workers)
            except Exception as e:  # never let one bad tick kill the daemon
                print(f"tick error: {type(e).__name__}: {e}", flush=True)
            time.sleep(POLL_SECONDS)
    finally:
        yt.close()


if __name__ == "__main__":
    main()
