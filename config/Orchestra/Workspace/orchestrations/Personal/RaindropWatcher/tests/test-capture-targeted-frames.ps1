#!/usr/bin/env pwsh
# Regression tests for tools/scripts/capture-targeted-frames.ps1 (the
# `targeted-frame-capture` step of the three raindrop video processors).
#
# Two silent-failure modes shipped for weeks without failing any run:
#
#   1. Picks parsing was a strict ConvertFrom-Json. From 2026-08-26 to
#      2026-10-05 the upstream `pick-targeted-frames` LLM step mostly answered
#      with prose ("Emitted the requested JSON on stdout ...") or a fenced
#      block, so the step saw "no picks" and every run produced ZERO targeted
#      frames while reporting ok=true.
#   2. Zakira.Replay was invoked through the `dnx` launcher, which is a cmd.exe
#      batch shim. cmd.exe treats an unquoted `&` in the video URL
#      (`...watch?v=ID&t=1s`) as a command separator, so the URL was truncated,
#      every flag after it was dropped, the CLI ran a full default extraction
#      into a fresh run directory, and the step ended with
#      "'t' is not recognized as an internal or external command" (run
#      b431f0c6a0f5 and every earlier `&` URL).
#
# These tests run the *shipped* script with a fake `dotnet` placed first on
# PATH, so they are fully offline and assert the exact argument vector that
# would reach Zakira.Replay.
#
# Exit 0 = all pass; 1 = failure.

param(
    [string]$Script = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\scripts\capture-targeted-frames.ps1')
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:pass = 0; $script:fail = 0
function Assert([bool]$c, [string]$m) {
    if ($c) { $script:pass++; Write-Host "  PASS  $m" -ForegroundColor Green }
    else    { $script:fail++; Write-Host "  FAIL  $m" -ForegroundColor Red }
}

if (-not (Test-Path -LiteralPath $Script)) { throw "script not found: $Script" }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("capture-targeted-frames-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$shimDir = Join-Path $tmp 'shim'
New-Item -ItemType Directory -Path $shimDir -Force | Out-Null

# --- Fake `dotnet` ------------------------------------------------------------
# Records the exact argument vector it received and answers like Zakira.Replay's
# `frames --output-format json`: one frame per `--at` timestamp. Behaviour is
# driven by env vars so the shim itself never changes between cases.
#   CAPTURE_TEST_ARGS_FILE  where to write the received args (one per line)
#   CAPTURE_TEST_MODE       ok (default) | fail
# Diagnostics go through Write-Output rather than [Console]::Error: the real
# dotnet.exe's stderr is merged by the script's `2>&1`, but a .ps1 shim's raw
# Console.Error bypasses PowerShell redirection, so stdout is the faithful
# stand-in for "merged output" here.
[System.IO.File]::WriteAllText((Join-Path $shimDir 'dotnet.ps1'), @'
$argsFile = $env:CAPTURE_TEST_ARGS_FILE
if ($argsFile) { [System.IO.File]::WriteAllLines($argsFile, [string[]]$args) }

if ($env:CAPTURE_TEST_MODE -eq 'fail') {
    Write-Output "Analyzing ..."
    Write-Output "boom: simulated CLI failure"
    exit 1
}

$at = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '--at' -and $i + 1 -lt $args.Count) { $at = [string]$args[$i + 1] } }
$frames = @()
$n = 0
foreach ($ts in ($at -split ',' | Where-Object { $_ })) {
    $n++
    $frames += [ordered]@{ id = "frame-$n"; path = "C:\fake\runs\r1\frames\frame-$n-$($ts -replace ':','-').jpg"; timestampLabel = $ts }
}
Write-Output "Done in 0s. r1 - $n frames"
[ordered]@{ runId = 'r1'; frames = $frames; warnings = @() } | ConvertTo-Json -Depth 6
exit 0
'@, (New-Object System.Text.UTF8Encoding($false)))

$analyzeJson = '{"runId":"wogdlm3tdr0-ab8451ef","status":"completed","artifactDirectory":"C:\\temp\\Zakira.Replay\\runs\\wogdlm3tdr0-ab8451ef"}'
$ampUrl      = 'https://www.youtube.com/watch?v=woGDLM3Tdr0&t=1s'
$picksObject = '{"ok":true,"picks":[{"timestamp":"00:05:18","reason":"keys"},{"timestamp":"00:09:38","reason":"ponytail"},{"timestamp":"00:13:42","reason":"police"}]}'

# Runs the shipped script in a child pwsh with the shim first on PATH. Inputs
# travel via files to avoid command-line quoting damage; the result is the last
# JSON object on stdout (the script's single Write-Out).
function Invoke-Capture {
    param([string]$Picks, [string]$Source = $ampUrl, [string]$Analyze = $analyzeJson, [int]$MaxCap = 5, [string]$Mode = 'ok')

    $id = [guid]::NewGuid().ToString('N')
    $argsFile = Join-Path $tmp "args-$id.txt"
    $picksFile = Join-Path $tmp "picks-$id.txt"
    $analyzeFile = Join-Path $tmp "analyze-$id.txt"
    [System.IO.File]::WriteAllText($picksFile, $Picks, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($analyzeFile, $Analyze, (New-Object System.Text.UTF8Encoding($false)))

    $runner = @"
`$env:PATH = '$shimDir;' + `$env:PATH
`$env:CAPTURE_TEST_ARGS_FILE = '$argsFile'
`$env:CAPTURE_TEST_MODE = '$Mode'
`$picks = [System.IO.File]::ReadAllText('$picksFile')
`$analyze = [System.IO.File]::ReadAllText('$analyzeFile')
& '$Script' -PicksJson `$picks -Source '$Source' -ZakiraAnalyzeJson `$analyze -MaxCap $MaxCap
"@
    $stdout = & pwsh -NoProfile -Command $runner 2>$null | Out-String
    $exit = $LASTEXITCODE

    $json = $null
    $lastBrace = $stdout.LastIndexOf('{')
    $firstBrace = $stdout.IndexOf('{')
    if ($firstBrace -ge 0) { try { $json = $stdout.Substring($firstBrace).Trim() | ConvertFrom-Json -Depth 10 } catch { $json = $null } }

    $cliArgs = @()
    if (Test-Path -LiteralPath $argsFile) { $cliArgs = @([System.IO.File]::ReadAllLines($argsFile)) }

    return [pscustomobject]@{ Exit = $exit; Result = $json; CliArgs = $cliArgs; CliInvoked = (Test-Path -LiteralPath $argsFile); Stdout = $stdout }
}

try {
    Write-Host "[1] bare JSON picks -> all frames captured, URL with '&' reaches the CLI intact" -ForegroundColor Cyan
    $r = Invoke-Capture -Picks $picksObject
    Assert ($r.Exit -eq 0) "script exits 0"
    Assert ($null -ne $r.Result) "emits a JSON envelope"
    Assert ($r.Result.ok -eq $true) "ok=true"
    Assert (@($r.Result.captured).Count -eq 3) "captured 3 of 3 picks (got $(@($r.Result.captured).Count))"
    Assert ($r.Result.budget -eq 'captured 3 of 5') "budget string reports 3 of 5"
    Assert ($r.CliInvoked) "Zakira.Replay CLI was invoked"
    Assert ($r.CliArgs[0] -eq 'dnx' -and $r.CliArgs[1] -eq 'Zakira.Replay') "invoked as 'dotnet dnx Zakira.Replay ...' (real dotnet.exe, not the dnx.cmd shim)"
    Assert ($r.CliArgs -contains $ampUrl) "full URL including '&t=1s' arrives as ONE argument"
    $atIdx = [Array]::IndexOf($r.CliArgs, '--at')
    Assert ($atIdx -ge 0 -and $r.CliArgs[$atIdx + 1] -eq '00:05:18,00:09:38,00:13:42') "--at carries the comma-joined timestamps in order"
    $ridIdx = [Array]::IndexOf($r.CliArgs, '--run-id')
    Assert ($ridIdx -ge 0 -and $r.CliArgs[$ridIdx + 1] -eq 'wogdlm3tdr0-ab8451ef') "--run-id reuses the analyze run (no fresh extraction)"
    Assert ($r.CliArgs -contains '--output-format' -and $r.CliArgs -contains 'json') "--output-format json survives after the URL"
    Assert ((@($r.Result.captured) | ForEach-Object { $_.reason }) -join ',' -eq 'keys,ponytail,police') "captured entries keep the pick reasons positionally"
    Assert (@($r.Result.captured)[0].fileUri -like 'file:///C:/fake/*') "captured entries expose a file:// URI"

    Write-Host "[2] prose-wrapped JSON (the post-2026-08-26 LLM shape) is still parsed" -ForegroundColor Cyan
    $prose = "Selected three transcript-grounded visual moments and emitted the requested JSON on stdout.`n`n$picksObject`n`nVerified timestamp format and separation from baseline frames."
    $r = Invoke-Capture -Picks $prose
    Assert ($r.Result.ok -eq $true -and @($r.Result.captured).Count -eq 3) "3 picks extracted from prose (got $(@($r.Result.captured).Count))"

    Write-Host "[3] fenced JSON block is parsed" -ForegroundColor Cyan
    $fenced = "Here you go:`n" + '```json' + "`n" + $picksObject + "`n" + '```'
    $r = Invoke-Capture -Picks $fenced
    Assert ($r.Result.ok -eq $true -and @($r.Result.captured).Count -eq 3) "3 picks extracted from a fenced block (got $(@($r.Result.captured).Count))"

    Write-Host "[4] picks object embedded after an unrelated object" -ForegroundColor Cyan
    $multi = '{"status":"thinking"} ... final answer: ' + $picksObject
    $r = Invoke-Capture -Picks $multi
    Assert ($r.Result.ok -eq $true -and @($r.Result.captured).Count -eq 3) "the object carrying 'picks' wins over an earlier object (got $(@($r.Result.captured).Count))"

    Write-Host "[5] prose with no JSON -> no picks, no CLI call, step still succeeds" -ForegroundColor Cyan
    $r = Invoke-Capture -Picks 'Emitted the requested JSON on stdout with five picks; all timestamps verified.'
    Assert ($r.Exit -eq 0 -and $r.Result.ok -eq $true) "ok=true (never fails the orchestration)"
    Assert (@($r.Result.captured).Count -eq 0) "captured 0"
    Assert ($r.Result.note -eq 'no picks from upstream prompt') "note explains the empty result"
    Assert (-not $r.CliInvoked) "CLI not invoked when there is nothing to capture"

    Write-Host "[6] picks beyond MaxCap are skipped with a reason" -ForegroundColor Cyan
    $seven = '{"ok":true,"picks":[' + ((1..7 | ForEach-Object { "{`"timestamp`":`"00:0$_`:00`",`"reason`":`"r$_`"}" }) -join ',') + ']}'
    $r = Invoke-Capture -Picks $seven -MaxCap 5
    Assert (@($r.Result.captured).Count -eq 5) "captured exactly 5 (got $(@($r.Result.captured).Count))"
    Assert (@($r.Result.skipped).Count -eq 2 -and (@($r.Result.skipped) | Where-Object { $_.reason -like 'exceeds cap*' }).Count -eq 2) "2 overflow picks reported as skipped"
    $atIdx = [Array]::IndexOf($r.CliArgs, '--at')
    Assert (($r.CliArgs[$atIdx + 1] -split ',').Count -eq 5) "only the capped timestamps are sent to the CLI"

    Write-Host "[7] CLI failure is reported in the envelope without throwing" -ForegroundColor Cyan
    $r = Invoke-Capture -Picks $picksObject -Mode fail
    Assert ($r.Exit -eq 0) "script still exits 0"
    Assert ($r.Result.ok -eq $false) "ok=false"
    Assert ($r.Result.error -eq 'Zakira.Replay frames exit=1') "error names the CLI exit code"
    Assert ([string]$r.Result.cliOutputTail -match 'simulated CLI failure') "cliOutputTail carries the CLI's stderr for diagnosis"

    Write-Host "[8] missing runId in the analyze payload is reported, CLI not called" -ForegroundColor Cyan
    $r = Invoke-Capture -Picks $picksObject -Analyze '{"status":"completed"}'
    Assert ($r.Result.ok -eq $false -and $r.Result.error -match 'runId') "ok=false with a runId error"
    Assert (-not $r.CliInvoked) "CLI not invoked without a runId"
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "capture-targeted-frames: $script:pass passed, $script:fail failed" -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
