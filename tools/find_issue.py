# -*- coding: utf-8 -*-
import sys
sys.path.insert(0, r"C:\automata\orchestrator")
from yt_client import YouTrackClient
c = YouTrackClient()
res = c._request("GET", "/issues",
                 params={"fields": "idReadable,summary", "query": "project: %s" % c.project, "$top": 20}) or []
match = [i for i in res if "[e2e smoke] avensio login" in (i.get("summary") or "")]
if not match:
    print("NONE FOUND"); sys.exit(0)
rid = match[0]["idReadable"]
try:
    c.add_tag(rid, c.label)
    tagged = "tagged " + c.label
except Exception as e:
    tagged = "tag WARN: %s" % e
print("ISSUE", rid, "|", tagged)
