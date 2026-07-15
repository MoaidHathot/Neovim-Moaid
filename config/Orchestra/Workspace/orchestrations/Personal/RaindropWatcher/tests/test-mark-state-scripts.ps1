#!/usr/bin/env pwsh
# Integration test for the deterministic state-write Script steps in
# raindrop-processor.yaml (mark-processing, mark-completed) and the failure hook
# (tools/scripts/hook-mark-failed.ps1).
#
# WHY THIS EXISTS
# ---------------
# These steps replaced LLM Prompt steps that timed out. They write the watcher
# state record via the Zakira.Exchange CLI. The subtle failure mode this test
# guards against: invoking the CLI through the `dnx` shim (dnx.cmd -> "dotnet.exe
# dnx %*") strips the double-quotes out of the JSON --data payload (the batch %*
# re-expansion mangles them), so the record is stored as unparseable `{k:v}` text
# instead of `{"k":"v"}` JSON. raindrop-tracker's load-state parser then fails to
# read it back and treats the item as brand-new -> duplicate dispatch, lost
# attempts/dead-letter tracking. The steps therefore invoke the CLI via
# `dotnet dnx` (native exe + Standard arg passing) which keeps the JSON intact.
#
# This test runs the ACTUAL script bodies extracted from the YAML (not copies),
# against a throwaway SQLite db, and asserts every stored record round-trips as
# valid JSON through the exact load-state parser, with pre-existing fields
# preserved across the merge.
#
# Exit code 0 = all assertions passed; 1 = failure.

param(
    [string]$ProcessorYaml = (Join-Path (Split-Path $PSScriptRoot -Parent) 'raindrop-processor.yaml'),
    [string]$HookScript    = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/scripts/hook-mark-failed.ps1'),
    [string]$RepairScript  = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/scripts/repair-corrupted-state.ps1')
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
# Match the scripts under test: decode the CLI's UTF-8 output as UTF-8 so the harness
# reads back non-ASCII fields the same way the (fixed) scripts do.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:failures = 0
$script:passed = 0
function Assert([bool]$cond, [string]$msg) {
    if ($cond) { $script:passed++; Write-Host "  PASS  $msg" -ForegroundColor Green }
    else       { $script:failures++; Write-Host "  FAIL  $msg" -ForegroundColor Red }
}

$dotnet = (Get-Command dotnet -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$category = 'raindrop-watcher-state'

# --- Extract a `script: |` block for a named step out of the YAML ------------
function Get-StepScript {
    param([string]$YamlPath, [string]$StepName)
    $lines = Get-Content -LiteralPath $YamlPath
    $inStep = $false; $scriptIndent = -1; $collecting = $false
    $buf = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        if (-not $inStep) {
            if ($line -match "^\s*-\s*name:\s*$([regex]::Escape($StepName))\s*$") { $inStep = $true }
            continue
        }
        if (-not $collecting) {
            if ($line -match '^(\s*)script:\s*\|') { $scriptIndent = $Matches[1].Length; $collecting = $true }
            elseif ($line -match "^\s*-\s*name:\s*\S") { break }  # next step, script not found
            continue
        }
        # collecting block content: stop when a non-blank line dedents to <= script:
        if ($line.Trim().Length -gt 0) {
            $indent = ($line -replace '\S.*$','').Length
            if ($indent -le $scriptIndent) { break }
        }
        $buf.Add($line)
    }
    if ($buf.Count -eq 0) { throw "Could not extract script for step '$StepName' from $YamlPath" }
    # Strip the common leading indent (based on the first non-blank line).
    $first = ($buf | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
    $base = ($first -replace '\S.*$','').Length
    return (($buf | ForEach-Object { if ($_.Length -ge $base) { $_.Substring($base) } else { $_.TrimStart() } }) -join "`n")
}

# --- Read a record back through the exact load-state parser ------------------
function Get-Record {
    param([string]$Db, [string]$Key)
    $out = & $dotnet dnx Zakira.Exchange --yes -- --db $Db get $category $Key 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    $lines = @($out)
    $dataIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ([string]$lines[$i] -match '^\s*Data:\s*') { $dataIdx = $i; break } }
    if ($dataIdx -lt 0) { return $null }
    $endIdx = $lines.Count
    for ($j = $dataIdx + 1; $j -lt $lines.Count; $j++) {
        if ([string]$lines[$j] -match '^\s*(Author|Reason|Tags|Custom|Created|Last Modified):\s*') { $endIdx = $j; break }
    }
    $span = ($lines[$dataIdx..($endIdx - 1)] | ForEach-Object { [string]$_ }) -join "`n"
    $json = ($span -replace '^\s*Data:\s*', '').Trim()
    $rawStartsQuoted = [bool]($json -match '^\{\s*"')
    try { $obj = $json | ConvertFrom-Json -DateKind String -ErrorAction Stop }
    catch { return [pscustomobject]@{ Parsed = $false; StartsQuoted = $rawStartsQuoted; Raw = $json; Obj = $null } }
    return [pscustomobject]@{ Parsed = $true; StartsQuoted = $rawStartsQuoted; Raw = $json; Obj = $obj }
}

$markProcessing = Get-StepScript -YamlPath $ProcessorYaml -StepName 'mark-processing'
$markCompleted  = Get-StepScript -YamlPath $ProcessorYaml -StepName 'mark-completed'
$sbProcessing = [scriptblock]::Create($markProcessing)
$sbCompleted  = [scriptblock]::Create($markCompleted)

$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("raindrop-marktest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$db = Join-Path $tmpRoot 'zakira.db'

try {
    # === Scenario 1: normal lifecycle (queued -> processing -> completed) =====
    Write-Host "`n[1] Lifecycle: seed queued (MCP-style parseable) -> mark-processing -> mark-completed" -ForegroundColor Cyan
    $rid = '900000001'
    $queuedAt    = '2026-07-14T22:00:00.000+03:00'
    $firstSeenAt = '2026-07-10T09:15:00.000+03:00'
    $addedAt     = '2026-07-14T20:53:46.539Z'
    $noteHash    = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    $seed = [ordered]@{
        raindropId = $rid; url = 'https://example.com/x'; title = 'Héllo, world: a test'
        status = 'queued'; attempts = 0; noteHash = $noteHash
        queuedAt = $queuedAt; addedAt = $addedAt; firstSeenAt = $firstSeenAt
        tags = @('ai','video'); reason = 'new'
    } | ConvertTo-Json -Compress
    & $dotnet dnx Zakira.Exchange --yes -- --db $db create $category $rid --data $seed --author raindrop-watcher --reason 'seed queued' --tags queued 2>&1 | Out-Null
    $seedRec = Get-Record -Db $db -Key $rid
    Assert ($seedRec.Parsed -and $seedRec.StartsQuoted) "seed record is valid quoted JSON"

    # mark-processing args: rid,url,title,noteHash,tagsJson,addedAt,priorAttempts,runId,db,category
    & $sbProcessing $rid 'https://example.com/x' 'Héllo, world: a test' $noteHash '["ai","video"]' $addedAt '0' 'run-abc123' $db $category | Out-Null
    $rp = Get-Record -Db $db -Key $rid
    Assert ($rp.Parsed) "after mark-processing: record parses as JSON"
    Assert ($rp.StartsQuoted) "after mark-processing: stored Data is quoted JSON (not mangled)"
    Assert ($rp.Obj.status -eq 'processing') "after mark-processing: status=processing (got '$($rp.Obj.status)')"
    Assert ([int]$rp.Obj.attempts -eq 1) "after mark-processing: attempts=1 (got '$($rp.Obj.attempts)')"
    Assert ($rp.Obj.orchestrationRunId -eq 'run-abc123') "after mark-processing: orchestrationRunId set"
    Assert (-not [string]::IsNullOrWhiteSpace($rp.Obj.startedAt)) "after mark-processing: startedAt set"
    Assert ($rp.Obj.queuedAt -eq $queuedAt) "after mark-processing: queuedAt PRESERVED exactly (got '$($rp.Obj.queuedAt)')"
    Assert ($rp.Obj.firstSeenAt -eq $firstSeenAt) "after mark-processing: firstSeenAt PRESERVED exactly (got '$($rp.Obj.firstSeenAt)')"
    Assert ($rp.Obj.noteHash -eq $noteHash) "after mark-processing: noteHash PRESERVED (change-detection key)"
    Assert ($rp.Obj.addedAt -eq $addedAt) "after mark-processing: addedAt PRESERVED exactly"
    Assert ($rp.Obj.title -eq $seedRec.Obj.title) "after mark-processing: title PRESERVED across merge (round-trip stable, got '$($rp.Obj.title)')"
    Assert ($rp.Obj.title.Contains([char]233)) "after mark-processing: non-ASCII char (e-acute) survived read->merge->write"

    # mark-completed args: rid,noteHash,dispatchJson,db,category
    $dispatch = '{"processor":"raindrop-video-generic-processor","executionId":"child-777","status":"Completed"}'
    & $sbCompleted $rid $noteHash $dispatch $db $category | Out-Null
    $rc = Get-Record -Db $db -Key $rid
    Assert ($rc.Parsed) "after mark-completed: record parses as JSON"
    Assert ($rc.StartsQuoted) "after mark-completed: stored Data is quoted JSON (not mangled)"
    Assert ($rc.Obj.status -eq 'completed') "after mark-completed: status=completed (got '$($rc.Obj.status)')"
    Assert (-not [string]::IsNullOrWhiteSpace($rc.Obj.completedAt)) "after mark-completed: completedAt set"
    Assert ($rc.Obj.lastProcessor -eq 'raindrop-video-generic-processor') "after mark-completed: lastProcessor parsed from dispatch"
    Assert ($rc.Obj.lastChildExecutionId -eq 'child-777') "after mark-completed: lastChildExecutionId parsed from dispatch"
    Assert ($rc.Obj.queuedAt -eq $queuedAt) "after mark-completed: queuedAt STILL preserved"
    Assert ($rc.Obj.firstSeenAt -eq $firstSeenAt) "after mark-completed: firstSeenAt STILL preserved"
    Assert ([int]$rc.Obj.attempts -eq 1) "after mark-completed: attempts STILL 1 (preserved)"

    # === Scenario 2: create-fallback (record missing) ========================
    Write-Host "`n[2] Create-fallback: mark-processing when no record exists yet" -ForegroundColor Cyan
    $rid2 = '900000002'
    & $sbProcessing $rid2 'https://example.com/y' 'Second' 'abc123hash' '[]' '2026-07-14T20:00:00.000Z' '0' 'run-def456' $db $category | Out-Null
    $rp2 = Get-Record -Db $db -Key $rid2
    Assert ($rp2 -and $rp2.Parsed) "create-fallback: record created and parses"
    Assert ($rp2.StartsQuoted) "create-fallback: stored Data is quoted JSON"
    Assert ($rp2.Obj.status -eq 'processing') "create-fallback: status=processing"
    Assert ($rp2.Obj.raindropId -eq $rid2) "create-fallback: raindropId seeded"

    # === Scenario 3: failure hook uses the quote-safe invocation =============
    # Static check (running the full hook would also publish to ActionView -- a
    # side effect we don't want in a unit test). The hook's zakira write is the
    # same `dotnet dnx ... edit --data <json>` pattern exercised live in [1]/[2],
    # and its `edit --category/--key` form is verified to round-trip as JSON.
    Write-Host "`n[3] Failure hook: quote-safe invocation present and file parses" -ForegroundColor Cyan
    $hookText = Get-Content -LiteralPath $HookScript -Raw
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($hookText, [ref]$null, [ref]$parseErrors)
    Assert (($parseErrors | Measure-Object).Count -eq 0) "hook: script parses with no syntax errors"
    Assert ($hookText -match '&\s*\$dotnet\s+dnx\s+Zakira\.Exchange') "hook: writes via quote-safe 'dotnet dnx' (the fix)"
    Assert ($hookText -notmatch '&\s*dnx\s+Zakira\.Exchange') "hook: no bare '& dnx Zakira.Exchange' (the quote-stripping bug)"
    Assert ($hookText -match "PSNativeCommandArgumentPassing\s*=\s*'Standard'") "hook: Standard native arg passing set"

    # === Scenario 4: failure hook end-to-end, merge preserves attempts =======
    # Runs the REAL hook. Its zakira writes go through `& $dotnet dnx` (full path,
    # unaffected by PATH); its ActionView calls use the bare `dnx` name, which we
    # shadow with a no-op shim on PATH so nothing is published to ActionView.
    Write-Host "`n[4] Failure hook end-to-end: get->merge preserves attempts (ActionView sandboxed)" -ForegroundColor Cyan
    $rid4 = '900000004'
    $seed4 = [ordered]@{
        raindropId = $rid4; url = 'https://example.com/w'; title = 'Fourth: café'
        status = 'processing'; attempts = 2; queuedAt = $queuedAt
        startedAt = '2026-07-14T22:05:00.000+03:00'; noteHash = 'deadbeef'; firstSeenAt = $firstSeenAt
    } | ConvertTo-Json -Compress
    New-Item -ItemType Directory -Path (Join-Path $tmpRoot 'orchestra') -Force | Out-Null
    $hookDb = Join-Path $tmpRoot 'orchestra/zakira.db'
    & $dotnet dnx Zakira.Exchange --yes -- --db $hookDb create $category $rid4 --data $seed4 --tags processing 2>&1 | Out-Null

    $shimDir = Join-Path $tmpRoot 'shim'
    New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $shimDir 'dnx.cmd') -Value "@echo off`r`nexit /b 0" -Encoding ascii
    $savedPath = $env:PATH; $savedXdg = $env:XDG_CONFIG_HOME
    try {
        $env:XDG_CONFIG_HOME = $tmpRoot          # hook derives db = $XDG_CONFIG_HOME/orchestra/zakira.db
        $env:PATH = "$shimDir;$env:PATH"
        $hookPayload = '{"steps":[{"name":"dispatch-processor","errorMessage":"boom, with comma"}]}'
        $hookPayload | & pwsh -NoProfile -File $HookScript $rid4 'https://example.com/w' 'Fourth: café' *> $null
    } finally {
        $env:PATH = $savedPath
        if ($null -ne $savedXdg) { $env:XDG_CONFIG_HOME = $savedXdg } else { Remove-Item Env:\XDG_CONFIG_HOME -ErrorAction Ignore }
    }
    $hr = Get-Record -Db $hookDb -Key $rid4
    Assert ($hr -and $hr.Parsed) "hook e2e: failed record parses as valid JSON (was the corruption bug)"
    Assert ($hr.StartsQuoted) "hook e2e: stored Data is quoted JSON (not mangled {k:v})"
    Assert ($hr.Obj.status -eq 'failed') "hook e2e: status=failed"
    Assert ([int]$hr.Obj.attempts -eq 2) "hook e2e: attempts PRESERVED (=2) so dead-lettering can fire (got '$($hr.Obj.attempts)')"
    Assert ($hr.Obj.queuedAt -eq $queuedAt) "hook e2e: queuedAt preserved across merge"
    Assert ($hr.Obj.noteHash -eq 'deadbeef') "hook e2e: noteHash (change-detection key) preserved"
    Assert ($hr.Obj.firstSeenAt -eq $firstSeenAt) "hook e2e: firstSeenAt preserved"
    Assert ($hr.Obj.failedStep -eq 'dispatch-processor') "hook e2e: failedStep recorded from stdin payload"
    Assert ($hr.Obj.lastError -eq 'boom, with comma') "hook e2e: lastError recorded (value with comma intact)"

    # === Scenario 5: repair-corrupted-state heals legacy stripped-quote records
    # Seed a genuinely corrupted record via the bare `dnx` shim (which strips the
    # JSON quotes, reproducing the original bug), then run the repair tool.
    Write-Host "`n[5] Repair tool: heals a legacy corrupted (stripped-quote) record" -ForegroundColor Cyan
    $rid5 = '900000005'
    $corruptSeed = '{"raindropId":"900000005","status":"failed","failedStep":"mark-completed","failedAt":"2026-07-13T21:24:52.2632770Z","url":"https://www.youtube.com/watch?v=abc123","lastError":"Step timed out after 120 seconds."}'
    # Force legacy native arg passing so the bare `dnx` shim strips the JSON quotes,
    # reproducing exactly how the pre-fix hook corrupted records in production.
    $savedPass = $PSNativeCommandArgumentPassing
    $PSNativeCommandArgumentPassing = 'Legacy'
    & dnx Zakira.Exchange --yes -- --db $db create $category $rid5 --data $corruptSeed --tags failed 2>&1 | Out-Null
    $PSNativeCommandArgumentPassing = $savedPass
    $before = Get-Record -Db $db -Key $rid5
    Assert (-not $before.Parsed) "repair: seeded record is corrupted/unparseable to begin with"

    & pwsh -NoProfile -File $RepairScript -Database $db -NoBackup *> $null
    $after = Get-Record -Db $db -Key $rid5
    Assert ($after -and $after.Parsed) "repair: record now parses as valid JSON"
    Assert ($after.StartsQuoted) "repair: stored Data is quoted JSON"
    Assert ($after.Obj.status -eq 'failed') "repair: status recovered (failed)"
    Assert ($after.Obj.raindropId -eq $rid5) "repair: raindropId = key (authoritative)"
    Assert ($after.Obj.failedStep -eq 'mark-completed') "repair: failedStep recovered"
    Assert ($after.Obj.url -eq 'https://www.youtube.com/watch?v=abc123') "repair: url (with colons) recovered intact"
    Assert ($after.Obj.repairedFrom -eq 'corrupted-cli-write') "repair: tagged with repairedFrom marker"

    # idempotent: a valid record from scenario 1 must be left untouched
    $reprocRunAgain = Get-Record -Db $db -Key '900000001'
    & pwsh -NoProfile -File $RepairScript -Database $db -NoBackup *> $null
    $stillOk = Get-Record -Db $db -Key '900000001'
    Assert ($stillOk.Parsed -and $stillOk.Obj.status -eq $reprocRunAgain.Obj.status) "repair: idempotent -- already-valid record unchanged on re-run"
}
finally {
    if ($env:XDG_CONFIG_HOME -eq $tmpRoot) { Remove-Item Env:\XDG_CONFIG_HOME -ErrorAction Ignore }
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction Ignore
}

Write-Host "`n==== $($script:passed) passed, $($script:failures) failed ====" -ForegroundColor $(if ($script:failures) { 'Red' } else { 'Green' })
if ($script:failures -gt 0) { exit 1 } else { exit 0 }
