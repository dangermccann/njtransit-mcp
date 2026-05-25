# NJ Transit MCP server

An [MCP](https://modelcontextprotocol.io) server that exposes NJ Transit
commuter-rail departure and train-status data as tools Claude can call.

## Tools

- `list_stations` — every NJT rail station + code
- `upcoming_departures(station)` — next ~19 trains from a station
- `station_schedule(station, include_non_njt=False)` — full upcoming schedule
- `train_stops(train_id)` — stop list + live ETAs for one train
- `active_trains` — live position/status for every running train

## Local dev

**macOS / Linux:**
```bash
# Python 3.11+
python -m venv .venv && source .venv/bin/activate
pip install -e .

cp .env.example .env   # then fill in NJTRANSIT_USERNAME / _PASSWORD
njtransit-mcp          # serves Streamable HTTP on :8080 at /mcp
```

**Windows (PowerShell):**
```powershell
# Python 3.11+
python -m venv .venv; .venv\Scripts\Activate.ps1
pip install -e .

Copy-Item .env.example .env   # then fill in NJTRANSIT_USERNAME / _PASSWORD
njtransit-mcp                 # serves Streamable HTTP on :8080 at /mcp
```

Hit it with the MCP Inspector:

```powershell
npx @modelcontextprotocol/inspector
# Connect to http://localhost:8080/mcp (Streamable HTTP)
```

## Deploy to Cloud Run

Credentials live in Secret Manager; the service reads them as env vars.

**macOS / Linux:**
```bash
export PROJECT_ID=your-gcp-project
export REGION=us-east4   # optional

# One-time: store creds
printf %s "$NJTRANSIT_USERNAME" | gcloud secrets create njtransit-username --data-file=-
printf %s "$NJTRANSIT_PASSWORD" | gcloud secrets create njtransit-password --data-file=-

./deploy.sh
```

**Windows (PowerShell):**
```powershell
$env:PROJECT_ID = "your-gcp-project"
$env:REGION     = "us-east4"   # optional

# One-time: store creds
$env:NJTRANSIT_USERNAME | gcloud secrets create njtransit-username --data-file=-
$env:NJTRANSIT_PASSWORD | gcloud secrets create njtransit-password --data-file=-

.\deploy.ps1
```

The deploy script prints the service URL. The MCP endpoint is `<url>/mcp`.

## Adding to Claude

In Claude.ai → Settings → Connectors → Add custom connector, paste the
Cloud Run URL with `/mcp` suffix.

## Notes

- Built against the NJ Transit Rail Data v3 API (`raildata.njtransit.com`).
- Auth is a session token from `getToken`; the client caches and refreshes
  on 401/403.
- Public schedule data only — no OAuth needed.
