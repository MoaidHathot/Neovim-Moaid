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
# IMPORTANT (resilience policy, per RaindropWatcher design note):
# This hook intentionally **throws** when its own internal steps fail (zakira
# edit or ActionView add), so that broken state-persistence doesn't go
# unnoticed. The orchestration.failure that triggered the hook is the
# *primary* signal; a hook failure on top of it surfaces as a secondary signal
# in Orchestra's hook log. The combination tells you both "the orchestration
# died at step X" AND "and we also could not record that fact in the watcher
# state machine, so the next tracker tick may need stuck-detection to recover."
# The stuck-in-flight rule in raindrop-tracker.yaml is the second line of
# defense for this exact case.

$ErrorActionPreference = 'Stop'
$raindropId = $args[0]
$url        = $args[1]
$title      = $args[2]

if ([string]::IsNullOrWhiteSpace($raindropId)) {
    throw "hook-mark-failed: raindropId argument missing"
}

# Read the hook payload from stdin (may be empty).
$payloadText = ''
try {
    $payloadText = [Console]::In.ReadToEnd()
} catch {
    # stdin not available is fine; we just don't get rich failure context.
    Write-Warning "hook-mark-failed: could not read stdin: $_"
}

$payload = $null
if ($payloadText) {
    try { $payload = $payloadText | ConvertFrom-Json } catch {
        Write-Warning "hook-mark-failed: stdin was not JSON: $_"
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
# We can't invoke the MCP from a script directly, so we shell out to the
# Zakira.Exchange CLI (the same package, different command shape).
$zakiraDb = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME 'orchestra/zakira.db' } else { $null }
if (-not $zakiraDb) {
    throw "hook-mark-failed: XDG_CONFIG_HOME is not set; cannot locate zakira.db. The state record for raindropId=$raindropId could not be updated. The next tracker tick's stuck-in-flight rule should recover this."
}

$updatedData = @{
    raindropId = $raindropId
    url        = $url
    title      = $title
    status     = 'failed'
    failedAt   = $nowIso
    failedStep = $failedStep
    lastError  = $errorMessage
} | ConvertTo-Json -Compress

& dnx Zakira.Exchange --yes -- --db $zakiraDb edit `
    --category raindrop-watcher-state `
    --key $raindropId `
    --data $updatedData `
    --reason "marked failed by raindrop-processor failure hook" `
    --tags failed 2>&1 | ForEach-Object { Write-Information $_ -InformationAction Continue }
if ($LASTEXITCODE -ne 0) {
    throw "hook-mark-failed: zakira edit exited $LASTEXITCODE for raindropId=$raindropId. The watcher state record is now inconsistent; the next tracker tick will need stuck-in-flight detection to recover."
}

# --- 2) Publish a raindrop-error ActionView entry ----------------------------
$reprocessScript = Join-Path $PSScriptRoot 'reprocess-raindrop.ps1'
$errorEntryId = "raindrop-error-$raindropId"  # stable per-raindrop -> latest failure replaces prior, no accumulation
$entry = @{
    schemaVersion = '1'
    id            = $errorEntryId
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
        @{ label = 'Reprocess (move back to AI-Inbox)'; style = 'default'; confirmMessage = 'Move this raindrop back to AI-Inbox and rerun the full analysis on the next tracker tick? The Zakira state record will be cleared.'; command = @{
            type = 'cli'; program = 'pwsh'; args = @('-NoProfile','-File',$reprocessScript,'-RaindropId',$raindropId)
        }; onSuccess = 'archive' }
    )
}
$tmpFile = Join-Path $env:TEMP "raindrop-error-$raindropId-$([guid]::NewGuid().ToString('N')).json"
try {
    $entry | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmpFile -Encoding UTF8
    # Delete-then-add for idempotent upsert (so retried failures don't accumulate entries).
    & dnx ActionView.Cli --yes -- delete $errorEntryId --force 2>$null | Out-Null
    & dnx ActionView.Cli --yes -- add --file $tmpFile 2>&1 | ForEach-Object { Write-Information $_ -InformationAction Continue }
    if ($LASTEXITCODE -ne 0) {
        throw "hook-mark-failed: actionview add exited $LASTEXITCODE for raindropId=$raindropId. The zakira state was updated to 'failed' but no ActionView entry was published; the user will see the failure only via the next rolling watcher-status entry."
    }
} finally {
    Remove-Item -LiteralPath $tmpFile -Force -ErrorAction Ignore
}

Write-Output "{`"ok`":true,`"raindropId`":`"$raindropId`",`"failedStep`":`"$failedStep`"}"
