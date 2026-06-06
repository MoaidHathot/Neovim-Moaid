#!/usr/bin/env pwsh
# CLI-based targeted frame capture for video processors.
#
# Replaces the MCP-driven approach we tried first: Copilot's tool-name
# validator (`^[a-zA-Z0-9_-]{1,128}$`) rejects MCP tools whose names
# contain dots / slashes, which Zakira.Replay's MCP uses. Going through
# the CLI dodges that entirely AND is deterministic (we know exactly what
# was attempted, no LLM-tool-discovery uncertainty).
#
# Usage:
#   capture-targeted-frames.ps1 -PicksJson '<json>' `
#                               -Source '<video url>' `
#                               -ZakiraAnalyzeJson '<json>' `
#                               -MaxCap <int>
#
# PicksJson shape (LLM-produced upstream):
#   {
#     "ok": true,
#     "picks": [
#       { "timestamp": "hh:mm:ss", "reason": "one short sentence" }
#     ]
#   }
#
# ZakiraAnalyzeJson shape (from the baseline analyze step):
#   { "runId": "...", "artifactDirectory": "...", ... }
#
# Stdout (single JSON object; SAME shape as the old MCP-based step):
#   {
#     "ok": true,
#     "runId": "<id>",
#     "captured": [
#       { "timestamp": "...", "reason": "...", "path": "...", "fileUri": "file:///..." }
#     ],
#     "skipped": [ { "timestamp": "...", "reason": "..." } ],
#     "budget": "captured N of M",
#     "warnings": [ ... ]      # surfaced from the CLI when present
#   }

param(
    [Parameter(Mandatory=$true)] [string]$PicksJson,
    [Parameter(Mandatory=$true)] [string]$Source,
    [Parameter(Mandatory=$true)] [string]$ZakiraAnalyzeJson,
    [Parameter(Mandatory=$true)] [int]   $MaxCap
)

$ErrorActionPreference = 'Stop'

function Write-Out($obj) {
    $obj | ConvertTo-Json -Depth 8 -Compress
    exit 0
}

# Extract the runId from the baseline analyze output. If we can't, surface
# the issue but don't fail the orchestration -- synth/ActionView gracefully
# render without targeted images.
$RunId = $null
try {
    $analyze = $ZakiraAnalyzeJson | ConvertFrom-Json
    if ($analyze -and $analyze.runId) { $RunId = "$($analyze.runId)" }
} catch {
    # fall through; handled below
}
if ([string]::IsNullOrWhiteSpace($RunId)) {
    Write-Out @{
        ok = $false
        runId = $null
        captured = @()
        skipped = @()
        budget = "captured 0 of $MaxCap"
        error = 'could not extract runId from zakira-analyze output'
    }
}

# Parse picks. Best-effort: if the upstream Prompt step returned junk, emit
# empty captured array and let synth/ActionView gracefully render without
# images. We never want this step to be the cause of an orchestration failure.
$picks = @()
try {
    $parsed = $PicksJson | ConvertFrom-Json
    if ($parsed -and $parsed.picks) {
        foreach ($p in @($parsed.picks)) {
            if ($p.timestamp -and $p.reason) {
                $picks += [pscustomobject]@{ timestamp = "$($p.timestamp)"; reason = "$($p.reason)" }
            }
        }
    }
} catch {
    # Treat as no picks.
}

if ($picks.Count -eq 0) {
    Write-Out @{
        ok = $true
        runId = $RunId
        captured = @()
        skipped = @()
        budget = "captured 0 of $MaxCap"
        note = 'no picks from upstream prompt'
    }
}

# Cap.
$capped = if ($picks.Count -gt $MaxCap) { @($picks[0..($MaxCap - 1)]) } else { $picks }
$overflowSkipped = @()
if ($picks.Count -gt $MaxCap) {
    foreach ($p in $picks[$MaxCap..($picks.Count - 1)]) {
        $overflowSkipped += [pscustomobject]@{ timestamp = $p.timestamp; reason = "exceeds cap of $MaxCap" }
    }
}

# Batch into a single Zakira.Replay frames call (faster than N separate
# yt-dlp probes + browser launches). `--at` takes comma-separated values.
$timestamps = ($capped | ForEach-Object { $_.timestamp }) -join ','
$cliOutLines = & dnx Zakira.Replay --yes -- frames $Source `
    --at $timestamps `
    --run-id $RunId `
    --output-format json `
    --max-edge 1280 `
    --allow-media-download 2>&1
$cliExit = $LASTEXITCODE

# The CLI prints status lines to stderr (which 2>&1 merges in); the JSON
# payload is the last balanced-brace block on stdout. Pull it out.
$joined = ($cliOutLines | Out-String)
$jsonStart = $joined.IndexOf("{`r`n  `"runId`"")
if ($jsonStart -lt 0) { $jsonStart = $joined.IndexOf('{"runId"') }
if ($jsonStart -lt 0) { $jsonStart = $joined.LastIndexOf('{') }
$jsonText = if ($jsonStart -ge 0) { $joined.Substring($jsonStart) } else { '' }

$cliPayload = $null
if ($jsonText) {
    try { $cliPayload = $jsonText | ConvertFrom-Json } catch {}
}

if ($cliExit -ne 0 -and -not $cliPayload) {
    # Hard CLI failure with no payload to harvest -- still don't throw; let
    # synth render without images and record the error in the envelope so
    # the user can see what went wrong in the per-step output.
    Write-Out @{
        ok = $false
        runId = $RunId
        captured = @()
        skipped = $overflowSkipped
        budget = "captured 0 of $MaxCap"
        error = "Zakira.Replay frames exit=$cliExit"
        cliOutputTail = (($cliOutLines | Select-Object -Last 10) -join "`n")
    }
}

# Correlate output frames back to picks. The CLI's `frames` array entries
# typically carry a `timestamp` / `time` / `seconds` field. We try a few
# common shapes; on failure we positionally pair them with picks (which
# preserves order since we passed --at in order).
$cliFrames = @()
if ($cliPayload -and $cliPayload.frames) { $cliFrames = @($cliPayload.frames) }

$captured = @()
$failed   = @()
for ($i = 0; $i -lt $capped.Count; $i++) {
    $pick = $capped[$i]
    $frame = if ($i -lt $cliFrames.Count) { $cliFrames[$i] } else { $null }
    if (-not $frame) {
        $failed += [pscustomobject]@{ timestamp = $pick.timestamp; reason = 'no frame returned by CLI (source may not support frame capture)' }
        continue
    }
    # Try common path field names.
    $path = $null
    foreach ($field in @('path','file','filePath','outputPath','imagePath')) {
        if ($frame.$field) { $path = "$($frame.$field)"; break }
    }
    if (-not $path) {
        $failed += [pscustomobject]@{ timestamp = $pick.timestamp; reason = 'CLI frame has no recognizable path field' }
        continue
    }
    $fileUri = ''
    try { $fileUri = ([System.Uri]::new($path)).AbsoluteUri } catch { $fileUri = "file:///$($path -replace '\\','/')" }
    $captured += [pscustomobject]@{
        timestamp = $pick.timestamp
        reason    = $pick.reason
        path      = $path
        fileUri   = $fileUri
    }
}

Write-Out @{
    ok       = $true
    runId    = $RunId
    captured = $captured
    skipped  = ($overflowSkipped + $failed)
    budget   = ("captured {0} of {1}" -f $captured.Count, $MaxCap)
    warnings = if ($cliPayload -and $cliPayload.warnings) { $cliPayload.warnings } else { @() }
}
