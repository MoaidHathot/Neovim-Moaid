#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deterministically build the raindrop-article ActionView entry JSON.

.DESCRIPTION
    Replaces the LLM `create-action-view-entry` step, which merely assembled a fixed
    JSON structure around the synthesized markdown but occasionally HUNG on its final
    turn (0 output / null usage / 600s timeout) for large articles -- silently failing
    the whole orchestration even though the analysis had already been produced.

    All inputs are already available deterministically:
      * the analysis markdown (with inline images) is the synthesize step's saved file,
      * article metadata (site, published date, byline, fetch mode) is in the
        fetch-readable envelope,
      * everything else is raindrop params.

    The Visual-evidence section is rebuilt from the `![alt](url)` image embeds found in
    the analysis markdown. Output is written to -OutFile and its path echoed to stdout.

.NOTES
    Mirrors the entry shape the LLM used to emit, so it validates against the same
    ActionView schema (`ActionView.Cli validate --strict`).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$RaindropId,
    [string]$Title = '',
    [string]$Url = '',
    [string]$TagsJson = '[]',
    [string]$Note = '',
    [string]$AddedAt = '',
    [Parameter(Mandatory=$true)] [string]$SynthesisFile,
    [string]$ReadableJson = '',
    [string]$FallbackText = '',
    [string]$Source = 'raindrop-article-generic-processor',
    [Parameter(Mandatory=$true)] [string]$ReprocessScript,
    [Parameter(Mandatory=$true)] [string]$OutFile
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if ([string]::IsNullOrWhiteSpace($RaindropId)) { throw 'build-article-actionview-entry: RaindropId is required.' }

# --- analysis markdown (the synthesize step's saved file) --------------------
$analysis = ''
if (-not [string]::IsNullOrWhiteSpace($SynthesisFile) -and (Test-Path -LiteralPath $SynthesisFile)) {
    $analysis = Get-Content -LiteralPath $SynthesisFile -Raw
}
if ([string]::IsNullOrWhiteSpace($analysis)) { $analysis = $FallbackText }
if ([string]::IsNullOrWhiteSpace($analysis)) { $analysis = "_Analysis unavailable._" }

# --- article metadata from the fetch-readable envelope -----------------------
$meta = $null
if (-not [string]::IsNullOrWhiteSpace($ReadableJson)) {
    try { $meta = $ReadableJson | ConvertFrom-Json -ErrorAction Stop } catch { $meta = $null }
}
function Meta([string]$name) {
    if ($null -eq $meta) { return $null }
    $p = $meta.PSObject.Properties[$name]
    if ($p -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)) { return [string]$p.Value }
    return $null
}
$byline      = Meta 'byline'
$siteName    = Meta 'siteName'
$publishedAt = Meta 'publishedAt'
$fetchMode   = Meta 'mode'; if (-not $fetchMode) { $fetchMode = 'unknown' }

$subtitleParts = @($byline, $siteName, $publishedAt) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$subtitle = ($subtitleParts -join ' | ')

# --- tags: drop workflow tags, keep user tags, add raindrop+article ----------
$workflow = @('processed', 'processing', 'failed', 'dead-letter', 'queued')
$rawTags = @()
try { $rawTags = @($TagsJson | ConvertFrom-Json) } catch { $rawTags = @() }
$rawTags = @($rawTags | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$userTags = @($rawTags | Where-Object { $workflow -notcontains $_.ToLowerInvariant() })
$origTagsDisplay = if ($userTags.Count -gt 0) { $userTags -join ', ' } else { 'None' }
$entryTags = @($userTags + @('raindrop', 'article') | Select-Object -Unique)

# --- Visual-evidence images extracted from the analysis markdown -------------
$images = New-Object System.Collections.Generic.List[object]
$seen = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in [regex]::Matches($analysis, '!\[(?<alt>[^\]]*)\]\((?<url>[^)\s]+)\)')) {
    $u = $m.Groups['url'].Value
    if ($seen.Add($u)) {
        $images.Add([pscustomobject]@{ alt = $m.Groups['alt'].Value; url = $u })
    }
}

# --- assemble content blocks -------------------------------------------------
$noteDisplay = if ([string]::IsNullOrWhiteSpace($Note)) { 'None' } else { $Note }
$addedDisplay = if ([string]::IsNullOrWhiteSpace($AddedAt)) { 'Unknown' } else { $AddedAt }

$content = New-Object System.Collections.Generic.List[object]
$content.Add([ordered]@{
    type  = 'keyValue'
    label = 'Source'
    pairs = [ordered]@{
        'URL'           = [ordered]@{ type = 'link'; url = $Url; label = $Url }
        'Added at'      = $addedDisplay
        'Original tags' = $origTagsDisplay
        'Note'          = $noteDisplay
        'Fetch mode'    = $fetchMode
    }
})
$content.Add([ordered]@{
    type = 'section'; title = 'Analysis'
    content = @([ordered]@{ type = 'markdown'; body = $analysis })
})
if ($images.Count -gt 0) {
    $veBody = ($images | ForEach-Object { "### $($_.alt)`n`n![$($_.alt)]($($_.url))" }) -join "`n`n"
    $content.Add([ordered]@{
        type = 'section'; title = 'Visual evidence'; badge = "$($images.Count) images"
        content = @([ordered]@{ type = 'markdown'; body = $veBody })
    })
}
$content.Add([ordered]@{ type = 'link'; label = 'Open original'; url = $Url })

# --- actions -----------------------------------------------------------------
$urlForPs = $Url -replace "'", "''"
$actions = @(
    [ordered]@{ label = 'Open original'; style = 'primary'; command = [ordered]@{ type = 'cli'; program = 'pwsh'; args = @('-NoProfile', '-Command', "Start-Process '$urlForPs'") }; onSuccess = 'keep' }
    [ordered]@{ label = 'Reprocess (move back to AI-Inbox)'; style = 'default'; confirmMessage = 'Move this raindrop back to AI-Inbox and rerun the full analysis on the next tracker tick?'; command = [ordered]@{ type = 'cli'; program = 'pwsh'; args = @('-NoProfile', '-File', $ReprocessScript, '-RaindropId', $RaindropId) }; onSuccess = 'archive' }
    [ordered]@{ label = 'Dismiss'; style = 'default'; command = [ordered]@{ type = 'cli'; program = 'pwsh'; args = @('-NoProfile', '-Command', 'exit 0') }; onSuccess = 'archive' }
)

$titleCapped = if ($Title.Length -gt 120) { $Title.Substring(0, 120) } else { $Title }

$entry = [ordered]@{
    schemaVersion = '1'
    id            = "raindrop-$RaindropId-article"
    type          = 'raindrop-article'
    source        = $Source
    createdAt     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
    title         = $titleCapped
    subtitle      = $subtitle
    severity      = 'low'
    icon          = 'file-text'
    tags          = $entryTags
    content       = $content.ToArray()
    actions       = $actions
}

$json = $entry | ConvertTo-Json -Depth 40
$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
[System.IO.File]::WriteAllText($OutFile, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Output $OutFile
