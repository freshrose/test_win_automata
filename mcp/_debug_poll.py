import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "orchestrator"))
from yt_client import YouTrackClient, YouTrackError

yt = YouTrackClient()

def try_q(label, q):
    try:
        res = yt._request("GET", "/issues", params={"query": q, "fields": "idReadable,tags(name)", "$top": 20})
        print(f"[OK] {label}: {q!r} -> {[r.get('idReadable') for r in res]}")
    except YouTrackError as e:
        print(f"[ERR] {label}: {q!r} -> {str(e)[:160]}")

try_q("opt-in only",     f"project: {{{yt.project}}} tag: {{{yt.label}}}")
try_q("bare tag",        f"tag: {{{yt.label}}}")
try_q("state tag braces", "tag: {state:queued}")
try_q("state tag quoted", 'tag: state:queued')
try_q("combined",        f"project: {{{yt.project}}} tag: {{{yt.label}}} tag: {{state:queued}}")
yt.close()
