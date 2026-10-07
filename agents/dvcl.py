#!/usr/bin/env python3
"""dvcl.py -- one-shot client for the VM's delphi_vcl MCP (FastMCP streamable HTTP).

Lets the host driver (via PSDirect) issue a single GUI action to the in-VM MCP
server, which drives avensio on the interactive desktop. Server keeps the
connected-app in a global, so state persists across these one-shot calls.

Usage:
  python dvcl.py <tool> '<json-args>' [outfile]
    <tool>      e.g. delphi_connect_app, delphi_click, delphi_screenshot
    <json-args> the tool's `params` object as JSON (default {})
    [outfile]   for delphi_screenshot: decode data_base64 -> save PNG here
"""
import asyncio, sys, json, base64

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

URL = "http://127.0.0.1:8765/mcp"
HEADERS = {"Authorization": "Bearer anyone-can-vibe-now"}


async def main() -> int:
    tool = sys.argv[1]
    raw = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else ""
    if raw.startswith("@"):
        with open(raw[1:], "r", encoding="utf-8-sig") as fh:
            raw = fh.read().strip()
    args = json.loads(raw) if raw else {}
    outfile = sys.argv[3] if len(sys.argv) > 3 else None

    from mcp import ClientSession
    from mcp.client.streamable_http import streamablehttp_client

    async with streamablehttp_client(URL, headers=HEADERS) as (r, w, _):
        async with ClientSession(r, w) as session:
            await session.initialize()
            res = await session.call_tool(tool, {"params": args})
            texts = [c.text for c in res.content if getattr(c, "text", None)]
            payload = "\n".join(texts)

    if outfile and tool == "delphi_screenshot":
        try:
            obj = json.loads(payload)
            if obj.get("success") and obj.get("data_base64"):
                raw = base64.b64decode(obj["data_base64"])
                with open(outfile, "wb") as fh:
                    fh.write(raw)
                print(f"SAVED {outfile} ({len(raw)} bytes)")
                return 0
            print("SCREENSHOT_FAIL " + payload[:300])
            return 1
        except Exception as exc:
            print(f"SCREENSHOT_ERR {exc}: {payload[:300]}")
            return 1

    print(payload)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
