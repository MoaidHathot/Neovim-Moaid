#!/usr/bin/env pwsh
# Regression tests for the `verify-dispatch` step in raindrop-processor.yaml.
#
# Background: `invoke_orchestration` (sync) returns status="Failed" without
# throwing, so the LLM `dispatch-processor` step succeeds even when the child
# failed. `verify-dispatch` is the deterministic gate that re-derives the child
# status and throws unless it can positively confirm success.
#
# It used to read the status with four narrow regexes, all of which assumed a
# JSON-ish shape. Run 51af7212aa5b was failed by that gate on the sentence
#
#   Child orchestration raindrop-video-generic-processor invoked synchronously;
#   executionId 4e8aefe6c1f3 completed with status "succeeded". Returning the
#   result envelope verbatim.
#
# even though child 4e8aefe6c1f3 had SUCCEEDED -- a false negative that pushed a
# finished raindrop back into AI-Inbox for reprocessing. Four more runs on
# 2026-07-20/21 hit the same shape.
#
# These tests extract the *shipped* script out of the YAML (not a copy) and run
# it against each envelope shape, asserting both directions: real successes must
# pass, and anything not positively confirmed must still fail safe.
#
# Exit 0 = all pass; 1 = failure.

param(
    [string]$Orchestration = (Join-Path (Split-Path $PSScriptRoot -Parent) 'raindrop-processor.yaml')
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:pass = 0; $script:fail = 0
function Assert([bool]$c, [string]$m) {
    if ($c) { $script:pass++; Write-Host "  PASS  $m" -ForegroundColor Green }
    else    { $script:fail++; Write-Host "  FAIL  $m" -ForegroundColor Red }
}

# --- Extract the verify-dispatch script block from the orchestration ----------
# Deliberately textual: this test must exercise the exact text that the engine
# runs, so it cannot round-trip through a YAML library that might normalise it.
function Get-StepScript {
    param([string]$Path, [string]$StepName)

    $lines = [System.IO.File]::ReadAllLines($Path)
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^  - name:\s+$([regex]::Escape($StepName))\s*$") { $start = $i; break }
    }
    if ($start -lt 0) { throw "step '$StepName' not found in $Path" }

    $scriptAt = -1
    for ($i = $start; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^  - name:\s' -and $i -gt $start) { break }
        if ($lines[$i] -match '^    script:\s*\|\s*$') { $scriptAt = $i; break }
    }
    if ($scriptAt -lt 0) { throw "step '$StepName' has no literal 'script: |' block" }

    $body = New-Object System.Collections.Generic.List[string]
    for ($i = $scriptAt + 1; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.Trim().Length -eq 0) { $body.Add(''); continue }
        if ($l -notmatch '^      ') { break }   # de-dent ends the literal block
        $body.Add($l.Substring(6))
    }
    return ($body -join "`n").TrimEnd()
}

$scriptText = Get-StepScript -Path $Orchestration -StepName 'verify-dispatch'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("verify-dispatch-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$stepFile = Join-Path $tmp 'verify-dispatch.ps1'
[System.IO.File]::WriteAllText($stepFile, $scriptText, (New-Object System.Text.UTF8Encoding($false)))

# Run the step exactly like the engine does: single positional arg = the
# dispatch-processor output. The envelope travels via a file and the result
# comes back as JSON, because passing envelopes containing quotes/newlines on a
# child process command line mangles them, and PowerShell's error renderer wraps
# and truncates long messages on stderr -- both would make this suite lie.
$runnerFile = Join-Path $tmp 'runner.ps1'
[System.IO.File]::WriteAllText($runnerFile, @'
param([string]$StepFile, [string]$EnvelopeFile, [string]$ResultFile)
$envelope = [System.IO.File]::ReadAllText($EnvelopeFile)
$res = [ordered]@{ threw = $false; output = ''; error = '' }
try {
    $out = & $StepFile $envelope
    $res.output = ($out | Out-String)
} catch {
    $res.threw = $true
    $res.error = [string]$_.Exception.Message
}
[System.IO.File]::WriteAllText($ResultFile, ($res | ConvertTo-Json -Depth 4))
'@, (New-Object System.Text.UTF8Encoding($false)))

function Invoke-Step {
    param([string]$Envelope, [hashtable]$Env = @{})

    $id = [guid]::NewGuid().ToString('N')
    $envFile = Join-Path $tmp "env-$id.txt"
    $resFile = Join-Path $tmp "res-$id.json"
    [System.IO.File]::WriteAllText($envFile, $Envelope, (New-Object System.Text.UTF8Encoding($false)))

    $saved = @{}
    foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    try {
        & pwsh -NoProfile -File $runnerFile $stepFile $envFile $resFile *> $null
    } finally {
        foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }

    if (-not (Test-Path -LiteralPath $resFile)) { return [pscustomobject]@{ Threw = $true; Stdout = ''; Error = 'runner produced no result file' } }
    $j = Get-Content -LiteralPath $resFile -Raw | ConvertFrom-Json
    return [pscustomobject]@{ Threw = [bool]$j.threw; Stdout = [string]$j.output; Error = [string]$j.error }
}

try {
    Write-Host "[1] prose envelope from run 51af7212aa5b (child actually succeeded)" -ForegroundColor Cyan
    # The exact string that produced the false failure.
    $prose = 'Child orchestration raindrop-video-generic-processor invoked synchronously; executionId 4e8aefe6c1f3 completed with status "succeeded". Returning the result envelope verbatim.'
    $r = Invoke-Step -Envelope $prose
    Assert (-not $r.Threw) "prose status-succeeded narrative is accepted $($r.Error)"
    Assert ($r.Stdout -match '"ok"\s*:\s*true') "emits an ok envelope"
    Assert ($r.Stdout -match 'succeeded') "reports childStatus succeeded"

    Write-Host "[2] plain JSON envelope" -ForegroundColor Cyan
    $r = Invoke-Step -Envelope '{"status":"succeeded","finalContent":"{\"ok\":true}"}'
    Assert (-not $r.Threw) "plain JSON success accepted "

    Write-Host "[3] fenced JSON envelope" -ForegroundColor Cyan
    $fenced = "Here is the result:`n" + '```json' + "`n" + '{"status":"succeeded","finalContent":"done"}' + "`n" + '```'
    $r = Invoke-Step -Envelope $fenced
    Assert (-not $r.Threw) "fenced JSON success accepted "

    Write-Host "[4] genuine child failure must still fail" -ForegroundColor Cyan
    $r = Invoke-Step -Envelope '{"status":"failed","finalContent":"submit-action-view-entry blew up"}'
    Assert ($r.Threw) "JSON status=failed is rejected"
    Assert ($r.Error -match "did not succeed") "error names the non-success status"
    Assert ($r.Error -match 'submit-action-view-entry blew up') "error carries the child's finalContent"

    Write-Host "[5] prose failure must still fail" -ForegroundColor Cyan
    $r = Invoke-Step -Envelope 'Child orchestration invoked synchronously; executionId aabbccdd1122 completed with status "failed".'
    Assert ($r.Threw) "prose status-failed narrative is rejected"

    Write-Host "[6] mixed narrative fails safe (failure word wins)" -ForegroundColor Cyan
    # A narrative that mentions both must NOT be read as a success.
    $r = Invoke-Step -Envelope 'Step one reported status "succeeded", but the orchestration ended with status "failed".'
    Assert ($r.Threw) "success+failure narrative is rejected rather than accepted"

    Write-Host "[7] empty output is a failure" -ForegroundColor Cyan
    $r = Invoke-Step -Envelope '   '
    Assert ($r.Threw) "whitespace-only envelope is rejected"
    Assert ($r.Error -match 'produced no output') "error explains the empty envelope"

    Write-Host "[8] unreadable envelope is rejected AND quoted back" -ForegroundColor Cyan
    # Diagnosability guard: the old code threw without showing the envelope, so
    # the only way to learn what arrived was to open the run folder by hand.
    $r = Invoke-Step -Envelope 'the child was dispatched and something happened, who can say what'
    Assert ($r.Threw) "unreadable envelope is rejected (fail-safe)"
    Assert ($r.Error -match 'could not determine child status') "error says the status was undeterminable"
    Assert ($r.Error -match 'who can say what') "error quotes the raw envelope for diagnosis"

    Write-Host "[9] executionId-only envelope resolves via the run history" -ForegroundColor Cyan
    # No status word anywhere -> the step must fall back to run.json on disk.
    $fakeLocal = Join-Path $tmp 'localappdata'
    $runDir = Join-Path $fakeLocal 'OrchestraHost\executions\raindrop-video-generic-processor\raindrop-video-generic-processor_1.1.0_orchestration_x_20260826-105534_4e8aefe6c1f3'
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    @'
{
  "runId": "4e8aefe6c1f3",
  "orchestrationName": "raindrop-video-generic-processor",
  "startedAt": "2026-08-26T10:55:34.3711289+00:00",
  "status": "Succeeded",
  "orchestrationVersion": "1.1.0"
}
'@ | Set-Content -LiteralPath (Join-Path $runDir 'run.json') -Encoding utf8

    $r = Invoke-Step -Envelope 'Child orchestration dispatched synchronously; executionId 4e8aefe6c1f3. Returning the result envelope verbatim.' -Env @{ LOCALAPPDATA = $fakeLocal }
    Assert (-not $r.Threw) "status resolved from run.json $($r.Error)"
    Assert ($r.Stdout -match '(?i)succeeded') "childStatus taken from the run history"

    Write-Host "[10] run-history fallback reports a failed child as failed" -ForegroundColor Cyan
    $runDir2 = Join-Path $fakeLocal 'OrchestraHost\executions\raindrop-video-generic-processor\raindrop-video-generic-processor_1.1.0_orchestration_x_20260826-110000_ffee11223344'
    New-Item -ItemType Directory -Path $runDir2 -Force | Out-Null
    @'
{
  "runId": "ffee11223344",
  "orchestrationName": "raindrop-video-generic-processor",
  "status": "Failed"
}
'@ | Set-Content -LiteralPath (Join-Path $runDir2 'run.json') -Encoding utf8

    $r = Invoke-Step -Envelope 'Child orchestration dispatched synchronously; executionId ffee11223344. Returning the result envelope verbatim.' -Env @{ LOCALAPPDATA = $fakeLocal }
    Assert ($r.Threw) "failed child resolved from run.json is rejected"

    Write-Host "[11] unknown executionId still fails safe" -ForegroundColor Cyan
    $r = Invoke-Step -Envelope 'Child orchestration dispatched synchronously; executionId 000000000000. Returning the result envelope verbatim.' -Env @{ LOCALAPPDATA = $fakeLocal }
    Assert ($r.Threw) "missing run folder does not become an accidental success"
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "verify-dispatch: $script:pass passed, $script:fail failed" -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
