#!/usr/bin/env python3
"""yt-mcp — stdio MCP server: YouTrack outbound for avensio e2e agents.

Mirror of the reference `jcw-mcp`: each interactive `claude` (build agent on the
host, test agent in a VM) spawns one of these over stdio and uses it to talk
back to YouTrack — post comments, flip State, attach screenshots/logs, claim
ownership. Inbound (new issues/comments) arrives via the file inbox + Monitor,
not through this server.

Run standalone for a smoke test:
    python yt_mcp.py            # serves stdio JSON-RPC

Registered in an agent via:  claude --mcp-config __automata\\mcp\\yt-mcp.json
"""
from __future__ import annotations
import sys
from pathlib import Path

from pydantic import BaseModel, Field, ConfigDict
from mcp.server.fastmcp import FastMCP

# allow `import yt_client` from the sibling orchestrator package
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "orchestrator"))
from yt_client import YouTrackClient, YouTrackError  # noqa: E402

mcp = FastMCP("yt_mcp")

# Single shared client for the lifetime of this stdio server (one per agent).
_client: YouTrackClient | None = None


def _yt() -> YouTrackClient:
    global _client
    if _client is None:
        _client = YouTrackClient()
    return _client


class _Base(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")


class IssueRef(_Base):
    issue_id: str = Field(..., description="Readable issue id, e.g. AVE-12.")


class CommentInput(IssueRef):
    body: str = Field(..., description="Markdown comment body to post on the issue.")


class StateInput(IssueRef):
    state: str = Field(..., description="Lifecycle state (lowercase): queued/building/built/testing/passed/failed/needs-fix. Applied as a state:<x> tag.")


class AttachInput(IssueRef):
    file_path: str = Field(..., description="Absolute path to a file to upload (screenshot, build log, transcript).")


class ClaimInput(IssueRef):
    worker: str = Field(..., description="Worker identity claiming the issue, e.g. build-host or test1.")


@mcp.tool(name="yt_get_issue")
def yt_get_issue(params: IssueRef) -> dict:
    """Read an issue: summary, description, State, tags, comments, attachments."""
    try:
        return {"success": True, "issue": _yt().get_issue(params.issue_id)}
    except (YouTrackError, FileNotFoundError) as e:
        return {"success": False, "error": str(e)}


@mcp.tool(name="yt_post_comment")
def yt_post_comment(params: CommentInput) -> dict:
    """Post a comment on the issue (the pipeline's primary message channel)."""
    try:
        c = _yt().post_comment(params.issue_id, params.body)
        return {"success": True, "comment_id": (c or {}).get("id")}
    except (YouTrackError, FileNotFoundError) as e:
        return {"success": False, "error": str(e)}


@mcp.tool(name="yt_set_state")
def yt_set_state(params: StateInput) -> dict:
    """Transition the issue lifecycle (queued/building/built/testing/passed/failed/needs-fix).

    Implemented as a state:<x> tag (the AVE project has no State custom field),
    removing any prior state:* tag."""
    try:
        _yt().set_lifecycle(params.issue_id, params.state.lower())
        return {"success": True, "state": params.state.lower()}
    except (YouTrackError, FileNotFoundError) as e:
        return {"success": False, "error": str(e)}


@mcp.tool(name="yt_attach_file")
def yt_attach_file(params: AttachInput) -> dict:
    """Upload a file (screenshot / build log / transcript) as an issue attachment."""
    try:
        a = _yt().attach_file(params.issue_id, params.file_path)
        return {"success": True, "name": (a or {}).get("name")}
    except (YouTrackError, FileNotFoundError) as e:
        return {"success": False, "error": str(e)}


@mcp.tool(name="yt_claim")
def yt_claim(params: ClaimInput) -> dict:
    """Mark ownership by tagging the issue wip-<worker> (visible claim marker)."""
    try:
        _yt().add_tag(params.issue_id, f"wip-{params.worker}")
        return {"success": True, "worker": params.worker}
    except (YouTrackError, FileNotFoundError) as e:
        return {"success": False, "error": str(e)}


if __name__ == "__main__":
    mcp.run(transport="stdio")
