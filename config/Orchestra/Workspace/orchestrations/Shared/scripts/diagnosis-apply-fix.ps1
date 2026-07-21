# diagnosis-apply-fix.ps1
#
# Backs the "Apply Fix" button on the per-orchestration diagnosis ActionView
# card. The button collects an optional multiline Notes field and a Rerun
# checkbox, then calls this wrapper. It does two things, in order:
#
#   1. Records the user's notes onto the target failure in the diagnosis ledger
#      and flips its state to 'fix-requested', then re-publishes the card so the
#      user gets immediate feedback. Doing this FIRST guarantees the notes are
#      persisted even if launching the fixer is slow or the CLI path is busy.
#   2. Launches the `apply-orchestration-fix` orchestration (which performs the
#      actual LLM-driven YAML edit against the dotfile, records a fix attempt,
#      flips the failure to 'fix-applied' and re-publishes). Prefers the
#      `orchestra` CLI; falls back to the host REST API.
#
# The fixer reads the notes back from the ledger (addressed by name+signature);
# they are ALSO passed as a parameter for redundancy.
#
# Usage (called by the ActionView "Apply Fix" button):
#   pwsh -NoProfile -NoLogo -NonInteractive -File diagnosis-apply-fix.ps1 `
#     -OrchestrationName raindrop-tracker `
#     -Signature f40a2b61c987be50 `
#     -Notes '{{param.notes}}' `
#     -Rerun '{{param.rerun}}' `
#     -DbPath ... -ServerUrl ... -OrchestrationsRoot ... -SharedScriptsDir ...
#
# Exit codes:
#   0  success (notes recorded AND fixer launched)
#   1  ledger / failure not found
#   2  fixer launch failed (notes were still recorded)
#   3  bad input

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OrchestrationName,
    [Parameter(Mandatory)][string]$Signature,
    [string]$Notes = '',
    [string]$Rerun = 'false',
    [string]$DbPath = '',
    [string]$ServerUrl = '',
    [string]$OrchestrationsRoot = '',
    [string]$SharedScriptsDir = ''
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

# Normalize an unresolved ActionView placeholder to a safe default.
if ($Rerun -like '*{{*') { $Rerun = 'false' }
if ($Notes -like '*{{*') { $Notes = '' }

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

# Step 1: record notes + mark fix-requested, then re-publish for instant feedback.
if (-not [string]::IsNullOrWhiteSpace($Notes)) { Set-NoteProp $failure 'userNotes' $Notes }
[void](Set-DiagnosisFailureState -Ledger $ledger -Signature $Signature -State 'fix-requested' -UserNotes ([string]$failure.userNotes))
try {
    [void](Publish-DiagnosisCard -Ledger $ledger -DbPath $DbPath -SharedScriptsDir $SharedScriptsDir `
            -ServerUrl $ServerUrl -OrchestrationsRoot $OrchestrationsRoot -Author $author)
}
catch {
    # Non-fatal: the ledger already holds the notes/state; the fixer will re-publish.
    [Console]::Error.WriteLine("Warning: could not re-publish the card before launching the fixer: $($_.Exception.Message)")
}

# Step 2: launch the fixer orchestration (detached via dnx, so the button
# returns immediately). Notes are intentionally NOT passed as a --param: they
# were just written to the ledger above, and apply-orchestration-fix reads them
# back from there (addressed by name+signature). This also avoids putting a
# multiline value on a command line. dbPath + orchestrationsRoot are passed so
# the fixer operates on the exact same ledger + dotfiles workspace.
$params = @{
    orchestrationName  = $OrchestrationName
    signature          = $Signature
    rerunAfterApply    = $Rerun
    dbPath             = $DbPath
    orchestrationsRoot = $OrchestrationsRoot
}
$res = Invoke-OrchestraOrchestration -Name 'apply-orchestration-fix' -Parameters $params -ServerUrl $ServerUrl -By 'actionview-apply-fix'
if (-not $res.ok) {
    [Console]::Error.WriteLine("Notes recorded, but launching apply-orchestration-fix failed ($($res.method)): $($res.output)")
    exit 2
}

"OK apply-fix requested for $OrchestrationName/$Signature via $($res.method). Notes recorded; the fixer will edit the dotfile and update the card."
exit 0
