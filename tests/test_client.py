"""Mocked tests for NJTClient — verify request shape, token caching, refresh on 401."""

from __future__ import annotations

import httpx
import pytest
import respx

from njtransit_mcp.njt_client import NJTClient

BASE = "https://raildata.njtransit.com/api/TrainData"


@pytest.fixture
def client():
    return NJTClient(username="u", password="p", base_url=BASE)


@pytest.mark.asyncio
@respx.mock
async def test_token_fetched_once_and_reused(client):
    token_route = respx.post(f"{BASE}/getToken").mock(
        return_value=httpx.Response(200, json={"UserToken": "TKN"})
    )
    stations_route = respx.post(f"{BASE}/getStationList").mock(
        return_value=httpx.Response(200, json=[{"STATION_2CHAR": "NY", "STATIONNAME": "New York"}])
    )

    await client.station_list()
    await client.station_list()

    assert token_route.call_count == 1
    assert stations_route.call_count == 2
    # token must be passed in the form body
    body = stations_route.calls[0].request.content.decode()
    assert "token=TKN" in body
    await client.aclose()


@pytest.mark.asyncio
@respx.mock
async def test_refresh_on_401(client):
    tokens = iter(["OLD", "NEW"])
    respx.post(f"{BASE}/getToken").mock(
        side_effect=lambda req: httpx.Response(200, json={"UserToken": next(tokens)})
    )
    calls = {"n": 0}

    def schedule_handler(request):
        calls["n"] += 1
        if calls["n"] == 1:
            return httpx.Response(401, json={"error": "expired"})
        return httpx.Response(200, json=[{"TRAIN_ID": "3925"}])

    respx.post(f"{BASE}/getTrainSchedule19Rec").mock(side_effect=schedule_handler)

    result = await client.upcoming_departures("NY")
    assert result == [{"TRAIN_ID": "3925"}]
    assert calls["n"] == 2  # one 401, one retry
    await client.aclose()


@pytest.mark.asyncio
@respx.mock
async def test_station_normalized_to_upper(client):
    respx.post(f"{BASE}/getToken").mock(return_value=httpx.Response(200, json={"UserToken": "TKN"}))
    route = respx.post(f"{BASE}/getTrainSchedule19Rec").mock(
        return_value=httpx.Response(200, json=[])
    )

    await client.upcoming_departures("ny")
    body = route.calls[0].request.content.decode()
    assert "station=NY" in body
    await client.aclose()
