#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Reconcile raindrop-watcher-state records that were wrongly marked "completed"
    while their child processor actually FAILED (the pre-gate bug), and move those
    raindrops back to AI-Inbox for reprocessing.

.DESCRIPTION
    Before the verify-dispatch gate existed, `invoke_orchestration` (sync) returned
    status="Failed" without throwing, so dispatch-processor succeeded even when the
    child failed; move-to-processed then moved the raindrop into AI-Processed and
    mark-completed recorded state="completed". Those items are stranded: out of the
    inbox, invisible to the tracker's retry/dead-letter rules, and with no summary.

    This tool reads the on-disk raindrop-processor execution artifacts to recover the
    REAL child status (the dispatch-processor envelope's `status`), builds a
    raindropId -> latest-child-status map, and for every state record currently
    marked "completed" whose latest processing actually FAILED, invokes
    reprocess-raindrop.ps1 to move it back to AI-Inbox, strip stale tags, clear the
    Zakira state record, and remove per-raindrop ActionView entries.

    SAFE BY DEFAULT: dry-run unless -Apply is passed. Conservative: only records it
    can POSITIVELY confirm failed (a matching execution with a non-success status)
    are touched; anything ambiguous is left alone.

.PARAMETER Database         zakira.db path. Default $XDG_CONFIG_HOME/orchestra/zakira.db.
.PARAMETER ExecutionsRoot   raindrop-processor executions dir. Default the OrchestraHost location.
.PARAMETER ReprocessScript  Path to reprocess-raindrop.ps1. Default the sibling script.
.PARAMETER Category         Memory category. Default 'raindrop-watcher-state'.
.PARAMETER Apply            Actually move items back. Without it, only reports.
#>
[CmdletBinding()]
param(
    [string]$Database,
    [string]$ExecutionsRoot = (Join-Path $env:LOCALAPPDATA 'OrchestraHost/executions/raindrop-processor'),
    [string]$ReprocessScript = (Join-Path $PSScriptRoot 'reprocess-raindrop.ps1'),
    [string]$Category = 'raindrop-watcher-state',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if (-not $Database) {
    if (-not $env:XDG_CONFIG_HOME) { throw "reconcile: -Database not given and XDG_CONFIG_HOME is not set." }
    $Database = Join-Path $env:XDG_CONFIG_HOME 'orchestra/zakira.db'
}
if (-not (Test-Path -LiteralPath $Database))       { throw "reconcile: database not found: $Database" }
if (-not (Test-Path -LiteralPath $ExecutionsRoot)) { throw "reconcile: executions root not found: $ExecutionsRoot" }
if ($Apply -and -not (Test-Path -LiteralPath $ReprocessScript)) { throw "reconcile: reprocess script not found: $ReprocessScript" }

$dotnet = (Get-Command dotnet -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$successStatuses = @('succeeded', 'completed', 'success', 'ok')

function Test-Success([string]$status) {
    if ([string]::IsNullOrWhiteSpace($status)) { return $false }
    return $successStatuses -contains $status.Trim().ToLowerInvariant()
}

function Get-DataJsonFromCliOutput {
    param([string[]]$Lines)
    if ($null -eq $Lines -or $Lines.Count -eq 0) { return $null }
    $dataIdx = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) { if ([string]$Lines[$i] -match '^\s*Data:\s*') { $dataIdx = $i; break } }
    if ($dataIdx -lt 0) { return $null }
    $endIdx = $Lines.Count
    for ($j = $dataIdx + 1; $j -lt $Lines.Count; $j++) {
        if ([string]$Lines[$j] -match '^\s*(Author|Reason|Tags|Custom|Created|Last Modified):\s*') { $endIdx = $j; break }
    }
    $span = ($Lines[$dataIdx..($endIdx - 1)] | ForEach-Object { [string]$_ }) -join "`n"
    return ($span -replace '^\s*Data:\s*', '').Trim()
}

function Get-ChildStatus([string]$ExecutionDir) {
    $dp = Join-Path $ExecutionDir 'dispatch-processor-outputs.json'
    if (-not (Test-Path -LiteralPath $dp)) { return $null }
    try { $content = (Get-Content -LiteralPath $dp -Raw | ConvertFrom-Json).content } catch { return $null }
    if ([string]::IsNullOrWhiteSpace($content)) { return $null }
    if ($content -match '"status"\s*:\s*"([^"]+)"')        { return $Matches[1] }
    if ($content -match 'status\s*\*\*([A-Za-z-]+)\*\*')   { return $Matches[1] }
    return $null
}

# --- 1) Build raindropId -> latest child status from execution artifacts ------
Write-Host "Scanning execution artifacts under $ExecutionsRoot ..." -ForegroundColor Cyan
$latest = @{}   # rid -> @{ status; started; execId }
foreach ($d in (Get-ChildItem -LiteralPath $ExecutionsRoot -Directory -ErrorAction SilentlyContinue)) {
    $rj = Join-Path $d.FullName 'run.json'
    if (-not (Test-Path -LiteralPath $rj)) { continue }
    try { $run = Get-Content -LiteralPath $rj -Raw | ConvertFrom-Json } catch { continue }
    $rid = [string]$run.parameters.raindropId
    if ([string]::IsNullOrWhiteSpace($rid)) { continue }
    $started = [datetime]::MinValue
    try { $started = [datetime]::Parse([string]$run.startedAt, [System.Globalization.CultureInfo]::InvariantCulture) } catch { }
    $childStatus = Get-ChildStatus -ExecutionDir $d.FullName
    if (-not $latest.ContainsKey($rid) -or $started -gt $latest[$rid].started) {
        $latest[$rid] = @{ status = $childStatus; started = $started; execId = $d.Name }
    }
}
Write-Host "  found processing history for $($latest.Count) raindrop(s)." -ForegroundColor DarkGray

# --- 2) Walk state records; find completed-but-actually-failed ----------------
$listOut = & $dotnet dnx Zakira.Exchange --yes -- --db $Database list --cat $Category -n 100000 2>&1
if ($LASTEXITCODE -ne 0) { throw "reconcile: list failed: $($listOut -join ' ')" }
$keys = @($listOut) | Where-Object { $_ -match "^\s*\[$([regex]::Escape($Category))\]\s+(\S+)\s" } |
    ForEach-Object { ($_ -replace "^\s*\[$([regex]::Escape($Category))\]\s+(\S+).*", '$1') }

$mislabeled = New-Object System.Collections.Generic.List[object]
$skippedNoData = 0; $genuineCompleted = 0; $otherStatus = 0
foreach ($key in $keys) {
    $o = & $dotnet dnx Zakira.Exchange --yes -- --db $Database get $Category $key 2>&1
    if ($LASTEXITCODE -ne 0) { continue }
    $json = Get-DataJsonFromCliOutput -Lines @($o)
    $obj = $null; try { $obj = $json | ConvertFrom-Json -DateKind String -ErrorAction Stop } catch { }
    $status = if ($obj) { [string]$obj.status } else { '' }
    if ($status -ne 'completed') { $otherStatus++; continue }

    if (-not $latest.ContainsKey($key)) { $skippedNoData++; continue }   # can't confirm -> leave alone
    $child = $latest[$key].status
    if (Test-Success $child) { $genuineCompleted++; continue }           # genuinely processed -> leave

    $mislabeled.Add([pscustomobject]@{
        raindropId = $key
        childStatus = if ($child) { $child } else { '(unknown)' }
        lastRun = $latest[$key].started
        title = if ($obj) { [string]$obj.title } else { '' }
    })
}

Write-Host ""
Write-Host "State scan: $($keys.Count) record(s) | genuine completed=$genuineCompleted | other status=$otherStatus | completed-without-history=$skippedNoData" -ForegroundColor DarkGray
Write-Host "Completed-but-actually-FAILED (to move back to AI-Inbox): $($mislabeled.Count)" -ForegroundColor $(if ($mislabeled.Count) { 'Yellow' } else { 'Green' })
foreach ($m in ($mislabeled | Sort-Object lastRun)) {
    Write-Host ("  {0,-12} child={1,-10} lastRun={2:u}  {3}" -f $m.raindropId, $m.childStatus, $m.lastRun, $m.title)
}

if ($mislabeled.Count -eq 0) { Write-Host "`nNothing to reconcile." -ForegroundColor Green; exit 0 }
if (-not $Apply) {
    Write-Host "`n[dry-run] Re-run with -Apply to move these $($mislabeled.Count) raindrop(s) back to AI-Inbox (clears state + strips tags + removes ActionView entries)." -ForegroundColor Yellow
    exit 0
}

# --- 3) Move each back to AI-Inbox via reprocess-raindrop.ps1 ------------------
Write-Host "`nApplying: moving $($mislabeled.Count) raindrop(s) back to AI-Inbox ..." -ForegroundColor Cyan
$done = 0; $failed = 0
foreach ($m in $mislabeled) {
    try {
        $out = & pwsh -NoProfile -File $ReprocessScript -RaindropId $m.raindropId 2>&1
        $res = $null; try { $res = ($out | Select-Object -Last 1) | ConvertFrom-Json } catch { }
        if ($res -and $res.ok) { $done++; Write-Host ("  reprocess-queued {0}" -f $m.raindropId) -ForegroundColor Green }
        else { $failed++; Write-Warning ("  reprocess reported problems for {0}: {1}" -f $m.raindropId, ($out -join ' ')) }
    } catch {
        $failed++; Write-Warning ("  reprocess threw for {0}: {1}" -f $m.raindropId, $_.Exception.Message)
    }
}
Write-Host ""
Write-Host ("Reconciled={0}  Failed={1}" -f $done, $failed) -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
if ($failed -gt 0) { exit 1 } else { exit 0 }
