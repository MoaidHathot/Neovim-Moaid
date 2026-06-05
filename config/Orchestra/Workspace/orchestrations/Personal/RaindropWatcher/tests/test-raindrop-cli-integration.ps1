#!/usr/bin/env pwsh
# Integration test for raindrop.cs against a local mock raindrop.io API.
# Spins up an in-process HttpListener that mimics the subset of the
# raindrop.io REST API the CLI talks to, then exercises every command.

$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot/.."
$cli = Join-Path $root 'tools/raindrop.cs'

if (-not (Test-Path -LiteralPath $cli)) {
    throw "raindrop.cs not found at $cli"
}

# Pick an unused port in the dynamic range.
$listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), 0
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()

$mockUrl = "http://localhost:$port/"
$apiBase = "http://localhost:$port/rest/v1"

$tmpState = Join-Path $env:TEMP "raindrop-cli-int-$(Get-Random)"
New-Item -ItemType Directory -Path $tmpState -Force | Out-Null

# Start the mock server as a background job. The job hosts a HttpListener
# that responds with canned JSON for the routes the CLI calls.
$mockScript = {
    param($Prefix)

    $http = New-Object System.Net.HttpListener
    $http.Prefixes.Add($Prefix)
    $http.Start()

    $collections = [System.Collections.Generic.Dictionary[long, object]]::new()
    $collections[100] = @{ _id = 100; title = 'Inbox'; parent = $null }
    $collections[200] = @{ _id = 200; title = 'Processed'; parent = $null }

    $raindrops = [System.Collections.Generic.Dictionary[long, object]]::new()
    $raindrops[1] = @{
        _id = 1; collectionId = 100; title = 'Test Article'
        link = 'https://example.com/a'; tags = @('article')
        note = 'please summarize'; created = '2026-01-01T00:00:00Z'
    }
    $raindrops[2] = @{
        _id = 2; collectionId = 100; title = 'Recipe Video'
        link = 'https://youtube.com/watch?v=abc'; tags = @('recipe','video')
        note = ''; created = '2026-01-02T00:00:00Z'
    }

    function Write-Json {
        param($Response, $Object, [int]$Status = 200)
        $json = $Object | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $Response.StatusCode = $Status
        $Response.ContentType = 'application/json'
        $Response.ContentLength64 = $bytes.Length
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $Response.OutputStream.Close()
    }

    try {
        while ($http.IsListening) {
            $ctx = $http.GetContext()
            $req = $ctx.Request
            $res = $ctx.Response
            $path = $req.Url.AbsolutePath
            $method = $req.HttpMethod
            $auth = $req.Headers['Authorization']

            try {
                if (-not $auth -or -not $auth.StartsWith('Bearer ')) {
                    Write-Json $res @{ error = 'unauthorized' } 401
                    continue
                }
                $token = $auth.Substring(7)
                if ($token -eq 'BAD-TOKEN') {
                    Write-Json $res @{ error = 'expired' } 401
                    continue
                }
                if ($path -eq '/rest/v1/user' -and $method -eq 'GET') {
                    Write-Json $res @{ user = @{ _id = 42; fullName = 'Test User' } }
                    continue
                }
                if ($path -eq '/rest/v1/collections' -and $method -eq 'GET') {
                    Write-Json $res @{ items = @($collections.Values | Where-Object { -not $_.parent }) }
                    continue
                }
                if ($path -eq '/rest/v1/collections/childrens' -and $method -eq 'GET') {
                    Write-Json $res @{ items = @($collections.Values | Where-Object { $_.parent }) }
                    continue
                }
                if ($path -eq '/rest/v1/collection' -and $method -eq 'POST') {
                    $body = [System.IO.StreamReader]::new($req.InputStream).ReadToEnd() | ConvertFrom-Json
                    $newId = ($collections.Keys | Measure-Object -Maximum).Maximum + 1
                    $collections[$newId] = @{ _id = $newId; title = $body.title; parent = $null }
                    Write-Json $res @{ item = $collections[$newId] }
                    continue
                }
                if ($path -match '^/rest/v1/raindrops/(\-?\d+)$' -and $method -eq 'GET') {
                    $colId = [long]$Matches[1]
                    $items = @($raindrops.Values | Where-Object { $_.collectionId -eq $colId })
                    Write-Json $res @{ items = $items; count = $items.Count }
                    continue
                }
                if ($path -match '^/rest/v1/raindrop/(\d+)$' -and $method -eq 'GET') {
                    $id = [long]$Matches[1]
                    if ($raindrops.ContainsKey($id)) {
                        Write-Json $res @{ item = $raindrops[$id] }
                    } else {
                        Write-Json $res @{ error = 'not found' } 404
                    }
                    continue
                }
                if ($path -match '^/rest/v1/raindrop/(\d+)$' -and $method -eq 'PUT') {
                    $id = [long]$Matches[1]
                    if (-not $raindrops.ContainsKey($id)) {
                        Write-Json $res @{ error = 'not found' } 404
                        continue
                    }
                    $body = [System.IO.StreamReader]::new($req.InputStream).ReadToEnd() | ConvertFrom-Json
                    $r = $raindrops[$id]
                    if ($body.collection) { $r.collectionId = $body.collection.'$id' }
                    if ($body.tags) { $r.tags = @($body.tags) }
                    Write-Json $res @{ item = $r }
                    continue
                }
                Write-Json $res @{ error = "no route for $method $path" } 404
            } catch {
                Write-Json $res @{ error = $_.Exception.Message } 500
            }
        }
    } finally {
        $http.Stop()
    }
}

$job = Start-Job -ScriptBlock $mockScript -ArgumentList $mockUrl

# Wait for the mock to come up.
$ready = $false
for ($i = 0; $i -lt 50 -and -not $ready; $i++) {
    try {
        $probe = Invoke-WebRequest -Uri ($apiBase + '/user') -Headers @{ Authorization = 'Bearer probe' } -ErrorAction Stop -SkipHttpErrorCheck
        $ready = $true
    } catch {
        Start-Sleep -Milliseconds 100
    }
}
if (-not $ready) { throw "mock server failed to start at $mockUrl" }

try {
    $env:RAINDROP_STATE_DIR = $tmpState
    $env:RAINDROP_API_BASE = $apiBase
    $env:RAINDROP_TOKEN = 'TEST-TOKEN-OK'
    $env:RAINDROP_OAUTH_CLIENT_ID = $null
    $env:RAINDROP_OAUTH_CLIENT_SECRET = $null

    $failures = 0
    $tests = 0
    function Check {
        param($Label, [scriptblock]$Block)
        $script:tests++
        try {
            & $Block
            Write-Host "  pass: $Label" -ForegroundColor Green
        } catch {
            $script:failures++
            Write-Host "  FAIL: $Label -- $_" -ForegroundColor Red
        }
    }

    Check 'whoami returns user object' {
        $out = & dotnet run $cli -- whoami 2>&1 | Where-Object { $_ -notmatch '^\[' }
        $joined = ($out -join "`n")
        $joined | Out-Null
        $parsed = $joined | ConvertFrom-Json
        if ($parsed.user._id -ne 42) { throw "expected user id 42, got $($parsed.user._id)" }
    }

    Check 'list returns 2 items in inbox collection 100' {
        $out = & dotnet run $cli -- list --collection 100 2>&1 | Where-Object { $_ -notmatch '^\[' }
        $parsed = ($out -join "`n") | ConvertFrom-Json
        if ($parsed.count -ne 2) { throw "expected 2 items, got $($parsed.count)" }
        if ($parsed.items[0]._id -ne 1 -and $parsed.items[1]._id -ne 1) { throw "missing raindrop 1" }
    }

    Check 'get single raindrop' {
        $out = & dotnet run $cli -- get 2 2>&1 | Where-Object { $_ -notmatch '^\[' }
        $parsed = ($out -join "`n") | ConvertFrom-Json
        if ($parsed.item._id -ne 2) { throw "expected id 2, got $($parsed.item._id)" }
        if ($parsed.item.title -ne 'Recipe Video') { throw "wrong title" }
    }

    Check 'list-collections returns root + children' {
        $out = & dotnet run $cli -- list-collections 2>&1 | Where-Object { $_ -notmatch '^\[' }
        $parsed = ($out -join "`n") | ConvertFrom-Json
        if (-not $parsed.root) { throw "missing root array" }
        if ($parsed.root.Count -lt 2) { throw "expected at least 2 root collections" }
    }

    Check 'ensure-collection finds existing Inbox' {
        $out = & dotnet run $cli -- ensure-collection Inbox 2>&1 | Where-Object { $_ -notmatch '^\[' }
        $parsed = ($out -join "`n") | ConvertFrom-Json
        if ($parsed.created -ne $false) { throw "expected created=false, got $($parsed.created)" }
        if ($parsed.id -ne 100) { throw "expected id 100, got $($parsed.id)" }
    }

    Check 'ensure-collection creates new collection' {
        $out = & dotnet run $cli -- ensure-collection 'Recipes' 2>&1 | Where-Object { $_ -notmatch '^\[' }
        $parsed = ($out -join "`n") | ConvertFrom-Json
        if ($parsed.created -ne $true) { throw "expected created=true, got $($parsed.created)" }
        if ($parsed.id -lt 200) { throw "expected new id, got $($parsed.id)" }
    }

    Check 'move raindrop to processed' {
        $out = & dotnet run $cli -- move 1 --to-collection 200 --add-tag processed 2>&1 | Where-Object { $_ -notmatch '^\[' }
        $parsed = ($out -join "`n") | ConvertFrom-Json
        if ($parsed.item.collectionId -ne 200) { throw "expected collectionId 200, got $($parsed.item.collectionId)" }
        if ($parsed.item.tags -notcontains 'processed') { throw "missing processed tag" }
        if ($parsed.item.tags -notcontains 'article') { throw "existing tag dropped" }
    }

    Check 'add-tag adds tag' {
        $out = & dotnet run $cli -- add-tag 2 'queued' 2>&1 | Where-Object { $_ -notmatch '^\[' }
        $parsed = ($out -join "`n") | ConvertFrom-Json
        if ($parsed.item.tags -notcontains 'queued') { throw "tag not added" }
    }

    Check 'remove-tag removes tag' {
        $out = & dotnet run $cli -- remove-tag 2 'recipe' 2>&1 | Where-Object { $_ -notmatch '^\[' }
        $parsed = ($out -join "`n") | ConvertFrom-Json
        if ($parsed.item.tags -contains 'recipe') { throw "tag not removed" }
    }

    Check 'bad token exits 4 with HTTP 401' {
        $env:RAINDROP_TOKEN = 'BAD-TOKEN'
        $out = & dotnet run $cli -- whoami 2>&1
        if ($LASTEXITCODE -ne 4) { throw "expected exit 4, got $LASTEXITCODE" }
        if (($out -join "`n") -notmatch '401') { throw "expected 401 in error" }
        $env:RAINDROP_TOKEN = 'TEST-TOKEN-OK'
    }

    Write-Host ""
    if ($failures -gt 0) {
        Write-Host "FAILED: $failures of $tests integration tests" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "ALL $tests INTEGRATION TESTS PASSED" -ForegroundColor Green
    }
}
finally {
    Stop-Job -Job $job -ErrorAction Ignore
    Remove-Job -Job $job -Force -ErrorAction Ignore
    Remove-Item -LiteralPath $tmpState -Recurse -Force -ErrorAction Ignore
    $env:RAINDROP_API_BASE = $null
    $env:RAINDROP_TOKEN = $null
    $env:RAINDROP_STATE_DIR = $null
}
