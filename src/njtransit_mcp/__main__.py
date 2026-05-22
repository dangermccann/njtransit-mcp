"""Entrypoint: serve the MCP server over Streamable HTTP."""

from __future__ import annotations

import os

from .server import mcp


def main() -> None:
    mcp.settings.host = os.environ.get("HOST", "0.0.0.0")
    mcp.settings.port = int(os.environ.get("PORT", "8080"))
    mcp.run(transport="streamable-http")


if __name__ == "__main__":
    main()
