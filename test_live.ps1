# Integration test against the live Cloud Run MCP endpoint.
# Usage: .\test_live.ps1 [-Url https://your-service.run.app]

param(
    [string]$Url = "https://njtransit-mcp-489498673607.us-east4.run.app"
)

$ErrorActionPreference = "Stop"
$endpoint = "$Url/mcp"
$passed = 0
$failed = 0

function Write-Pass($msg) { Write-Host "  PASS  $msg" -ForegroundColor Green;  $script:passed++ }
function Write-Fail($msg) { Write-Host "  FAIL  $msg" -ForegroundColor Red;    $script:failed++ }

function Invoke-Mcp {
    param([string]$SessionId, [string]$Body)
    $headers = @{
        "Content-Type" = "application/json"
        "Accept"       = "application/json, text/event-stream"
    }
    if ($SessionId) { $headers["mcp-session-id"] = $SessionId }

    $resp = Invoke-WebRequest -Uri $endpoint -Method POST -Headers $headers -Body $Body -UseBasicParsing
    # Parse SSE envelope: extract JSON from "data: {...}" line
    $data = ($resp.Content -split "`n" | Where-Object { $_ -match "^data:" } | Select-Object -First 1) -replace "^data:\s*", ""
    return @{ Headers = $resp.Headers; Json = ($data | ConvertFrom-Json) }
}

Write-Host "`nTesting $endpoint`n"

# ── 1. Initialize ─────────────────────────────────────────────────────────────
Write-Host "1. Initialize"
$initBody = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"ps-test","version":"1.0"}}}'
$init = Invoke-Mcp -Body $initBody
$sid  = $init.Headers["mcp-session-id"]

if ($init.Json.result.serverInfo.name -eq "njtransit") {
    Write-Pass "server name = njtransit"
} else {
    Write-Fail "unexpected serverInfo: $($init.Json.result.serverInfo)"
}
if ($sid) {
    Write-Pass "got session id: $sid"
} else {
    Write-Fail "no mcp-session-id header returned"
    exit 1
}

# ── 2. List tools ─────────────────────────────────────────────────────────────
Write-Host "`n2. tools/list"
$toolsResp = Invoke-Mcp -SessionId $sid -Body '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
$toolNames = $toolsResp.Json.result.tools | ForEach-Object { $_.name }
$expected  = @("list_stations","upcoming_departures","station_schedule","train_stops","active_trains")
foreach ($t in $expected) {
    if ($toolNames -contains $t) { Write-Pass "tool registered: $t" }
    else                          { Write-Fail "tool missing:    $t" }
}

# ── 3. list_stations → real NJT data ─────────────────────────────────────────
Write-Host "`n3. list_stations (real API call)"
$stBody   = '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_stations","arguments":{}}}'
$stResp   = Invoke-Mcp -SessionId $sid -Body $stBody

if ($stResp.Json.result.isError) {
    Write-Fail "list_stations returned isError: $($stResp.Json.result.content[0].text)"
} else {
    $stText   = $stResp.Json.result.content[0].text
    $stations = $stText | ConvertFrom-Json

    if ($stations.Count -gt 10) {
        Write-Pass "received $($stations.Count) stations"
    } else {
        Write-Fail "too few stations: $($stations.Count)"
    }

    # Verify a few well-known stations are present
    foreach ($code in @("NY", "NWK", "HOB", "TRE")) {
        $found = $stations | Where-Object { $_.STATION_2CHAR -eq $code -or $_.StationName -match $code }
        if ($found) { Write-Pass "known station present: $code" }
        else         { Write-Fail "known station missing:  $code" }
    }
}

# ── 4. upcoming_departures(NY) → real train board ─────────────────────────────
Write-Host "`n4. upcoming_departures(NY) (real API call)"
$depBody = '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"upcoming_departures","arguments":{"station":"NY"}}}'
$depResp = Invoke-Mcp -SessionId $sid -Body $depBody

if ($depResp.Json.result.isError) {
    Write-Fail "upcoming_departures returned isError: $($depResp.Json.result.content[0].text)"
} else {
    $depText  = $depResp.Json.result.content[0].text
    $trains   = $depText | ConvertFrom-Json

    if ($trains.Count -gt 0) {
        Write-Pass "received $($trains.Count) departures from NY"
        $train = $trains[0]
        Write-Pass "first departure: train $($train.TRAIN_ID) to $($train.DESTINATION) at $($train.SCHED_DEP_DATE)"
    } else {
        Write-Fail "no departures returned (is it a service blackout?)"
    }

    # ── 5. train_stops → follow one train ──────────────────────────────────────
    if ($trains.Count -gt 0 -and $trains[0].TRAIN_ID) {
        $trainId  = $trains[0].TRAIN_ID
        Write-Host "`n5. train_stops($trainId)"
        $tsBody   = "{`"jsonrpc`":`"2.0`",`"id`":5,`"method`":`"tools/call`",`"params`":{`"name`":`"train_stops`",`"arguments`":{`"train_id`":`"$trainId`"}}}"
        $tsResp   = Invoke-Mcp -SessionId $sid -Body $tsBody

        if ($tsResp.Json.result.isError) {
            Write-Fail "train_stops returned isError: $($tsResp.Json.result.content[0].text)"
        } else {
            $tsText = $tsResp.Json.result.content[0].text
            $stops  = $tsText | ConvertFrom-Json
            if ($stops.Count -gt 0) {
                Write-Pass "train $trainId has $($stops.Count) stops"
            } else {
                Write-Fail "no stops returned for train $trainId"
            }
        }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "`n$('─' * 50)"
Write-Host "  $passed passed  |  $failed failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "$('─' * 50)`n"
if ($failed -gt 0) { exit 1 }
