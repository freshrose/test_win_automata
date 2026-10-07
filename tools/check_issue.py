# -*- coding: utf-8 -*-
import sys
sys.path.insert(0, r"C:\automata\orchestrator")
from yt_client import YouTrackClient
rid = sys.argv[1] if len(sys.argv) > 1 else "AVE-3"
c = YouTrackClient()
iss = c.get_issue(rid)
print("ISSUE", iss.get("id"), "| state:", iss.get("state"), "| tags:", iss.get("tags"))
print("attachments:", iss.get("attachments"))
print("--- comments ---")
for cm in iss.get("comments") or []:
    print(f"[{cm.get('author')}] {cm.get('text')}")
