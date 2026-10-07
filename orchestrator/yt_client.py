"""Shared YouTrack REST client for the avensio e2e pipeline.

Used by both the orchestrator (inbound poll) and yt_mcp.py (outbound).
Dependency-light: uses httpx (already pulled in by the `mcp` package).

Credentials are read from __automata/config/auth.env (gitignored):
    YOUTRACK_BASE_URL=https://org.youtrack.cloud
    YOUTRACK_TOKEN=perm:xxxx
    YOUTRACK_PROJECT=AVE
    YOUTRACK_LABEL=avensio-e2e
"""
from __future__ import annotations
import os
from pathlib import Path
from typing import Any, Optional

import httpx

# auth.env lives next to this file's grandparent: __automata/config/auth.env
_CONFIG_ENV = Path(__file__).resolve().parents[1] / "config" / "auth.env"


def load_auth(env_path: Path | str | None = None) -> dict[str, str]:
    """Parse a KEY=VALUE .env file. Lines starting with # and blanks ignored."""
    path = Path(env_path) if env_path else _CONFIG_ENV
    if not path.exists():
        raise FileNotFoundError(
            f"auth.env not found at {path}. Copy config/auth.env.example and fill it in."
        )
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        out[key.strip()] = val.strip()
    return out


# YouTrack field projections reused across calls.
_ISSUE_FIELDS = (
    "idReadable,summary,description,"
    "customFields(name,value(name)),"
    "tags(name),"
    "comments(id,text,created,author(login,fullName)),"
    "attachments(id,name)"
)


class YouTrackError(RuntimeError):
    pass


class YouTrackClient:
    def __init__(self, auth: dict[str, str] | None = None, timeout: float = 30.0):
        a = auth or load_auth()
        base = a.get("YOUTRACK_BASE_URL", "").rstrip("/")
        token = a.get("YOUTRACK_TOKEN", "")
        if not base or not token:
            raise YouTrackError("YOUTRACK_BASE_URL and YOUTRACK_TOKEN are required.")
        self.base = base
        self.project = a.get("YOUTRACK_PROJECT", "")
        self.label = a.get("YOUTRACK_LABEL", "avensio-e2e")
        self._auth = a
        self._client = httpx.Client(
            base_url=f"{base}/api",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            },
            timeout=timeout,
        )

    # ---- low-level ----
    def _request(self, method: str, path: str, **kw) -> Any:
        r = self._client.request(method, path, **kw)
        if r.status_code >= 400:
            raise YouTrackError(f"{method} {path} -> {r.status_code}: {r.text[:500]}")
        if r.status_code == 204 or not r.content:
            return None
        return r.json()

    # ---- reads ----
    def get_issue(self, issue_id: str) -> dict:
        """Full issue snapshot: summary, description, state, tags, comments, attachments."""
        data = self._request("GET", f"/issues/{issue_id}", params={"fields": _ISSUE_FIELDS})
        return _flatten_issue(data)

    def search_issues(self, query: str, limit: int = 100) -> list[dict]:
        data = self._request(
            "GET", "/issues",
            params={"query": query, "fields": _ISSUE_FIELDS, "$top": limit},
        )
        return [_flatten_issue(d) for d in (data or [])]

    def poll_pipeline(self, states: list[str] | None = None) -> list[dict]:
        """Issues in this project carrying the opt-in label, optionally filtered by State.

        On a greenfield instance the opt-in tag does not exist until the first
        issue uses it; YouTrack 400s on `tag: {x}` for an unknown tag. Treat that
        as "no work yet" and return []."""
        q = f"project: {{{self.project}}} tag: {{{self.label}}}" if self.project else f"tag: {{{self.label}}}"
        if states:
            # second tag: clause ANDs with the opt-in; commas inside it are OR.
            q += " tag: " + ", ".join(f"{{state:{s}}}" for s in states)
        try:
            return self.search_issues(q)
        except YouTrackError as e:
            if "isn't used for the tag field" in str(e) or "invalid_query" in str(e):
                return []
            raise

    # ---- writes ----
    def post_comment(self, issue_id: str, body: str) -> dict:
        return self._request(
            "POST", f"/issues/{issue_id}/comments",
            params={"fields": "id,text,created"},
            json={"text": body},
        )

    def set_state(self, issue_id: str, state: str) -> dict:
        """Set the single-value State custom field by name."""
        payload = {
            "customFields": [
                {
                    "name": "State",
                    "$type": "StateIssueCustomField",
                    "value": {"name": state},
                }
            ]
        }
        return self._request(
            "POST", f"/issues/{issue_id}",
            params={"fields": "customFields(name,value(name))"},
            json=payload,
        )

    def attach_file(self, issue_id: str, file_path: str) -> dict:
        p = Path(file_path)
        if not p.exists():
            raise YouTrackError(f"attach_file: {p} does not exist")
        with p.open("rb") as fh:
            files = {"file": (p.name, fh, "application/octet-stream")}
            res = self._request(
                "POST", f"/issues/{issue_id}/attachments",
                params={"fields": "id,name"},
                files=files,
            )
        # YouTrack returns a list of created attachments; normalize to the first.
        if isinstance(res, list):
            return res[0] if res else {}
        return res

    def create_issue(self, summary: str, description: str = "") -> dict:
        """Create an issue in the configured project. Returns flattened issue."""
        if not self.project:
            raise YouTrackError("YOUTRACK_PROJECT is required to create issues.")
        proj = self._request("GET", "/admin/projects",
                             params={"fields": "shortName,id", "$top": 100})
        match = next((p for p in proj if p.get("shortName") == self.project), None)
        if not match:
            raise YouTrackError(f"Project {self.project} not found.")
        data = self._request(
            "POST", "/issues",
            params={"fields": _ISSUE_FIELDS},
            json={"project": {"id": match["id"]}, "summary": summary, "description": description},
        )
        return _flatten_issue(data)

    def state_values(self) -> list[str]:
        """Available State field values for the configured project (empty if none/not found)."""
        proj = self._request("GET", "/admin/projects",
                             params={"fields": "shortName,id", "$top": 100})
        match = next((p for p in proj if p.get("shortName") == self.project), None)
        if not match:
            return []
        cfs = self._request("GET", f"/admin/projects/{match['id']}/customFields",
                           params={"fields": "field(name),bundle(values(name))", "$top": 100})
        for cf in cfs or []:
            if (cf.get("field") or {}).get("name") == "State":
                return [v.get("name") for v in ((cf.get("bundle") or {}).get("values") or [])]
        return []

    def _find_or_create_tag(self, name: str) -> dict:
        """YouTrack won't attach a tag by name alone — resolve to an id, creating it if needed."""
        existing = self._request("GET", "/issueTags",
                                 params={"fields": "id,name", "$top": 1000}) or []
        for t in existing:
            if t.get("name") == name:
                return t
        return self._request("POST", "/issueTags",
                            params={"fields": "id,name"}, json={"name": name})

    def add_tag(self, issue_id: str, tag: str) -> dict:
        t = self._find_or_create_tag(tag)
        return self._request(
            "POST", f"/issues/{issue_id}/tags",
            params={"fields": "id,name"},
            json={"id": t["id"]},
        )

    def set_lifecycle(self, issue_id: str, state: str) -> dict:
        """Lifecycle via tags (mirrors the reference plan's label scheme): apply
        state:<x> and remove any other state:* tags from the issue."""
        # remove existing state:* tags
        cur = self.get_issue(issue_id)
        for tname in cur.get("tags", []):
            if tname.startswith("state:") and tname != f"state:{state}":
                tag = self._find_or_create_tag(tname)
                try:
                    self._request("DELETE", f"/issues/{issue_id}/tags/{tag['id']}")
                except YouTrackError:
                    pass
        return self.add_tag(issue_id, f"state:{state}")

    def close(self) -> None:
        self._client.close()


def _flatten_issue(data: dict | None) -> dict:
    """Reduce the verbose YouTrack shape to a flat, agent-friendly dict."""
    if not data:
        return {}
    fields = {}
    for cf in data.get("customFields", []) or []:
        val = cf.get("value")
        if isinstance(val, dict):
            fields[cf["name"]] = val.get("name")
        elif isinstance(val, list):
            fields[cf["name"]] = [v.get("name") for v in val if isinstance(v, dict)]
        else:
            fields[cf["name"]] = val
    return {
        "id": data.get("idReadable"),
        "summary": data.get("summary"),
        "description": data.get("description"),
        "state": fields.get("State"),
        "fields": fields,
        "tags": [t.get("name") for t in (data.get("tags") or [])],
        "comments": [
            {
                "id": c.get("id"),
                "author": (c.get("author") or {}).get("login"),
                "created": c.get("created"),
                "text": c.get("text"),
            }
            for c in (data.get("comments") or [])
        ],
        "attachments": [a.get("name") for a in (data.get("attachments") or [])],
    }
