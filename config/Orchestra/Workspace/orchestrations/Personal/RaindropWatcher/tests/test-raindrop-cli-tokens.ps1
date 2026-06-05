#!/usr/bin/env pwsh
# Token-storage tests for raindrop.cs:
#   1. DPAPI round-trip on Windows (Save -> Load) -- proves the on-disk file
#      is encrypted and unreadable as JSON.
#   2. Legacy plaintext migration -- proves a pre-existing
#      $XDG_CONFIG_HOME/orchestra/raindrop-tokens.json is read, re-saved at
#      the new RAINDROP_STATE_DIR path (encrypted on Windows), and the old
#      plaintext file is deleted.

$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot/.."
$cli = Join-Path $root 'tools/raindrop.cs'

if (-not (Test-Path -LiteralPath $cli)) {
    throw "raindrop.cs not found at $cli"
}

$tmpRoot = Join-Path $env:TEMP "raindrop-cli-tokens-$(Get-Random)"
$newStateDir = Join-Path $tmpRoot 'state'
$legacyXdg   = Join-Path $tmpRoot 'xdg'
$legacyDir   = Join-Path $legacyXdg 'orchestra'
$legacyFile  = Join-Path $legacyDir 'raindrop-tokens.json'
New-Item -ItemType Directory -Path $newStateDir -Force | Out-Null
New-Item -ItemType Directory -Path $legacyDir   -Force | Out-Null

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

# Saved env so we can restore at end.
$saved = @{
    RAINDROP_STATE_DIR        = $env:RAINDROP_STATE_DIR
    RAINDROP_TOKEN            = $env:RAINDROP_TOKEN
    RAINDROP_OAUTH_CLIENT_ID  = $env:RAINDROP_OAUTH_CLIENT_ID
    XDG_CONFIG_HOME           = $env:XDG_CONFIG_HOME
}

try {
    # No auth -- we don't hit the network here; we only exercise TokenStore via tokens-show.
    $env:RAINDROP_TOKEN = $null
    $env:RAINDROP_OAUTH_CLIENT_ID = $null
    $env:RAINDROP_STATE_DIR = $newStateDir
    $env:XDG_CONFIG_HOME    = $legacyXdg

    $newTokensFile = Join-Path $newStateDir 'raindrop-tokens.bin'

    # ---- Setup: a plausible legacy plaintext token file. ----
    $legacyJson = @{
        access_token  = 'legacy-access-token-XYZ'
        refresh_token = 'legacy-refresh-token-XYZ'
        token_type    = 'Bearer'
        expires_at    = (Get-Date).AddHours(1).ToUniversalTime().ToString('o')
    } | ConvertTo-Json
    Set-Content -LiteralPath $legacyFile -Value $legacyJson -NoNewline -Encoding UTF8

    Check 'legacy plaintext file exists before first run' {
        if (-not (Test-Path -LiteralPath $legacyFile)) { throw "fixture missing" }
        if (Test-Path -LiteralPath $newTokensFile) { throw "new file should not exist yet" }
    }

    # ---- Trigger migration via tokens-show. ----
    $allOutput = & dotnet run $cli -- tokens-show 2>&1
    $stdoutLines = $allOutput | Where-Object { $_ -notmatch '^\[' -and $_ -notmatch '^raindrop:' }
    $stderrLines = $allOutput | Where-Object { $_ -match 'migrated tokens|raindrop:' -or $_ -match '^\[' }

    Check 'tokens-show after legacy file exists succeeds' {
        if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
    }

    Check 'tokens-show reports tokens exist at new path' {
        $parsed = ($stdoutLines -join "`n") | ConvertFrom-Json
        if (-not $parsed.exists) { throw "exists=$($parsed.exists)" }
        if ($parsed.path -notmatch [regex]::Escape('raindrop-tokens.bin')) {
            throw "unexpected path: $($parsed.path)"
        }
        if ($parsed.hasAccessToken -ne $true) { throw "hasAccessToken=$($parsed.hasAccessToken)" }
        if ($parsed.hasRefreshToken -ne $true) { throw "hasRefreshToken=$($parsed.hasRefreshToken)" }
    }

    Check 'tokens-show reports encrypted=true on Windows' {
        $parsed = ($stdoutLines -join "`n") | ConvertFrom-Json
        if ($IsWindows -or ($null -eq $IsWindows -and $env:OS -eq 'Windows_NT')) {
            if ($parsed.encrypted -ne $true) { throw "expected encrypted=true on Windows" }
        } else {
            if ($parsed.encrypted -ne $false) { throw "expected encrypted=false on non-Windows" }
        }
    }

    Check 'migration emits the "migrated tokens" stderr notice' {
        $joined = ($stderrLines -join "`n")
        if ($joined -notmatch 'migrated tokens from legacy') {
            throw "expected migration notice, got: $joined"
        }
    }

    Check 'legacy plaintext file deleted after migration' {
        if (Test-Path -LiteralPath $legacyFile) { throw "legacy file still present" }
    }

    Check 'new token file exists on disk' {
        if (-not (Test-Path -LiteralPath $newTokensFile)) { throw "new file missing" }
    }

    Check 'new token file on Windows is NOT plaintext JSON' {
        if ($IsWindows -or ($null -eq $IsWindows -and $env:OS -eq 'Windows_NT')) {
            $raw = [System.IO.File]::ReadAllBytes($newTokensFile)
            # DPAPI blob has a recognizable header; plaintext would start with `{`.
            if ($raw[0] -eq [byte][char]'{') {
                throw "file content starts with `{`, looks like plaintext (should be encrypted)"
            }
            # Try to parse as JSON; this MUST fail.
            $text = [System.Text.Encoding]::UTF8.GetString($raw)
            try {
                $null = $text | ConvertFrom-Json -ErrorAction Stop
                throw "file parsed as JSON; encryption did not happen"
            } catch [System.Management.Automation.RuntimeException] {
                # expected -- not JSON
            } catch {
                # Any other failure (e.g. PSObject conversion) also means "not JSON".
            }
        } else {
            # On non-Windows, file is plaintext JSON by design.
            $text = Get-Content -LiteralPath $newTokensFile -Raw
            $null = $text | ConvertFrom-Json -ErrorAction Stop
        }
    }

    # ---- Second invocation: reads back from the encrypted .bin without migration. ----
    $allOutput2 = & dotnet run $cli -- tokens-show 2>&1
    $stdoutLines2 = $allOutput2 | Where-Object { $_ -notmatch '^\[' -and $_ -notmatch '^raindrop:' }
    $stderrLines2 = $allOutput2 | Where-Object { $_ -match 'migrated tokens|raindrop:' -or $_ -match '^\[' }

    Check 'second tokens-show reads encrypted file successfully' {
        if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
        $parsed = ($stdoutLines2 -join "`n") | ConvertFrom-Json
        if (-not $parsed.exists) { throw "exists=$($parsed.exists)" }
        if ($parsed.hasAccessToken -ne $true) { throw "lost hasAccessToken on read-back" }
    }

    Check 'second tokens-show does NOT emit migration notice' {
        $joined = ($stderrLines2 -join "`n")
        if ($joined -match 'migrated tokens from legacy') {
            throw "migration should be a one-time event"
        }
    }

    Write-Host ""
    if ($failures -gt 0) {
        Write-Host "FAILED: $failures of $tests token-storage tests" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "ALL $tests TOKEN-STORAGE TESTS PASSED" -ForegroundColor Green
    }
}
finally {
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction Ignore
    foreach ($k in $saved.Keys) {
        Set-Item -LiteralPath "env:$k" -Value $saved[$k] -ErrorAction Ignore
    }
}
