#!/usr/bin/env pwsh
# Manual reprocess of a single raindrop. Wired up as the "Reprocess" action
# on every per-raindrop success ActionView entry, and usable directly from
# the CLI for scripted recovery.
#
# What it does (all best-effort, partial-failure-tolerant):
#   1. Looks up the raindrop's current collection via the raindrop CLI.
#   2. If the raindrop is in AI-Processed or AI-DeadLetter, moves it back
#      into AI-Inbox.
#   3. Removes the `processed` and `dead-letter` tags so the next tick's
#      classifier doesn't get confused.
#   4. Deletes the Zakira.Exchange `raindrop-watcher-state` record for the
#      raindrop, so the next tracker tick treats it as a brand-new item
#      (rather than applying the "completed -- skip" rule).
#   5. Deletes any per-raindrop ActionView entries with the deterministic
#      ids raindrop-<id>-recipe, raindrop-<id>-video-session,
#      raindrop-<id>-video-generic, raindrop-<id>-article,
#      raindrop-error-<id>, raindrop-dead-letter-<id>.
#
# After this script returns, the next tracker tick (or the immediate next
# `orchestra run raindrop-tracker`) will re-dispatch the raindrop through
# the full classify -> processor pipeline. Side-effect dedup still applies:
# save-recipe.ps1 overwrites or timestamps, save-article-images.ps1 hashes
# URLs and skips cache hits, ActionView entries upsert by stable id, and
# Zakira.Replay's analyze step reuses its `--cache` per runId.
#
# Usage:
#   reprocess-raindrop.ps1 -RaindropId <id> `
#                          [-InboxName 'AI-Inbox'] `
#                          [-RaindropCli '<path>'] `
#                          [-SkipMove]                  # only clear state, don't move
#                          [-SkipStateDelete]           # only move, keep zakira record
#                          [-SkipActionViewDismiss]     # leave AV entries alone
#
# Defaults: full reprocess (move + state delete + AV dismiss).
#
# Stdout: a single JSON object summarising what was done.

param(
    [Parameter(Mandatory=$true)] [string]$RaindropId,
    [string]$InboxName = 'AI-Inbox',
    [string]$RaindropCli,
    [switch]$SkipMove,
    [switch]$SkipStateDelete,
    [switch]$SkipActionViewDismiss
)

$ErrorActionPreference = 'Continue'

if (-not $RaindropCli) {
    # Default to the sibling raindrop.cs file when invoked from this folder.
    $RaindropCli = Join-Path (Split-Path -Parent $PSScriptRoot) 'raindrop.cs'
}
if (-not (Test-Path -LiteralPath $RaindropCli)) {
    @{ ok = $false; error = "raindrop CLI not found: $RaindropCli" } | ConvertTo-Json -Compress
    exit 1
}

$result = [ordered]@{
    ok                    = $true
    raindropId            = $RaindropId
    moved                 = $false
    movedFromCollection   = $null
    movedToCollection     = $null
    stateRecordDeleted    = $false
    actionViewIdsDeleted  = @()
    actionViewIdsMissing  = @()
    errors                = @()
}

# --- 1) Resolve the inbox collection id --------------------------------------
$inboxId = $null
if (-not $SkipMove) {
    try {
        $inboxJson = & dotnet run $RaindropCli -- ensure-collection $InboxName 2>$null
        if ($LASTEXITCODE -ne 0) {
            $result.errors += "ensure-collection $InboxName exit=$LASTEXITCODE"
        } else {
            $inboxObj = ($inboxJson -join "`n") | ConvertFrom-Json
            if ($inboxObj.id) { $inboxId = [long]$inboxObj.id }
        }
    } catch {
        $result.errors += "ensure-collection threw: $($_.Exception.Message)"
    }
}

# --- 2) Look up the raindrop's current collection ----------------------------
$currentCollectionId = $null
try {
    $getJson = & dotnet run $RaindropCli -- get $RaindropId 2>$null
    if ($LASTEXITCODE -eq 0) {
        $getObj = ($getJson -join "`n") | ConvertFrom-Json
        # raindrop API response wraps the item under `.item`.
        $item = if ($getObj.item) { $getObj.item } else { $getObj }
        if ($item.collection -and $item.collection.'$id') {
            $currentCollectionId = [long]$item.collection.'$id'
        }
        $result.movedFromCollection = $currentCollectionId
    } else {
        $result.errors += "raindrop get $RaindropId exit=$LASTEXITCODE"
    }
} catch {
    $result.errors += "raindrop get threw: $($_.Exception.Message)"
}

# --- 3) Move back to AI-Inbox if needed --------------------------------------
if (-not $SkipMove -and $inboxId) {
    if ($currentCollectionId -and $currentCollectionId -eq $inboxId) {
        # Already in inbox; nothing to do for the move part.
        $result.movedToCollection = $inboxId
    } else {
        try {
            $moveOut = & dotnet run $RaindropCli -- move $RaindropId --to-collection $inboxId 2>&1
            if ($LASTEXITCODE -ne 0) {
                $result.errors += "raindrop move $RaindropId -> $inboxId exit=${LASTEXITCODE}: $(($moveOut | Out-String).Trim())"
            } else {
                $result.moved = $true
                $result.movedToCollection = $inboxId
            }
        } catch {
            $result.errors += "raindrop move threw: $($_.Exception.Message)"
        }
        # Strip stale workflow tags so classify/router doesn't get confused.
        foreach ($tag in @('processed','dead-letter','failed')) {
            try {
                & dotnet run $RaindropCli -- remove-tag $RaindropId $tag 2>$null | Out-Null
            } catch {
                # Best-effort; ignore.
            }
        }
    }
}

# --- 4) Delete the Zakira state record ---------------------------------------
if (-not $SkipStateDelete) {
    $zakiraDb = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME 'orchestra/zakira.db' } else { $null }
    if (-not $zakiraDb) {
        $result.errors += 'XDG_CONFIG_HOME not set; cannot locate zakira.db (skipping state delete)'
    } else {
        try {
            $zOut = & dnx Zakira.Exchange --yes -- --db $zakiraDb delete --category raindrop-watcher-state --key $RaindropId 2>&1
            if ($LASTEXITCODE -eq 0) {
                $result.stateRecordDeleted = $true
            } else {
                # Treat "not found" as success (idempotency).
                $tail = ($zOut | Out-String)
                if ($tail -match 'not found' -or $tail -match 'no entry') {
                    $result.stateRecordDeleted = $true
                } else {
                    $result.errors += "zakira delete exit=${LASTEXITCODE}: $($tail.Trim())"
                }
            }
        } catch {
            $result.errors += "zakira delete threw: $($_.Exception.Message)"
        }
    }
}

# --- 5) Dismiss/delete per-raindrop ActionView entries -----------------------
if (-not $SkipActionViewDismiss) {
    $candidateIds = @(
        "raindrop-$RaindropId-recipe",
        "raindrop-$RaindropId-video-session",
        "raindrop-$RaindropId-video-generic",
        "raindrop-$RaindropId-article",
        "raindrop-error-$RaindropId",
        "raindrop-dead-letter-$RaindropId"
    )
    foreach ($id in $candidateIds) {
        try {
            $delOut = & dnx ActionView.Cli --yes -- delete $id --force 2>&1
            if ($LASTEXITCODE -eq 0) {
                $result.actionViewIdsDeleted += $id
            } else {
                # Most ids won't exist for any given raindrop; that's fine.
                $result.actionViewIdsMissing += $id
            }
        } catch {
            $result.errors += "actionview delete $id threw: $($_.Exception.Message)"
        }
    }
}

if ($result.errors.Count -gt 0) { $result.ok = $false }
$result | ConvertTo-Json -Depth 6 -Compress
