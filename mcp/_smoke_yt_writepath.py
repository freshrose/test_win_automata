"""One-time write-path validation against the real AVE project:
inspect State values, create AVE smoke issue, tag it, comment, attach, set state."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "orchestrator"))
from yt_client import YouTrackClient

import sys as _sys
yt = YouTrackClient()
# reuse an existing smoke issue id if passed, else create one
iid = _sys.argv[1] if len(_sys.argv) > 1 else None
if not iid:
    issue = yt.create_issue(
        summary="[e2e smoke] avensio pipeline write-path check",
        description="Auto-created to validate the yt-mcp write path and bootstrap tags. Safe to delete.",
    )
    iid = issue["id"]
    print("created issue:", iid)
else:
    print("reusing issue:", iid)

yt.add_tag(iid, yt.label)
print("tagged opt-in:", yt.label)

yt.set_lifecycle(iid, "queued")
print("lifecycle -> state:queued")

yt.post_comment(iid, "yt-mcp write-path OK: comment posted by the pipeline smoke test.")
print("comment posted")

shot = Path(__file__).resolve().parents[1] / "runs" / "login-form.png"
if shot.exists():
    a = yt.attach_file(iid, str(shot))
    print("attached:", (a or {}).get("name"))
else:
    print("no screenshot to attach at", shot)

# verify by reading back
back = yt.get_issue(iid)
print("readback tags:", back.get("tags"), "| attachments:", back.get("attachments"))

# verify pipeline poll now finds it under the queued state
found = [i["id"] for i in yt.poll_pipeline(states=["queued"])]
print("poll_pipeline(queued) finds:", found)

print("DONE. Issue:", iid)
yt.close()
