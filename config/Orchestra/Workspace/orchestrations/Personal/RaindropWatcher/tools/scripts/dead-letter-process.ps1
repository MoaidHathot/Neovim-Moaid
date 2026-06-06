#!/usr/bin/env pwsh
# Dead-letter handler invoked once per tracker tick.
# For each item in `selection.deadLetter`:
#   1. Move the raindrop from AI-Inbox into the dead-letter collection and
#      tag it `dead-letter` via the raindrop CLI.
#   2. Flip its Zakira.Exchange record to status="dead-lettered" with
#      deadLetteredAt timestamp.
#   3. Publish a `raindrop-dead-letter` ActionView entry (severity=critical).
#
# Per-item failures are caught and reported; the script keeps going so one
# bad item doesn't block the rest. It exits 0 unless ALL items fail
# (suggesting a systemic problem worth surfacing to the tracker run log).
#
# Usage:
#   dead-letter-process.ps1 -RaindropCli <path-to-raindrop.cs> `
#                           -BootstrapJson '<json>' `
#                           -SelectionJson '<json>' `
#                           -ZakiraDb <path> `
#                           -ZakiraCategory <category>
#
# Stdout: a single JSON object summarizing per-item results.

param(
    [Parameter(Mandatory=$true)] [string]$RaindropCli,
    [Parameter(Mandatory=$true)] [string]$BootstrapJson,
    [Parameter(Mandatory=$true)] [string]$SelectionJson,
    [Parameter(Mandatory=$true)] [string]$ZakiraDb,
    [Parameter(Mandatory=$true)] [string]$ZakiraCategory
)

$ErrorActionPreference = 'Continue'

function Write-FinalJson($obj) {
    $obj | ConvertTo-Json -Depth 8 -Compress
}

try {
    $bootstrap = $BootstrapJson | ConvertFrom-Json
} catch {
    Write-FinalJson @{ ok = $false; error = "bootstrap json parse failed: $($_.Exception.Message)"; deadLettered = @() }
    exit 0
}
try {
    $selection = $SelectionJson | ConvertFrom-Json
} catch {
    Write-FinalJson @{ ok = $false; error = "selection json parse failed: $($_.Exception.Message)"; deadLettered = @() }
    exit 0
}

$deadLetterCollectionId = $bootstrap.deadLetterCollectionId
if (-not $deadLetterCollectionId) {
    Write-FinalJson @{ ok = $false; error = "bootstrap.deadLetterCollectionId missing"; deadLettered = @() }
    exit 0
}

$items = @()
if ($selection.deadLetter) { $items = @($selection.deadLetter) }

if ($items.Count -eq 0) {
    Write-FinalJson @{ ok = $true; deadLettered = @(); skipped = @(); note = 'no dead-letter items this tick' }
    exit 0
}

$results = @()
$nowIso  = (Get-Date).ToUniversalTime().ToString('o')

foreach ($it in $items) {
    $rid = "$($it.raindropId)"
    $url = "$($it.url)"
    $title = "$($it.title)"
    $attempts = if ($it.attempts) { [int]$it.attempts } else { 0 }
    $lastError = "$($it.lastError)"
    if ([string]::IsNullOrWhiteSpace($lastError)) { $lastError = 'unknown failure (see prior raindrop-error entries)' }

    $perItem = [ordered]@{
        raindropId = $rid
        url        = $url
        moved      = $false
        zakiraUpdated = $false
        actionViewPublished = $false
        errors     = @()
    }

    # --- 1) Move the raindrop into the dead-letter collection ----------------
    try {
        $moveOut = & dotnet run $RaindropCli -- move $rid --to-collection $deadLetterCollectionId --add-tag dead-letter 2>&1
        if ($LASTEXITCODE -ne 0) {
            $perItem.errors += "move exit=${LASTEXITCODE}: $(($moveOut | Out-String).Trim())"
        } else {
            $perItem.moved = $true
        }
    } catch {
        $perItem.errors += "move threw: $($_.Exception.Message)"
    }

    # --- 2) Update Zakira state record to status="dead-lettered" ------------
    try {
        $updatedData = @{
            raindropId      = $rid
            url             = $url
            title           = $title
            status          = 'dead-lettered'
            deadLetteredAt  = $nowIso
            attempts        = $attempts
            lastError       = $lastError
        } | ConvertTo-Json -Compress
        $zOut = & dnx Zakira.Exchange --yes -- --db $ZakiraDb edit `
            --category $ZakiraCategory `
            --key $rid `
            --data $updatedData `
            --reason "dead-lettered by tracker after max attempts" `
            --tags dead-letter 2>&1
        if ($LASTEXITCODE -ne 0) {
            $perItem.errors += "zakira edit exit=${LASTEXITCODE}: $(($zOut | Out-String).Trim())"
        } else {
            $perItem.zakiraUpdated = $true
        }
    } catch {
        $perItem.errors += "zakira edit threw: $($_.Exception.Message)"
    }

    # --- 3) Publish a raindrop-dead-letter ActionView entry -----------------
    $deadLetterEntryId = "raindrop-dead-letter-$rid"  # stable per-raindrop -> idempotent
    $reprocessScript = Join-Path $PSScriptRoot 'reprocess-raindrop.ps1'
    $tmpFile = Join-Path $env:TEMP "raindrop-deadletter-$rid-$([guid]::NewGuid().ToString('N')).json"
    try {
        $entry = @{
            schemaVersion = '1'
            id            = $deadLetterEntryId
            type          = 'raindrop-dead-letter'
            source        = 'raindrop-tracker'
            title         = "Raindrop dead-lettered: $title"
            subtitle      = "after $attempts attempt(s) -- $url"
            severity      = 'critical'
            icon          = 'skull'
            tags          = @('raindrop','dead-letter')
            content = @(
                @{ type = 'keyValue'; label = 'Dead-letter'; pairs = @{
                    'Raindrop ID'       = $rid
                    'URL'               = $url
                    'Attempts'          = "$attempts"
                    'Last error'        = $lastError
                    'Dead-lettered at'  = $nowIso
                } }
                @{ type = 'alert'; level = 'error'; title = 'Manual intervention required'; message = "This raindrop was moved to the dead-letter collection after $attempts failed attempt(s). Investigate the failures (see prior raindrop-error entries), fix the underlying issue, and either click Reprocess to retry from scratch or delete it manually." }
                @{ type = 'link'; label = 'Open original'; url = $url }
            )
            actions = @(
                @{ label = 'Open in raindrop.io'; style = 'default'; command = @{
                    type = 'cli'; program = 'cmd'; args = @('/c','start','','https://app.raindrop.io/my/0/item/' + $rid + '/edit')
                }; onSuccess = 'keep' }
                @{ label = 'Open dead-letter collection'; style = 'default'; command = @{
                    type = 'cli'; program = 'cmd'; args = @('/c','start','','https://app.raindrop.io/my/' + $deadLetterCollectionId)
                }; onSuccess = 'keep' }
                @{ label = 'Reprocess (move back to AI-Inbox, reset attempts)'; style = 'primary'; confirmMessage = 'Move this raindrop back to AI-Inbox, clear its Zakira state, and rerun analysis from scratch on the next tracker tick? Use this after you have fixed the underlying issue that caused the failures.'; command = @{
                    type = 'cli'; program = 'pwsh'; args = @('-NoProfile','-File',$reprocessScript,'-RaindropId',$rid)
                }; onSuccess = 'archive' }
            )
        }
        $entry | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmpFile -Encoding UTF8
        # Delete-then-add upsert so an accidental re-dispatch of the same dead-letter item doesn't accumulate entries.
        & dnx ActionView.Cli --yes -- delete $deadLetterEntryId --force 2>$null | Out-Null
        $avOut = & dnx ActionView.Cli --yes -- add --file $tmpFile 2>&1
        if ($LASTEXITCODE -ne 0) {
            $perItem.errors += "actionview add exit=${LASTEXITCODE}: $(($avOut | Out-String).Trim())"
        } else {
            $perItem.actionViewPublished = $true
        }
    } catch {
        $perItem.errors += "actionview publish threw: $($_.Exception.Message)"
    } finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction Ignore
    }

    $perItem.ok = ($perItem.errors.Count -eq 0)
    $results += [pscustomobject]$perItem
}

$allFailed = -not ($results | Where-Object { $_.ok }) -and ($results.Count -gt 0)
Write-FinalJson @{
    ok            = -not $allFailed
    deadLettered  = $results
    note          = if ($allFailed) { 'all dead-letter items failed -- check raindrop CLI / zakira / ActionView availability' } else { '' }
}
