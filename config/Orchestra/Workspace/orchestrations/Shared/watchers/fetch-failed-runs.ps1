#Requires -Version 7.0
<#
.SYNOPSIS
    Orchestra watcher fetcher (protocol v1): orchestration runs that failed since the last
    tick, grouped per orchestration, read from the local host's history API.

.DESCRIPTION
    Deterministic replacement for the `fetch-failed-runs` step of the retired
    `diagnose-auto-failed-orchestrations` scheduler orchestration. Uses the watcher cursor
    (`{ sinceUtc }` = newest completedAt seen) instead of a fixed 70-minute lookback, so a
    failure is reported once instead of being re-seen by overlapping windows. On the first
    tick (no cursor) it looks back `config.lookbackMinutes` (default 70).

    Each item groups the new failures of one orchestration and has exactly the shape
    `diagnose-orchestration-failures` reads from its `group` input:
      { id, orchestrationName, count, failedRunsJson }
    where `failedRunsJson` is a JSON-array string of
      { executionId, orchestrationName, runStatus, startedAt, completedAt, errorMessage }.
    The `id` is `<orchestrationName>|<newest executionId>`, so a fresh failure of an already
    diagnosed orchestration produces a new key (Orchestra's fifo dedup keys on it) while a
    re-observation of the same runs does not.

    config (fetch.config):
      serverUrl              "http://127.0.0.1:5100"   (the host this watcher runs inside)
      lookbackMinutes        70                        (first tick only)
      excludeOrchestrations  [ names never to diagnose - e.g. the diagnoser itself ]
#>
$ErrorActionPreference = 'Stop'

$request = [Console]::In.ReadToEnd() | ConvertFrom-Json -Depth 20
$config = $request.config
if ($null -eq $config -or [string]::IsNullOrWhiteSpace([string]$config.serverUrl)) { throw 'fetch.config.serverUrl is required.' }

$serverUrl = ([string]$config.serverUrl).TrimEnd('/')
$lookbackMinutes = if ($config.PSObject.Properties['lookbackMinutes'] -and $config.lookbackMinutes) { [int]$config.lookbackMinutes } else { 70 }
$exclude = @()
if ($config.PSObject.Properties['excludeOrchestrations'] -and $null -ne $config.excludeOrchestrations) {
    $exclude = @($config.excludeOrchestrations | ForEach-Object { ([string]$_).ToLowerInvariant() })
}

function ConvertTo-UtcDateTime {
    # ConvertFrom-Json / Invoke-RestMethod turn ISO-8601 strings into [datetime] objects; casting
    # those back to [string] drops the zone and re-parsing shifts them by the local offset. Handle
    # every shape explicitly and always come out with a UTC [datetime].
    param($value)
    if ($null -eq $value) { return $null }
    if ($value -is [datetimeoffset]) { return ([datetimeoffset]$value).UtcDateTime }
    if ($value -is [datetime]) {
        $d = [datetime]$value
        switch ($d.Kind) {
            'Utc' { return $d }
            'Local' { return $d.ToUniversalTime() }
            default { return [datetime]::SpecifyKind($d, 'Utc') }
        }
    }
    $s = [string]$value
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    try {
        return [datetimeoffset]::Parse($s, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal).UtcDateTime
    } catch { return $null }
}

function ConvertTo-IsoUtcString {
    param($value)
    $d = ConvertTo-UtcDateTime $value
    if ($null -eq $d) { return '' }
    return $d.ToString('o')
}

$sinceUtc = $null
if ($null -ne $request.cursor -and $request.cursor.PSObject.Properties['sinceUtc']) {
    $sinceUtc = ConvertTo-UtcDateTime $request.cursor.sinceUtc
}
if ($null -eq $sinceUtc) { $sinceUtc = (Get-Date).ToUniversalTime().AddMinutes(-1 * $lookbackMinutes) }

$resp = Invoke-RestMethod -Uri "$serverUrl/api/history?statuses=failed&limit=200" -Method Get -TimeoutSec 30

$runs = [System.Collections.Generic.List[object]]::new()
$newest = $sinceUtc
foreach ($r in @($resp.runs)) {
    if ($null -eq $r) { continue }
    $status = [string]$r.status
    if (-not $status.ToLowerInvariant().Contains('fail')) { continue }
    $name = [string]$r.orchestrationName
    if ([string]::IsNullOrWhiteSpace($name) -or $exclude -contains $name.ToLowerInvariant()) { continue }

    $ts = ConvertTo-UtcDateTime $r.completedAt
    if ($null -eq $ts) { $ts = ConvertTo-UtcDateTime $r.startedAt }
    # Strictly newer than the cursor: a run completing in the very same tick as the cursor
    # timestamp is caught by the dedup key, not by re-reading it here.
    if ($null -ne $ts -and $ts -le $sinceUtc) { continue }
    if ($null -ne $ts -and $ts -gt $newest) { $newest = $ts }

    [void]$runs.Add([pscustomobject]@{
        executionId       = [string]$r.runId
        orchestrationName = $name
        runStatus         = $status
        startedAt         = ConvertTo-IsoUtcString $r.startedAt
        completedAt       = ConvertTo-IsoUtcString $r.completedAt
        errorMessage      = [string]$r.errorMessage
    })
}

function ConvertTo-JsonArrayString {
    # Always a single-level JSON array string for 0/1/N elements (ConvertTo-Json -AsArray double-wraps).
    param($Items)
    $arr = @($Items)
    if ($arr.Count -eq 0) { return '[]' }
    return '[' + (($arr | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 50 -Compress }) -join ',') + ']'
}

$items = [System.Collections.Generic.List[object]]::new()
foreach ($grp in ($runs | Group-Object -Property orchestrationName)) {
    $groupRuns = @($grp.Group | Sort-Object { [string]$_.completedAt }) # ISO-8601 UTC strings sort lexically
    $newestRun = $groupRuns[-1]
    [void]$items.Add([ordered]@{
        id                = "$($grp.Name)|$($newestRun.executionId)"
        orchestrationName = [string]$grp.Name
        count             = $groupRuns.Count
        failedRunsJson    = (ConvertTo-JsonArrayString -Items $groupRuns)
    })
}

$response = [ordered]@{
    protocolVersion = '1'
    items           = $items.ToArray()
    cursor          = [ordered]@{ sinceUtc = $newest.ToString('o') }
    diagnostics     = [ordered]@{ message = "$($runs.Count) failed run(s) in $($items.Count) orchestration(s) since $($sinceUtc.ToString('o'))" }
}
[Console]::Out.Write((ConvertTo-Json -InputObject $response -Depth 100 -Compress))
exit 0
