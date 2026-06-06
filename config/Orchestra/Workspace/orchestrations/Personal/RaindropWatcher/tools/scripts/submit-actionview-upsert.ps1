#!/usr/bin/env pwsh
# Idempotent ActionView submit:
#   1. Reads the entry JSON file
#   2. Extracts the `id` field
#   3. Calls `dnx ActionView.Cli delete <id> --force` (ignored if missing)
#   4. Calls `dnx ActionView.Cli add --file <EntryFile>` and forwards stdout
#
# Use this in place of a direct `add` whenever the entry has a deterministic
# id (e.g., "raindrop-<raindropId>-recipe", "raindrop-error-<raindropId>",
# "raindrop-dead-letter-<raindropId>"). It guarantees: at most one entry per
# (type, id) ever lives in the ActionView inbox, no matter how many times
# the orchestration is retried.
#
# Usage:
#   submit-actionview-upsert.ps1 -EntryFile <path-to-entry.json>
#
# Stdout: forwards the output of `ActionView.Cli add` so existing callers
# that scrape it (e.g., to extract a published id) keep working.
#
# Exit codes:
#   0  - add succeeded (delete may or may not have removed a prior entry)
#   1  - bad arguments / entry file unreadable / entry id missing
#   2+ - non-zero ActionView add exit code (passed through)

param(
    [Parameter(Mandatory=$true)] [string]$EntryFile
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $EntryFile)) {
    Write-Error "submit-actionview-upsert: entry file not found: $EntryFile"
    exit 1
}

try {
    $entry = Get-Content -LiteralPath $EntryFile -Raw | ConvertFrom-Json
} catch {
    Write-Error "submit-actionview-upsert: entry file is not valid JSON: $($_.Exception.Message)"
    exit 1
}

$entryId = $entry.id
if ([string]::IsNullOrWhiteSpace($entryId)) {
    Write-Error "submit-actionview-upsert: entry JSON is missing the `id` field (this script requires a stable id for upsert semantics; use `dnx ActionView.Cli add --file ...` directly when you want an auto-generated id)"
    exit 1
}

# 1) Try to delete any prior entry with the same id. Failure is expected on
#    the first ever run (no such entry yet), so we swallow it.
& dnx ActionView.Cli --yes -- delete $entryId --force 2>$null | Out-Null
# Note: $LASTEXITCODE is non-zero here when the entry doesn't exist; that is
# fine, we treat it as a no-op. Do NOT propagate it.

# 2) Add the fresh entry. THIS exit code is the one that matters.
& dnx ActionView.Cli --yes -- add --file $EntryFile
exit $LASTEXITCODE
