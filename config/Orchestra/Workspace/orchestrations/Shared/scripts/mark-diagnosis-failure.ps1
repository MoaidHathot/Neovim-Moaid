# mark-diagnosis-failure.ps1
#
# Backs the per-failure buttons on the per-orchestration diagnosis ActionView
# card (Mark fixed / Dismiss this failure / Re-run / Revert). Each button
# targets ONE failure inside an orchestration's diagnosis ledger, addressed by
# (orchestrationName, signature). The card is a pure projection of that ledger,
# so every action here mutates the ledger via diagnosis-lib.ps1 and then
# re-renders/re-publishes the single card (or clears it when nothing is left to
# show).
#
# This mirrors mark-ledger-item.ps1 / flag-as-not-an-ask.ps1: a small
# synchronous pwsh wrapper is the cheapest reliable thing an ActionView button
# can call at click time.
#
# Actions:
#   fixed     -> failure.state = 'fixed'      (re-opens automatically as a
#                'regressed' failure if the same signature recurs later)
#   dismissed -> failure.state = 'dismissed'  (suppressed even if it recurs)
#   reopen    -> failure.state = 'open'
#   rerun     -> trigger `orchestra run <orchestrationName>` (no state change)
#   revert    -> restore the target orchestration YAML from the most recent
#                fix attempt's backup, then set failure.state = 'open'
#
# Usage (called by ActionView action buttons):
#   pwsh -NoProfile -NoLogo -NonInteractive -File mark-diagnosis-failure.ps1 `
#     -Action fixed `
#     -OrchestrationName raindrop-tracker `
#     -Signature f40a2b61c987be50 `
#     -DbPath C:\Users\me\.config\orchestra\zakira.db `
#     -SharedScriptsDir C:\...\Shared\scripts `
#     -ServerUrl http://localhost:5100 `
#     -OrchestrationsRoot C:\...\workspace\orchestrations `
#     [-Notes 'optional free-form note']
#
# Exit codes:
#   0  success
#   1  ledger / failure not found
#   2  CLI or filesystem operation failed
#   3  bad input

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('fixed', 'dismissed', 'reopen', 'rerun', 'revert')][string]$Action,
    [Parameter(Mandatory)][string]$OrchestrationName,
    [Parameter(Mandatory)][string]$Signature,
    [string]$DbPath = '',
    [string]$SharedScriptsDir = '',
    [string]$ServerUrl = '',
    [string]$OrchestrationsRoot = '',
    [string]$Notes = ''
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'

# Resolve the shared library. Prefer the passed dir; fall back to XDG dotfiles.
$libPath = if (-not [string]::IsNullOrWhiteSpace($SharedScriptsDir)) { Join-Path $SharedScriptsDir 'diagnosis-lib.ps1' } else { '' }
if ([string]::IsNullOrWhiteSpace($libPath) -or -not (Test-Path -LiteralPath $libPath)) {
    $cfg = $env:XDG_CONFIG_HOME
    if ([string]::IsNullOrWhiteSpace($cfg)) { $cfg = Join-Path $env:USERPROFILE '.config' }
    $SharedScriptsDir = Join-Path $cfg 'Orchestra/workspace/orchestrations/Shared/scripts'
    $libPath = Join-Path $SharedScriptsDir 'diagnosis-lib.ps1'
}
if (-not (Test-Path -LiteralPath $libPath)) {
    [Console]::Error.WriteLine("diagnosis-lib.ps1 not found (looked at '$libPath').")
    exit 3
}
. $libPath

$SharedScriptsDir = [System.IO.Path]::GetFullPath($SharedScriptsDir)
$DbPath = Resolve-ZakiraDbPath -DbPath $DbPath
$OrchestrationsRoot = Resolve-OrchestrationsRoot -Provided $OrchestrationsRoot
$author = 'actionview-button'

if (-not (Test-Path -LiteralPath $DbPath)) {
    [Console]::Error.WriteLine("Zakira database not found at: $DbPath")
    exit 3
}

$ledger = Get-DiagnosisLedger -DbPath $DbPath -OrchestrationName $OrchestrationName
if ($null -eq $ledger) {
    [Console]::Error.WriteLine("No diagnosis ledger for orchestration '$OrchestrationName'.")
    exit 1
}
$failure = Find-DiagnosisFailure -Ledger $ledger -Signature $Signature
if ($null -eq $failure) {
    [Console]::Error.WriteLine("No failure with signature '$Signature' in ledger for '$OrchestrationName'.")
    exit 1
}

function Publish-Or-Clear {
    param($Ledger)
    $visible = Get-DiagnosisVisibleFailures -Ledger $Ledger
    if (@($visible).Count -eq 0) {
        return (Clear-DiagnosisCard -Ledger $Ledger -DbPath $DbPath -Author $author)
    }
    return (Publish-DiagnosisCard -Ledger $Ledger -DbPath $DbPath -SharedScriptsDir $SharedScriptsDir `
            -ServerUrl $ServerUrl -OrchestrationsRoot $OrchestrationsRoot -Author $author)
}

$nowIso = (Get-Date).ToUniversalTime().ToString('o')

switch ($Action) {
    'fixed' {
        [void](Set-DiagnosisFailureState -Ledger $ledger -Signature $Signature -State 'fixed' -UserNotes $Notes)
        [void](Publish-Or-Clear -Ledger $ledger)
        "OK $OrchestrationName/$Signature -> fixed @ $nowIso"
        exit 0
    }
    'dismissed' {
        [void](Set-DiagnosisFailureState -Ledger $ledger -Signature $Signature -State 'dismissed' -UserNotes $Notes)
        [void](Publish-Or-Clear -Ledger $ledger)
        "OK $OrchestrationName/$Signature -> dismissed @ $nowIso"
        exit 0
    }
    'reopen' {
        [void](Set-DiagnosisFailureState -Ledger $ledger -Signature $Signature -State 'open' -UserNotes $Notes)
        [void](Publish-Or-Clear -Ledger $ledger)
        "OK $OrchestrationName/$Signature -> reopened @ $nowIso"
        exit 0
    }
    'rerun' {
        $res = Invoke-OrchestraOrchestration -Name $OrchestrationName -Parameters @{} -ServerUrl $ServerUrl -By 'actionview-diagnosis-rerun'
        if (-not $res.ok) {
            [Console]::Error.WriteLine("Re-run trigger failed ($($res.method)): $($res.output)")
            exit 2
        }
        "OK re-run '$OrchestrationName' via $($res.method) @ $nowIso"
        exit 0
    }
    'revert' {
        $path = [string]$ledger.orchestrationPath
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
            [Console]::Error.WriteLine("Cannot revert: orchestration path '$path' not found.")
            exit 2
        }
        $attempts = @($failure.fixAttempts)
        if ($attempts.Count -eq 0) {
            [Console]::Error.WriteLine('Cannot revert: no recorded fix attempt with a backup.')
            exit 1
        }
        $backup = [string]$attempts[$attempts.Count - 1].backup
        if ([string]::IsNullOrWhiteSpace($backup) -or -not (Test-Path -LiteralPath $backup)) {
            [Console]::Error.WriteLine("Cannot revert: backup '$backup' not found.")
            exit 2
        }
        try {
            Copy-Item -LiteralPath $backup -Destination $path -Force
        }
        catch {
            [Console]::Error.WriteLine("Revert copy failed: $($_.Exception.Message)")
            exit 2
        }
        # Record the revert and re-open the failure so the user can re-diagnose.
        $revertNote = "Reverted to backup $backup @ $nowIso"
        $existingNotes = [string]$failure.userNotes
        $mergedNotes = if ([string]::IsNullOrWhiteSpace($existingNotes)) { $revertNote } else { "$existingNotes`n$revertNote" }
        [void](Set-DiagnosisFailureState -Ledger $ledger -Signature $Signature -State 'open' -UserNotes $mergedNotes)
        $lastAttempt = $attempts[$attempts.Count - 1]
        Set-NoteProp $lastAttempt 'outcome' 'reverted'
        [void](Publish-Or-Clear -Ledger $ledger)
        "OK reverted '$OrchestrationName' from $backup @ $nowIso"
        exit 0
    }
}
