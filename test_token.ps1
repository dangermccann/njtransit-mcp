# Quick credential tester for the NJT Rail Data getToken endpoint.
# Try different username/password values until you find what works.
# Usage: .\test_token.ps1 -Username "you@example.com" -Password "secret"

param(
    [string]$Username = "",
    [string]$Password = "",
    [ValidateSet("prod","test","both")]
    [string]$Env = "both"
)

$endpoints = @{
    prod = "https://raildata.njtransit.com/api/TrainData"
    test = "https://testraildata.njtransit.com/api/TrainData"
}

function Test-Token {
    param([string]$Label, [string]$BaseUrl, [string]$User, [string]$Pass)

    Write-Host "`n[$Label]  $BaseUrl/getToken"
    Write-Host "  username = $(if ($User -eq '') { '(empty)' } else { $User })"
    Write-Host "  password = $(if ($Pass -eq '') { '(empty)' } else { '****' })"

    try {
        $resp = Invoke-WebRequest `
            -Uri "$BaseUrl/getToken" `
            -Method POST `
            -ContentType "application/x-www-form-urlencoded" `
            -Body "username=$([uri]::EscapeDataString($User))&password=$([uri]::EscapeDataString($Pass))" `
            -UseBasicParsing `
            -ErrorAction Stop

        Write-Host "  HTTP $($resp.StatusCode)" -ForegroundColor Green
        $body = $resp.Content
        Write-Host "  Body: $(if ($body) { $body } else { '(empty)' })"

        # If we got a token, try one real data call to confirm it works
        try {
            $parsed = $body | ConvertFrom-Json
            $token = $parsed.UserToken ?? $parsed.Authenticated ?? $parsed.token
            if ($token -and $token -ne "0") {
                Write-Host "  Token: $token" -ForegroundColor Cyan
                $dataResp = Invoke-WebRequest `
                    -Uri "$BaseUrl/getStationList" `
                    -Method POST `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body "token=$([uri]::EscapeDataString($token))" `
                    -UseBasicParsing `
                    -ErrorAction Stop
                $stations = $dataResp.Content | ConvertFrom-Json
                Write-Host "  getStationList: $($stations.Count) stations returned" -ForegroundColor Green
            }
        } catch {}

    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        Write-Host "  HTTP $code" -ForegroundColor Red
        try {
            $errBody = $_.ErrorDetails.Message
            Write-Host "  Body: $errBody"
        } catch {}
    }
}

if ($Env -eq "prod" -or $Env -eq "both") {
    Test-Token -Label "PROD" -BaseUrl $endpoints.prod -User $Username -Pass $Password
}
if ($Env -eq "test" -or $Env -eq "both") {
    Test-Token -Label "TEST" -BaseUrl $endpoints.test -User $Username -Pass $Password
}

Write-Host ""
