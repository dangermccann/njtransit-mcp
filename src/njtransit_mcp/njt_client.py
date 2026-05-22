"""Async client for the NJ Transit Rail Data v3 API.

The API uses POST + form-encoded bodies. Authentication is a session token
returned by `getToken` (username + password). Tokens are reused until the
upstream returns an auth error, at which point we refresh once and retry.
"""

from __future__ import annotations

import asyncio
import logging
import os
from typing import Any

import httpx

log = logging.getLogger(__name__)

DEFAULT_BASE_URL = "https://raildata.njtransit.com/api/TrainData"


class NJTAuthError(RuntimeError):
    pass


class NJTClient:
    def __init__(
        self,
        username: str | None = None,
        password: str | None = None,
        base_url: str | None = None,
        timeout: float = 15.0,
    ) -> None:
        self._username = username or os.environ["NJTRANSIT_USERNAME"]
        self._password = password or os.environ["NJTRANSIT_PASSWORD"]
        self._base_url = (base_url or os.environ.get("NJTRANSIT_BASE_URL", DEFAULT_BASE_URL)).rstrip("/")
        self._http = httpx.AsyncClient(timeout=timeout)
        self._token: str | None = None
        self._token_lock = asyncio.Lock()

    async def aclose(self) -> None:
        await self._http.aclose()

    async def _get_token(self, force_refresh: bool = False) -> str:
        async with self._token_lock:
            if self._token and not force_refresh:
                return self._token
            resp = await self._http.post(
                f"{self._base_url}/getToken",
                data={"username": self._username, "password": self._password},
            )
            resp.raise_for_status()
            payload = resp.json()
            token = payload.get("UserToken") or payload.get("Authenticated") or payload.get("token")
            if not token or token == "0":
                raise NJTAuthError(f"NJ Transit getToken returned no usable token: {payload!r}")
            self._token = token
            return token

    async def _post(self, path: str, params: dict[str, str]) -> Any:
        token = await self._get_token()
        body = {"token": token, **params}
        resp = await self._http.post(f"{self._base_url}/{path}", data=body)
        if resp.status_code in (401, 403):
            token = await self._get_token(force_refresh=True)
            body["token"] = token
            resp = await self._http.post(f"{self._base_url}/{path}", data=body)
        resp.raise_for_status()
        return resp.json()

    # ---- Rail data endpoints ----

    async def station_list(self) -> Any:
        """All station codes and names."""
        return await self._post("getStationList", {})

    async def station_schedule(self, station: str, njt_only: bool = True) -> Any:
        """Full schedule for a station (next ~3 hours)."""
        return await self._post(
            "getStationSchedule",
            {"station": station.upper(), "NJT_Only": "Y" if njt_only else "N"},
        )

    async def upcoming_departures(self, station: str) -> Any:
        """Next ~19 trains departing a station (the 'big board' view)."""
        return await self._post("getTrainSchedule19Rec", {"station": station.upper()})

    async def train_stops(self, train_id: str) -> Any:
        """Stop list and ETAs for one train."""
        return await self._post("getTrainStopList", {"train": str(train_id)})

    async def vehicle_data(self) -> Any:
        """Live position/status for all active trains."""
        return await self._post("getVehicleData", {})
