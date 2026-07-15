#!/usr/bin/env pwsh
<#
.SYNOPSIS
    One-time repair for raindrop-watcher-state records that were stored with their
    JSON double-quotes stripped (the `dnx`-shim quote-stripping bug in the pre-fix
    failure hook / state writes).

.DESCRIPTION
    Such records were persisted as unparseable `{key:value,...}` text instead of
    `{"key":"value",...}` JSON, so raindrop-tracker's load-state can't read them and
    treats the raindrop as brand-new (re-dispatching it and losing failure context).

    This script scans every record in the category, and for each one whose Data is NOT
    valid JSON it best-effort-recovers the known fields (status, raindropId, url,
    failedStep, failedAt, lastError, ...) from the lossy text and rewrites the record as
    clean JSON via the quote-safe `dotnet dnx` invocation. Records that are already valid
    JSON are left untouched, so the script is idempotent and safe to re-run.

    Best-effort caveats: values are split at known-key boundaries, so a free-text value
    that itself contains ",<knownKey>:" can be truncated, and non-ASCII text that was
    already mojibake'd to "????" in the corrupted store cannot be recovered. The fields
    that matter for scheduling (status, raindropId) are always recovered correctly.

.PARAMETER Database
    Path to zakira.db. Defaults to $XDG_CONFIG_HOME/orchestra/zakira.db.

.PARAMETER Category
    Memory category to scan. Defaults to 'raindrop-watcher-state'.

.PARAMETER DryRun
    Report what would be repaired without writing anything (implies -NoBackup).

.PARAMETER NoBackup
    Skip copying the database to a timestamped .bak before repairing.
#>
[CmdletBinding()]
param(
    [string]$Database,
    [string]$Category = 'raindrop-watcher-state',
    [switch]$DryRun,
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if (-not $Database) {
    if (-not $env:XDG_CONFIG_HOME) { throw "repair-corrupted-state: -Database not given and XDG_CONFIG_HOME is not set." }
    $Database = Join-Path $env:XDG_CONFIG_HOME 'orchestra/zakira.db'
}
if (-not (Test-Path -LiteralPath $Database)) { throw "repair-corrupted-state: database not found: $Database" }

$dotnet = (Get-Command dotnet -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source

# Known state fields, used as split boundaries when reconstructing lossy `{k:v}` text.
$knownKeys = @(
    'raindropId','url','title','note','status','previousStatus','attempts',
    'queuedAt','startedAt','completedAt','failedAt','failedStep','lastError',
    'noteHash','addedAt','firstSeenAt','reason','summary',
    'orchestrationRunId','lastProcessor','lastChildExecutionId',
    'previousFailedAt','previousLastError','previousFailedStep'
)
$numericKeys = @('attempts')

function Get-FieldFromCliOutput {
    param([string[]]$Lines, [string]$Field)
    foreach ($ln in $Lines) {
        if ([string]$ln -match "^\s*$([regex]::Escape($Field)):\s*(.*)$") { return $Matches[1].TrimEnd() }
    }
    return $null
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

function ConvertFrom-LossyData {
    param([string]$Text, [string]$Key)
    $inner = $Text.Trim()
    $inner = $inner -replace '^\{', '' -replace '\}$', ''
    $alt = ($knownKeys | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $rx  = [regex]::new("(?:^|,)($alt):(.*?)(?=,(?:$alt):|`$)")
    $out = [ordered]@{}
    foreach ($m in $rx.Matches($inner)) {
        $k = $m.Groups[1].Value
        $v = $m.Groups[2].Value
        if ($numericKeys -contains $k) {
            $n = 0; if ([int]::TryParse($v, [ref]$n)) { $out[$k] = $n } else { $out[$k] = $v }
        } else { $out[$k] = $v }
    }
    $out['raindropId'] = $Key            # authoritative: the record key is the id
    return $out
}

# --- Backup ------------------------------------------------------------------
if (-not $DryRun -and -not $NoBackup) {
    $bak = "$Database.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    Copy-Item -LiteralPath $Database -Destination $bak -Force
    Write-Host "Backup written: $bak" -ForegroundColor DarkGray
}

# --- Scan --------------------------------------------------------------------
$listOut = & $dotnet dnx Zakira.Exchange --yes -- --db $Database list --cat $Category -n 100000 2>&1
if ($LASTEXITCODE -ne 0) { throw "repair-corrupted-state: list failed: $($listOut -join ' ')" }

$keys = New-Object System.Collections.Generic.List[string]
foreach ($ln in @($listOut)) {
    if ([string]$ln -match "^\s*\[$([regex]::Escape($Category))\]\s+(\S+)\s") { $keys.Add($Matches[1]) }
}

Write-Host "Scanning $($keys.Count) record(s) in [$Category] ($Database)..." -ForegroundColor Cyan
$scanned = 0; $corrupted = 0; $repaired = 0; $failed = 0
foreach ($key in $keys) {
    $scanned++
    $out = & $dotnet dnx Zakira.Exchange --yes -- --db $Database get $Category $key 2>&1
    if ($LASTEXITCODE -ne 0) { continue }
    $lines = @($out)
    $json = Get-DataJsonFromCliOutput -Lines $lines
    if ([string]::IsNullOrWhiteSpace($json)) { continue }

    $ok = $true
    try { [void]($json | ConvertFrom-Json -DateKind String -ErrorAction Stop) } catch { $ok = $false }
    if ($ok) { continue }        # already valid JSON -> leave untouched (idempotent)

    $corrupted++
    $recovered = ConvertFrom-LossyData -Text $json -Key $key
    $recovered['repairedAt']   = (Get-Date).ToUniversalTime().ToString('o')
    $recovered['repairedFrom'] = 'corrupted-cli-write'
    $status = if ($recovered.Contains('status')) { $recovered['status'] } else { '?' }
    $tags = Get-FieldFromCliOutput -Lines $lines -Field 'Tags'
    if ([string]::IsNullOrWhiteSpace($tags)) { $tags = $status }

    if ($DryRun) {
        Write-Host ("  [dry-run] {0}  status={1}  -> would rewrite {2} field(s), tags='{3}'" -f $key, $status, $recovered.Count, $tags) -ForegroundColor Yellow
        continue
    }

    $payload = $recovered | ConvertTo-Json -Depth 50 -Compress
    $reason  = 'repair: rewrite corrupted CLI-written record as valid JSON'
    $o1 = & $dotnet dnx Zakira.Exchange --yes -- --db $Database edit $Category $key --data $payload --author raindrop-watcher-repair --reason $reason --tags $tags 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "  repair FAILED for ${key}: $($o1 -join ' ')"
        $failed++
        continue
    }
    # verify it now parses
    $verify = & $dotnet dnx Zakira.Exchange --yes -- --db $Database get $Category $key 2>&1
    $vjson = Get-DataJsonFromCliOutput -Lines @($verify)
    $vok = $true; try { [void]($vjson | ConvertFrom-Json -DateKind String -ErrorAction Stop) } catch { $vok = $false }
    if ($vok) { $repaired++; Write-Host ("  repaired {0}  status={1}" -f $key, $status) -ForegroundColor Green }
    else { $failed++; Write-Warning "  repair wrote ${key} but it still does not parse" }
}

Write-Host ""
Write-Host ("Scanned={0}  Corrupted={1}  Repaired={2}  Failed={3}{4}" -f `
    $scanned, $corrupted, $repaired, $failed, $(if ($DryRun) { '  (dry-run, nothing written)' } else { '' })) `
    -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
if ($failed -gt 0) { exit 1 } else { exit 0 }
