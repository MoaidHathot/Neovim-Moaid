#!/usr/bin/env pwsh
# Smoke test for raindrop.cs against a local mock raindrop.io server.
# Runs as a single-process script: spins up a mock HttpListener in a background
# job, exercises every CLI command via RAINDROP_API_BASE override (we patch
# the source at test time using $env:RAINDROP_API_BASE_URL since the helper
# allows that override -- if not, we monkey-patch via /etc/hosts equivalents).
#
# Strategy here: since the CLI hard-codes https://api.raindrop.io as base URL,
# we test against a *local* hosts override using `--api-base` -- we'll add that
# CLI flag if it doesn't exist. For now this script focuses on the parts that
# don't require the live API: --help, tokens-show, error paths.

$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot/.."
$cli = Join-Path $root 'tools/raindrop.cs'

if (-not (Test-Path -LiteralPath $cli)) {
    throw "raindrop.cs not found at $cli"
}

$tmp = Join-Path $env:TEMP "raindrop-cli-smoke-$(Get-Random)"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $env:RAINDROP_STATE_DIR = $tmp
    $env:RAINDROP_TOKEN = $null
    $env:RAINDROP_OAUTH_CLIENT_ID = $null
    $env:RAINDROP_OAUTH_CLIENT_SECRET = $null

    $failures = 0
    $tests = 0

    function Assert-Equal {
        param($actual, $expected, $label)
        $script:tests++
        if ($actual -ne $expected) {
            Write-Host "  FAIL: $label -- expected '$expected', got '$actual'" -ForegroundColor Red
            $script:failures++
        } else {
            Write-Host "  pass: $label" -ForegroundColor Green
        }
    }

    function Assert-Contains {
        param($actual, $needle, $label)
        $script:tests++
        if ($actual -notmatch [regex]::Escape($needle)) {
            Write-Host "  FAIL: $label -- '$needle' not found in output" -ForegroundColor Red
            Write-Host "        output: $actual" -ForegroundColor Yellow
            $script:failures++
        } else {
            Write-Host "  pass: $label" -ForegroundColor Green
        }
    }

    Write-Host "== help"
    $out = & dotnet run $cli -- --help 2>&1
    Assert-Equal $LASTEXITCODE 0 'help exit 0'
    Assert-Contains ($out -join "`n") 'raindrop login' 'help mentions login'

    Write-Host "== tokens-show (no tokens)"
    $out = & dotnet run $cli -- tokens-show 2>&1
    Assert-Equal $LASTEXITCODE 0 'tokens-show exit 0'
    Assert-Contains ($out -join "`n") '"exists": false' 'tokens-show reports missing'

    Write-Host "== whoami with no auth"
    $out = & dotnet run $cli -- whoami 2>&1
    Assert-Equal $LASTEXITCODE 3 'whoami no-auth exits 3'
    Assert-Contains ($out -join "`n") 'no auth configured' 'whoami says no auth'

    Write-Host "== unknown command"
    $out = & dotnet run $cli -- bogus 2>&1
    Assert-Equal $LASTEXITCODE 2 'unknown command exits 2'

    Write-Host "== list missing --collection"
    $out = & dotnet run $cli -- list 2>&1
    Assert-Equal $LASTEXITCODE 3 'missing flag exits 3'
    Assert-Contains ($out -join "`n") 'missing required --collection' 'flag error mentions flag'

    Write-Host "== ensure-collection missing title"
    $out = & dotnet run $cli -- ensure-collection 2>&1
    Assert-Equal $LASTEXITCODE 3 'missing title exits 3'

    Write-Host "== move missing raindropId"
    $out = & dotnet run $cli -- move --to-collection 5 2>&1
    Assert-Equal $LASTEXITCODE 3 'missing positional exits 3'

    Write-Host "== auto-login disabled via RAINDROP_AUTO_LOGIN=0 with OAuth env vars but no tokens"
    $env:RAINDROP_OAUTH_CLIENT_ID = 'fake-id'
    $env:RAINDROP_OAUTH_CLIENT_SECRET = 'fake-secret'
    $env:RAINDROP_AUTO_LOGIN = '0'
    try {
        $out = & dotnet run $cli -- whoami 2>&1
        Assert-Equal $LASTEXITCODE 3 'auto-login disabled exits 3'
        Assert-Contains ($out -join "`n") 'RAINDROP_AUTO_LOGIN=0 disabled' 'error mentions opt-out var'
    } finally {
        $env:RAINDROP_OAUTH_CLIENT_ID = $null
        $env:RAINDROP_OAUTH_CLIENT_SECRET = $null
        $env:RAINDROP_AUTO_LOGIN = $null
    }

    Write-Host ""
    if ($failures -gt 0) {
        Write-Host "FAILED: $failures of $tests tests" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "ALL $tests TESTS PASSED" -ForegroundColor Green
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction Ignore
}
