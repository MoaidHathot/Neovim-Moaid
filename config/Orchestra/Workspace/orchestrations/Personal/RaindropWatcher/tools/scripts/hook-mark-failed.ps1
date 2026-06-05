#!/usr/bin/env pwsh
# Hook script invoked on orchestration.failure by raindrop-processor.
# It does two things:
#   1. Flips the Zakira.Exchange state record for the raindrop to status="failed".
#   2. Drops a raindrop-error ActionView entry into the inbox so the user sees it.
#
# Stdin: a JSON payload produced by the Orchestra hook system (detail=standard,
#        steps=failed, includeRefs=true).
# Args:  $args[0] = raindropId, $args[1] = url, $args[2] = title
#
# This script intentionally does not throw -- hook failures otherwise log
# noisily and we don't want hook errors to obscure the real orchestration
# failure. We log everything to stderr.

$ErrorActionPreference = 'Continue'
$raindropId = $args[0]
$url        = $args[1]
$title      = $args[2]

# Read the hook payload from stdin (may be empty).
$payloadText = ''
try {
    $payloadText = [Console]::In.ReadToEnd()
} catch {
    Write-Error "hook-mark-failed: could not read stdin: $_"
}

$payload = $null
if ($payloadText) {
    try { $payload = $payloadText | ConvertFrom-Json } catch {
        Write-Error "hook-mark-failed: stdin was not JSON: $_"
    }
}

$failedStep = 'unknown'
$errorMessage = 'unknown failure'
if ($payload) {
    if ($payload.steps -and $payload.steps.Count -gt 0) {
        $failedStep = $payload.steps[0].name
        if ($payload.steps[0].errorMessage) { $errorMessage = $payload.steps[0].errorMessage }
    }
    if ($payload.errorMessage) { $errorMessage = $payload.errorMessage }
}

$nowIso = (Get-Date).ToUniversalTime().ToString('o')

# --- 1) Update Zakira.Exchange state -----------------------------------------
# We can't invoke the MCP from a script directly, so we use the Zakira.Exchange
# CLI (the same package) with subcommands. Zakira.Exchange supports `edit`/`get`
# subcommands when invoked as a CLI (not as MCP server). If that path doesn't
# exist on this machine, log and skip -- the next tracker tick will see the
# inconsistent state via attempts/timeouts.
$zakiraDb = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME 'orchestra/zakira.db' } else { $null }
$updatedData = @{
    raindropId = $raindropId
    url        = $url
    title      = $title
    status     = 'failed'
    failedAt   = $nowIso
    failedStep = $failedStep
    lastError  = $errorMessage
} | ConvertTo-Json -Compress
try {
    if ($zakiraDb) {
        # Use Zakira.Exchange `edit` subcommand. The exact CLI surface here is
        # best-effort -- if the call fails the next tracker tick will retry.
        & dnx Zakira.Exchange --yes -- --db $zakiraDb edit `
            --category raindrop-watcher-state `
            --key $raindropId `
            --data $updatedData `
            --reason "marked failed by raindrop-processor failure hook" `
            --tags failed 2>&1 | Write-Information
        if ($LASTEXITCODE -ne 0) {
            Write-Error "hook-mark-failed: zakira edit exit code $LASTEXITCODE (state may be inconsistent; next tick will surface it)"
        }
    } else {
        Write-Error "hook-mark-failed: XDG_CONFIG_HOME not set; skipping zakira state update"
    }
} catch {
    Write-Error "hook-mark-failed: zakira state update threw: $_"
}

# --- 2) Publish a raindrop-error ActionView entry ----------------------------
$entry = @{
    schemaVersion = '1'
    type          = 'raindrop-error'
    source        = 'raindrop-processor'
    title         = "Raindrop processing failed: $title"
    subtitle      = "step `"$failedStep`" failed -- $url"
    severity      = 'high'
    icon          = 'alert-triangle'
    tags          = @('raindrop','error', $failedStep)
    content = @(
        @{ type = 'keyValue'; label = 'Failure'; pairs = @{
            'Raindrop ID'  = $raindropId
            'URL'          = $url
            'Failed step'  = $failedStep
            'Failed at'    = $nowIso
        }}
        @{ type = 'alert'; level = 'error'; title = 'Error'; message = $errorMessage }
        @{ type = 'link'; label = 'Open original'; url = $url }
    )
    actions = @(
        @{ label = 'Open in raindrop.io'; style = 'default'; command = @{
            type = 'cli'; program = 'cmd'; args = @('/c','start','','https://app.raindrop.io/my/0/item/' + $raindropId + '/edit')
        }; onSuccess = 'keep' }
    )
}
$tmpFile = Join-Path $env:TEMP "raindrop-error-$raindropId-$([guid]::NewGuid().ToString('N')).json"
try {
    $entry | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmpFile -Encoding UTF8
    & dnx ActionView.Cli --yes -- add --file $tmpFile 2>&1 | Write-Information
    if ($LASTEXITCODE -ne 0) {
        Write-Error "hook-mark-failed: actionview add exit code $LASTEXITCODE"
    }
} catch {
    Write-Error "hook-mark-failed: ActionView publish threw: $_"
} finally {
    Remove-Item -LiteralPath $tmpFile -Force -ErrorAction Ignore
}

Write-Output "{`"ok`":true,`"raindropId`":`"$raindropId`",`"failedStep`":`"$failedStep`"}"
