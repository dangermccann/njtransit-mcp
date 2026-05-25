"""MCP server exposing NJ Transit rail tools over Streamable HTTP."""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from typing import Any

from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings

from .njt_client import NJTClient

load_dotenv()
logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))

_client: NJTClient | None = None


def _get_client() -> NJTClient:
    global _client
    if _client is None:
        _client = NJTClient()
    return _client


@asynccontextmanager
async def lifespan(_app):
    try:
        yield
    finally:
        if _client is not None:
            await _client.aclose()


mcp = FastMCP(
    "njtransit",
    instructions=(
        "Tools for querying NJ Transit commuter rail. Station codes are 3-5 letter "
        "abbreviations (e.g. NY=New York Penn, NWK=Newark Penn, HOB=Hoboken). "
        "Call list_stations to discover codes."
    ),
    lifespan=lifespan,
    # Disable localhost-only DNS rebinding protection so the server accepts
    # requests from any host (required for Cloud Run and other hosted deployments).
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)


@mcp.tool()
async def list_stations() -> Any:
    """List every NJ Transit rail station with its code and full name.

    Use this to resolve a human-readable station name to the short code
    required by the other tools.
    """
    return await _get_client().station_list()


@mcp.tool()
async def upcoming_departures(station: str) -> Any:
    """Get the next ~19 trains departing a station (the station 'big board').

    Args:
        station: 2-5 letter NJ Transit station code (e.g. "NY", "NWK", "HOB").
    """
    return await _get_client().upcoming_departures(station)


@mcp.tool()
async def station_schedule(station: str, include_non_njt: bool = False) -> Any:
    """Get the full upcoming schedule for a station.

    Args:
        station: NJ Transit station code.
        include_non_njt: Include Amtrak/MetroNorth trains that also serve the station.
    """
    return await _get_client().station_schedule(station, njt_only=not include_non_njt)


@mcp.tool()
async def train_stops(train_id: str) -> Any:
    """Get the stop list, scheduled times, and live ETAs for a specific train.

    Args:
        train_id: Train number, e.g. "3925".
    """
    return await _get_client().train_stops(train_id)


@mcp.tool()
async def active_trains() -> Any:
    """Get live position and status for every train currently operating.

    Returns a large payload; prefer train_stops or upcoming_departures when
    you know the train or station you care about.
    """
    return await _get_client().vehicle_data()
