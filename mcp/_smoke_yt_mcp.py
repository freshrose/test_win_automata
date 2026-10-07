"""Smoke-test: launch yt_mcp.py over stdio, list tools, call yt_get_issue read-path.
Verifies the MCP handshake works (i.e. `claude --mcp-config` would register it)."""
import asyncio, sys
from pathlib import Path
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

HERE = Path(__file__).resolve().parent


async def main() -> None:
    params = StdioServerParameters(command=sys.executable, args=[str(HERE / "yt_mcp.py")])
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            names = [t.name for t in tools.tools]
            print("TOOLS:", names)
            # read-only call against a likely-nonexistent issue: proves the tool path + client both work
            res = await session.call_tool("yt_get_issue", {"params": {"issue_id": "AVE-999999"}})
            txt = res.content[0].text if res.content else ""
            print("yt_get_issue(AVE-999999) ->", txt[:200])


if __name__ == "__main__":
    asyncio.run(main())
