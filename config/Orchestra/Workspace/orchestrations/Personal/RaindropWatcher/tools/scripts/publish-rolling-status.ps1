#!/usr/bin/env pwsh
# Publishes (replaces) the single rolling `raindrop-watcher-status` ActionView
# entry that summarizes the current health of the watcher.
#
# Pattern: list existing entries of type raindrop-watcher-status, delete each
# one, then add a fresh one. ActionView has no native upsert, so this is the
# canonical "one entry per type" pattern.
#
# This script is best-effort: failures are logged to stderr but the script
# always returns 0 so a flaky ActionView install can't break the tracker tick
# itself. The tick-summary text in tracker-summary covers the same info.
#
# Usage:
#   publish-rolling-status.ps1 -BootstrapJson '...' -ListInboxJson '...' `
#                              -SelectionJson '...' -DispatchJson '...' `
#                              -DeadLetterJson '...'

param(
    [Parameter(Mandatory=$true)] [string]$BootstrapJson,
    [Parameter(Mandatory=$true)] [string]$ListInboxJson,
    [Parameter(Mandatory=$true)] [string]$SelectionJson,
    [Parameter(Mandatory=$true)] [string]$DispatchJson,
    [Parameter(Mandatory=$true)] [string]$DeadLetterJson
)

$ErrorActionPreference = 'Continue'

function Try-ParseJson([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    try { return ($s | ConvertFrom-Json) } catch { return $null }
}

$bootstrap   = Try-ParseJson $BootstrapJson
$listInbox   = Try-ParseJson $ListInboxJson
$selection   = Try-ParseJson $SelectionJson
$dispatch    = Try-ParseJson $DispatchJson
$deadLetter  = Try-ParseJson $DeadLetterJson

$inboxCount       = if ($listInbox -and $listInbox.count) { [int]$listInbox.count } else { 0 }
$dispatchedItems  = if ($dispatch -and $dispatch.dispatched) { @($dispatch.dispatched) } else { @() }
$skippedItems     = if ($selection -and $selection.skipped) { @($selection.skipped) } else { @() }
$deferredItems    = if ($selection -and $selection.deferred) { @($selection.deferred) } else { @() }
$stuckItems       = if ($selection -and $selection.stuckReclassified) { @($selection.stuckReclassified) } else { @() }
$deadLetteredOk   = @()
$deadLetteredFail = @()
if ($deadLetter -and $deadLetter.deadLettered) {
    foreach ($d in @($deadLetter.deadLettered)) {
        if ($d.ok) { $deadLetteredOk += $d } else { $deadLetteredFail += $d }
    }
}

$nowIso = (Get-Date).ToUniversalTime().ToString('o')

$severity = 'low'
if ($deadLetteredOk.Count -gt 0 -or $deadLetteredFail.Count -gt 0 -or $stuckItems.Count -gt 0) {
    $severity = 'medium'
}

$inboxCollectionId      = if ($bootstrap) { "$($bootstrap.inboxCollectionId)" } else { '' }
$deadLetterCollectionId = if ($bootstrap) { "$($bootstrap.deadLetterCollectionId)" } else { '' }
$processedCollectionId  = if ($bootstrap) { "$($bootstrap.processedCollectionId)" } else { '' }

# --- Build content blocks ----------------------------------------------------
$contentBlocks = @()
$contentBlocks += @{
    type   = 'keyValue'
    label  = 'Counts'
    pairs  = [ordered]@{
        'Inbox'                    = "$inboxCount"
        'Dispatched this tick'     = "$($dispatchedItems.Count)"
        'Skipped'                  = "$($skippedItems.Count)"
        'Deferred to next tick'    = "$($deferredItems.Count)"
        'Dead-lettered this tick'  = "$($deadLetteredOk.Count)"
        'Stuck-reclassified'       = "$($stuckItems.Count)"
        'Last tick at (UTC)'       = $nowIso
    }
}

if ($dispatchedItems.Count -gt 0) {
    $md = "Dispatched this tick:`n`n"
    foreach ($d in $dispatchedItems) {
        $md += ('- `{0}` -> executionId `{1}`' -f $d.raindropId, $d.executionId) + "`n"
    }
    $contentBlocks += @{
        type = 'section'; title = 'Dispatched'
        content = @(@{ type = 'markdown'; body = $md })
    }
}

if ($deadLetteredOk.Count -gt 0 -or $deadLetteredFail.Count -gt 0) {
    $md = "Dead-lettered this tick:`n`n"
    foreach ($d in $deadLetteredOk) {
        $md += ('- OK `{0}` -- {1}' -f $d.raindropId, $d.url) + "`n"
    }
    foreach ($d in $deadLetteredFail) {
        $errs = ($d.errors -join '; ')
        $md += ('- FAILED `{0}` -- {1} (errors: {2})' -f $d.raindropId, $d.url, $errs) + "`n"
    }
    $contentBlocks += @{
        type = 'section'; title = 'Dead-lettered (this tick)'
        content = @(@{ type = 'markdown'; body = $md })
    }
}

if ($stuckItems.Count -gt 0) {
    $md = "Stuck items re-classified as failed this tick:`n`n"
    foreach ($s in $stuckItems) {
        $md += ('- `{0}` (priorStatus={1}, ageMinutes={2})' -f $s.raindropId, $s.priorStatus, $s.ageMinutes) + "`n"
    }
    $contentBlocks += @{
        type = 'section'; title = 'Stuck-reclassified'
        content = @(@{ type = 'markdown'; body = $md })
    }
}

$actions = @()
if ($inboxCollectionId) {
    $actions += @{ label = 'Open AI-Inbox'; style = 'default'; command = @{
        type = 'cli'; program = 'cmd'; args = @('/c','start','','https://app.raindrop.io/my/' + $inboxCollectionId)
    }; onSuccess = 'keep' }
}
if ($deadLetterCollectionId) {
    $actions += @{ label = 'Open AI-DeadLetter'; style = 'default'; command = @{
        type = 'cli'; program = 'cmd'; args = @('/c','start','','https://app.raindrop.io/my/' + $deadLetterCollectionId)
    }; onSuccess = 'keep' }
}

$entry = @{
    schemaVersion = '1'
    type          = 'raindrop-watcher-status'
    source        = 'raindrop-tracker'
    title         = "Raindrop watcher: $inboxCount pending, $($deadLetteredOk.Count) dead-lettered"
    subtitle      = "Last tick: dispatched $($dispatchedItems.Count), skipped $($skippedItems.Count), deferred $($deferredItems.Count)"
    severity      = $severity
    icon          = 'activity'
    tags          = @('raindrop','watcher','status')
    content       = $contentBlocks
    actions       = $actions
}

# --- Delete existing entries of this type ------------------------------------
# ActionView's `list` command emits a fixed-width text table (no JSON option
# as of this writing). We scrape the leftmost column for 32-hex-char IDs.
try {
    $listOut = & dnx ActionView.Cli --yes -- list --type raindrop-watcher-status 2>$null
    if ($LASTEXITCODE -eq 0 -and $listOut) {
        $lines = $listOut -split "`r?`n"
        $idRegex = [regex]::new('^\s*([0-9a-fA-F]{32})\b')
        $idsToDelete = @()
        foreach ($line in $lines) {
            $m = $idRegex.Match($line)
            if ($m.Success) { $idsToDelete += $m.Groups[1].Value }
        }
        foreach ($eid in $idsToDelete) {
            & dnx ActionView.Cli --yes -- delete $eid --force 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "publish-rolling-status: failed to delete stale entry $eid (exit=$LASTEXITCODE); duplicates may accumulate"
            }
        }
    }
} catch {
    Write-Warning "publish-rolling-status: error while listing/deleting old entries: $($_.Exception.Message)"
}

# --- Add the fresh entry -----------------------------------------------------
$tmpFile = Join-Path $env:TEMP "raindrop-watcher-status-$([guid]::NewGuid().ToString('N')).json"
try {
    $entry | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmpFile -Encoding UTF8
    & dnx ActionView.Cli --yes -- add --file $tmpFile 2>&1 | ForEach-Object { Write-Information $_ -InformationAction Continue }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "publish-rolling-status: actionview add exit=$LASTEXITCODE"
    }
} catch {
    Write-Warning "publish-rolling-status: add threw: $($_.Exception.Message)"
} finally {
    Remove-Item -LiteralPath $tmpFile -Force -ErrorAction Ignore
}

@{
    ok                   = $true
    inboxCount           = $inboxCount
    dispatched           = $dispatchedItems.Count
    skipped              = $skippedItems.Count
    deferred             = $deferredItems.Count
    deadLetteredThisTick = $deadLetteredOk.Count
    deadLetterFailures   = $deadLetteredFail.Count
    stuckReclassified    = $stuckItems.Count
    severity             = $severity
} | ConvertTo-Json -Compress
