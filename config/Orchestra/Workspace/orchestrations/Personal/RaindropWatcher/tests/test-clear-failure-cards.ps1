#!/usr/bin/env pwsh
# Regression tests for the `clear-failure-cards` step in raindrop-processor.yaml.
#
# Background: the orchestration.failure hook publishes a stable-id
# `raindrop-error-<id>` ActionView card (and dead-letter-move a
# `raindrop-dead-letter-<id>` card), but nothing removed them once a LATER
# attempt of the same raindrop succeeded -- the per-processor submit only
# upserts its own `raindrop-<id>-<type>` id. Raindrop 1876741587 kept a
# "Raindrop processing failed" card on the dashboard for a day after it had
# been processed successfully.
#
# The step must:
#   - delete exactly the cards that exist for THIS raindrop,
#   - never fall into the CLI's prefix-match (`delete raindrop-error-123`
#     would happily delete `raindrop-error-1234` when `...-123` is absent),
#   - never throw (a throw would trip the failure hook and flip an
#     already-completed item back to failed).
#
# The shipped script is extracted from the YAML and run against a fake
# `dotnet` (a .cmd shim, because the step resolves dotnet with
# `Get-Command -CommandType Application`) that records every invocation and
# plays back canned `list` / `delete` output.
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

# --- Extract the step script block from the orchestration (textual, like test-verify-dispatch) ---
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
        if ($l -notmatch '^      ') { break }
        $body.Add($l.Substring(6))
    }
    return ($body -join "`n").TrimEnd()
}

$scriptText = Get-StepScript -Path $Orchestration -StepName 'clear-failure-cards'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("clear-failure-cards-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$stepFile = Join-Path $tmp 'clear-failure-cards.ps1'
[System.IO.File]::WriteAllText($stepFile, $scriptText, (New-Object System.Text.UTF8Encoding($false)))

# --- Fake `dotnet` ------------------------------------------------------------
# dotnet.cmd (an Application, so Get-Command -CommandType Application finds it)
# forwards to dotnet-shim.ps1. The shim appends each invocation's args to
# CFC_TEST_CALLS_FILE and answers from a JSON fixture in CFC_TEST_ACTIVE_FILE:
#   { "raindrop-error": ["<id>", ...], "raindrop-dead-letter": [...] }
# `list --type T` renders the CLI's table for the ids of that type; `delete X`
# mimics the real CLI: exact id -> "Deleted entry: X"; otherwise prefix-match
# (the footgun the step must avoid); nothing -> "Entry not found" on stderr,
# still exit 0. CFC_TEST_LIST_FAIL=1 makes `list` exit 1.
$shimDir = Join-Path $tmp 'shim'
New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $shimDir 'dotnet.cmd'), "@echo off`r`npwsh -NoProfile -File `"%~dp0dotnet-shim.ps1`" %*`r`nexit /b %ERRORLEVEL%`r`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $shimDir 'dotnet-shim.ps1'), @'
$callsFile = $env:CFC_TEST_CALLS_FILE
if ($callsFile) { Add-Content -LiteralPath $callsFile -Value ($args -join ' ') -Encoding utf8 }

$active = @{}
if ($env:CFC_TEST_ACTIVE_FILE -and (Test-Path -LiteralPath $env:CFC_TEST_ACTIVE_FILE)) {
    $j = Get-Content -LiteralPath $env:CFC_TEST_ACTIVE_FILE -Raw | ConvertFrom-Json
    foreach ($p in $j.PSObject.Properties) { $active[$p.Name] = @($p.Value) }
}
$allIds = @($active.Values | ForEach-Object { $_ })

# args: dnx ActionView.Cli --yes -- <verb> ...
$verb = $args[4]
switch ($verb) {
    'list' {
        if ($env:CFC_TEST_LIST_FAIL -eq '1') { [Console]::Error.WriteLine('simulated list failure'); exit 1 }
        $type = $null
        for ($i = 5; $i -lt $args.Count; $i++) { if ($args[$i] -eq '--type' -and $i + 1 -lt $args.Count) { $type = $args[$i + 1] } }
        $ids = if ($type -and $active.ContainsKey($type)) { @($active[$type]) } else { @() }
        if ($ids.Count -eq 0) { Write-Output 'No active entries.'; exit 0 }
        Write-Output ("{0,-34} {1,-10} {2,-8} {3,-16} {4}" -f 'ID', 'Sev', 'Status', 'Type', 'Title')
        Write-Output (New-Object string ('-', 100))
        foreach ($id in $ids) { Write-Output (" {0,-33} {1,-10} {2,-8} {3,-16} {4}" -f $id, 'High', 'Pending', $type, "Raindrop processing failed: x") }
        Write-Output ''
        Write-Output "Total: $($ids.Count) active entries"
        exit 0
    }
    'delete' {
        $id = $args[5]
        if ($allIds -contains $id) { Write-Output "Deleted entry: $id"; exit 0 }
        $prefix = @($allIds | Where-Object { $_.StartsWith($id, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($prefix.Count -eq 1) { Write-Output "Deleted entry: $($prefix[0])"; exit 0 }
        [Console]::Error.WriteLine("Entry not found: $id")
        exit 0
    }
    default { [Console]::Error.WriteLine("unexpected verb: $verb"); exit 2 }
}
'@, (New-Object System.Text.UTF8Encoding($false)))

function Invoke-Step {
    param([string]$RaindropId, [hashtable]$Active = @{}, [bool]$ListFail = $false)

    $id = [guid]::NewGuid().ToString('N')
    $callsFile = Join-Path $tmp "calls-$id.txt"
    $activeFile = Join-Path $tmp "active-$id.json"
    [System.IO.File]::WriteAllText($activeFile, ($Active | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

    $runner = @"
`$env:PATH = '$shimDir;' + `$env:PATH
`$env:CFC_TEST_CALLS_FILE = '$callsFile'
`$env:CFC_TEST_ACTIVE_FILE = '$activeFile'
`$env:CFC_TEST_LIST_FAIL = '$(if ($ListFail) { '1' } else { '0' })'
& '$stepFile' '$RaindropId'
"@
    $stdout = & pwsh -NoProfile -Command $runner 2>$null | Out-String
    $exit = $LASTEXITCODE
    $json = $null
    try { $json = $stdout.Trim() | ConvertFrom-Json } catch { }
    $calls = @()
    if (Test-Path -LiteralPath $callsFile) { $calls = @(Get-Content -LiteralPath $callsFile) }
    return [pscustomobject]@{ Exit = $exit; Result = $json; Calls = $calls; Stdout = $stdout }
}

try {
    Write-Host "[1] stale error card present -> deleted; dead-letter absent" -ForegroundColor Cyan
    $r = Invoke-Step -RaindropId '1876741587' -Active @{ 'raindrop-error' = @('raindrop-error-1876741587', 'raindrop-error-1865702641') }
    Assert ($r.Exit -eq 0) "step exits 0"
    Assert ($null -ne $r.Result) "emits a JSON envelope ($($r.Stdout.Trim()))"
    Assert ($r.Result.ok -eq $true) "ok=true"
    Assert (@($r.Result.deleted) -contains 'raindrop-error-1876741587') "deleted the raindrop-error card"
    Assert (@($r.Result.absent) -contains 'raindrop-dead-letter-1876741587') "dead-letter card reported absent"
    Assert (@($r.Calls | Where-Object { $_ -match '\bdelete\b' }).Count -eq 1) "exactly one delete call"
    Assert (@($r.Calls | Where-Object { $_ -match 'delete raindrop-error-1876741587 --force' }).Count -eq 1) "delete targets the exact id with --force"
    Assert (@($r.Calls | Where-Object { $_ -match 'delete raindrop-error-1865702641' }).Count -eq 0) "other raindrops' cards untouched"
    Assert ((@($r.Calls) | Where-Object { $_ -notmatch '^dnx ActionView\.Cli --yes -- ' }).Count -eq 0) "every call goes through 'dnx ActionView.Cli --yes --'"

    Write-Host "[2] both cards present -> both deleted" -ForegroundColor Cyan
    $r = Invoke-Step -RaindropId '42' -Active @{ 'raindrop-error' = @('raindrop-error-42'); 'raindrop-dead-letter' = @('raindrop-dead-letter-42') }
    Assert ($r.Result.ok -eq $true -and @($r.Result.deleted).Count -eq 2) "deleted 2 cards (got $(@($r.Result.deleted).Count))"
    Assert (@($r.Result.absent).Count -eq 0) "nothing reported absent"

    Write-Host "[3] no cards -> no delete calls, still ok" -ForegroundColor Cyan
    $r = Invoke-Step -RaindropId '7' -Active @{ 'raindrop-error' = @('raindrop-error-99') }
    Assert ($r.Result.ok -eq $true) "ok=true"
    Assert (@($r.Result.deleted).Count -eq 0 -and @($r.Result.absent).Count -eq 2) "both ids reported absent, none deleted"
    Assert (@($r.Calls | Where-Object { $_ -match '\bdelete\b' }).Count -eq 0) "no delete call issued"

    Write-Host "[4] prefix-collision guard: a longer id that starts with ours must NOT be deleted" -ForegroundColor Cyan
    # Real CLI behaviour: `delete raindrop-error-123` with no exact file falls back to a
    # prefix match and would delete raindrop-error-1234. The step must never get there.
    $r = Invoke-Step -RaindropId '123' -Active @{ 'raindrop-error' = @('raindrop-error-1234') }
    Assert (@($r.Calls | Where-Object { $_ -match '\bdelete\b' }).Count -eq 0) "no delete call when only a prefix-colliding id exists"
    Assert (@($r.Result.absent) -contains 'raindrop-error-123') "our id reported absent"

    Write-Host "[5] list failure is reported, step does not throw" -ForegroundColor Cyan
    $r = Invoke-Step -RaindropId '5' -Active @{ 'raindrop-error' = @('raindrop-error-5') } -ListFail $true
    Assert ($r.Exit -eq 0) "step exits 0 even when the CLI fails"
    Assert ($r.Result.ok -eq $false) "ok=false"
    Assert (@($r.Result.errors).Count -ge 1 -and ([string]@($r.Result.errors)[0] -match 'list --type raindrop-error')) "error names the failing list call"
    Assert (@($r.Calls | Where-Object { $_ -match '\bdelete\b' }).Count -eq 0) "no blind delete after a failed list"

    Write-Host "[6] empty raindropId -> ok=false, no CLI call" -ForegroundColor Cyan
    $r = Invoke-Step -RaindropId '' -Active @{}
    Assert ($r.Exit -eq 0 -and $r.Result.ok -eq $false) "ok=false without throwing"
    Assert ($r.Calls.Count -eq 0) "CLI never invoked"
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "clear-failure-cards: $script:pass passed, $script:fail failed" -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
