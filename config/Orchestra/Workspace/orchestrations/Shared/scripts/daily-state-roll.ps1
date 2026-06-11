# daily-state-roll.ps1
#
# Reads the latest per-tracker `<category>:daily-summary` records from
# Zakira.Exchange and returns one normalized object the daily-morning-digest
# orchestration (B1) can compose into a single ActionView card.
#
# The convention is that every tracker writes one record per scheduler tick
# under the dedicated summary category named after itself:
#
#   <tracker-name>:daily-summary
#
# with a key formatted as the local date (YYYY-MM-DD). Trackers MAY also
# write an additional record at key "latest" pointing at the same payload,
# so consumers can read freshness without computing dates.
#
# Inputs (positional args):
#   $args[0]   absolute path to the Zakira SQLite database
#   $args[1]   comma-separated list of summary categories to read,
#              e.g. "my-prs-state:daily-summary,action-items-ledger:daily-summary"
#   $args[2]   ISO-8601 local date the digest is composing for (YYYY-MM-DD).
#              The script first tries this exact key, then falls back to "latest"
#              and finally to the most recent key surfaced by `list`.
#
# Output:
#   {
#     "rolledAt":  "<UTC iso>",
#     "digestDate": "<YYYY-MM-DD>",
#     "trackers": {
#       "<category>": {
#         "found":         true|false,
#         "key":           "<resolved key>",
#         "lastModified":  "<iso or null>",
#         "data":          <object or null>
#       }
#     }
#   }
#
# Missing categories are tolerated (found=false) so the digest renders even
# when individual trackers have not run yet.
#
# IMPORTANT: This script is invoked via positional `$args` (both by
# Orchestra `scriptFile:` steps and by direct `pwsh -File` callers).
# Do NOT add a `[CmdletBinding()] param()` block; PowerShell rejects
# untyped positional arguments when an empty param block is declared,
# which breaks the natural `$args[0..N]` contract.

$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'

$dbPath        = $args[0]
$categoriesRaw = $args[1]
$digestDate    = $args[2]

# Defensive: callers sometimes pass the entire resolve-digest-date
# JSON output instead of just the date string. Extract the
# digestDate field when we see JSON. (The orchestration engine
# does not let scriptFile args use expressions like
# `{{resolve-digest-date.output.digestDate}}`, so this defence makes
# the script tolerant of the natural caller pattern.)
if (-not [string]::IsNullOrWhiteSpace($digestDate) -and $digestDate.TrimStart().StartsWith('{')) {
    try {
        $parsed = ConvertFrom-Json -InputObject $digestDate -ErrorAction Stop
        if ($parsed.PSObject.Properties['digestDate']) {
            $digestDate = [string]$parsed.digestDate
        } elseif ($parsed.PSObject.Properties['summaryDate']) {
            $digestDate = [string]$parsed.summaryDate
        }
    } catch {
        # Leave as-is; the script's 'latest'/list fallback will handle
        # the bogus key.
    }
}

if ([string]::IsNullOrWhiteSpace($dbPath)) {
    throw 'daily-state-roll: dbPath argument is required.'
}
if ([string]::IsNullOrWhiteSpace($categoriesRaw)) {
    throw 'daily-state-roll: comma-separated categories argument is required.'
}
if ([string]::IsNullOrWhiteSpace($digestDate)) {
    $digestDate = (Get-Date).ToString('yyyy-MM-dd')
}

$categories = @($categoriesRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

function Get-DataJsonFromCliOutput {
    param([string[]]$Lines)
    if ($null -eq $Lines -or $Lines.Count -eq 0) { return $null }
    $dataIdx = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ([string]$Lines[$i] -match '^\s*Data:\s*') { $dataIdx = $i; break }
    }
    if ($dataIdx -lt 0) { return $null }
    $endIdx = $Lines.Count
    for ($j = $dataIdx + 1; $j -lt $Lines.Count; $j++) {
        if ([string]$Lines[$j] -match '^\s*(Author|Reason|Tags|Custom|Created|Last Modified):\s*') {
            $endIdx = $j; break
        }
    }
    $span = ($Lines[$dataIdx..($endIdx - 1)] | ForEach-Object { [string]$_ }) -join "`n"
    return ($span -replace '^\s*Data:\s*', '').Trim()
}

function Get-LastModifiedFromCliOutput {
    param([string[]]$Lines)
    if ($null -eq $Lines -or $Lines.Count -eq 0) { return $null }
    foreach ($line in $Lines) {
        if ([string]$line -match '^\s*Last Modified:\s*(.+)$') {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Get-LatestKeyFromList {
    # `list --category <category> --top 1` returns the most recently
    # modified entry first. The CLI output for `list` is
    #   <key>  <last-modified>
    # one row per entry, with a header line. We grab the first row's key.
    param([string]$Database, [string]$Category)
    $out = & dnx Zakira.Exchange --yes -- --db $Database list --category $Category --top 1 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    if ($null -eq $out -or $out.Count -eq 0) { return $null }
    # Strip header lines that include "Key" or column dividers and pick the
    # first content line. The CLI's exact list format may vary; the parser
    # below tolerates either tab-, double-space-, or whitespace-aligned
    # columns and falls back to the first token on the first non-header line.
    foreach ($line in @($out)) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -match '^\s*(Key|---|====)') { continue }
        $tokens = $text -split '\s{2,}|\t', 2
        if ($tokens.Count -eq 0) { continue }
        $candidate = $tokens[0].Trim()
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return $candidate
        }
    }
    return $null
}

$result = [ordered]@{
    rolledAt   = (Get-Date).ToUniversalTime().ToString('o')
    digestDate = $digestDate
    trackers   = [ordered]@{}
}

foreach ($category in $categories) {
    $found = $false
    $resolvedKey = $null
    $lastModified = $null
    $data = $null

    foreach ($candidateKey in @($digestDate, 'latest')) {
        $out = & dnx Zakira.Exchange --yes -- --db $dbPath get $category $candidateKey 2>&1
        if ($LASTEXITCODE -eq 0) {
            $dataJson = Get-DataJsonFromCliOutput -Lines $out
            $lastModified = Get-LastModifiedFromCliOutput -Lines $out
            if ($dataJson) {
                try { $data = ConvertFrom-Json -InputObject $dataJson -ErrorAction Stop } catch { $data = $null }
            }
            $found = $true
            $resolvedKey = $candidateKey
            break
        }
    }

    if (-not $found) {
        $fallbackKey = Get-LatestKeyFromList -Database $dbPath -Category $category
        if (-not [string]::IsNullOrWhiteSpace($fallbackKey)) {
            $out = & dnx Zakira.Exchange --yes -- --db $dbPath get $category $fallbackKey 2>&1
            if ($LASTEXITCODE -eq 0) {
                $dataJson = Get-DataJsonFromCliOutput -Lines $out
                $lastModified = Get-LastModifiedFromCliOutput -Lines $out
                if ($dataJson) {
                    try { $data = ConvertFrom-Json -InputObject $dataJson -ErrorAction Stop } catch { $data = $null }
                }
                $found = $true
                $resolvedKey = $fallbackKey
            }
        }
    }

    $result.trackers[$category] = [ordered]@{
        found        = $found
        key          = $resolvedKey
        lastModified = $lastModified
        data         = $data
    }
}

$result | ConvertTo-Json -Depth 100 -Compress
