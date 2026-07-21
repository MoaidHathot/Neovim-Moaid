# diagnosis-lib.ps1
#
# Shared library for the failed-orchestration self-healing pipeline. This file
# is the single source of truth for two things that MUST stay identical across
# every producer/consumer of the diagnosis ledger:
#
#   1. The failure SIGNATURE algorithm (Get-DiagnosisSignature). The signature
#      is what dedupes "the same failure" across runs. It is computed
#      deterministically from the failing step names + error categories + a
#      normalized error text (volatile bits like GUIDs, timestamps, absolute
#      paths, execution ids and long numbers are stripped) so that the same
#      underlying bug hashes to the same 16-hex string every time. It is
#      LLM-free on purpose: the grandchild diagnoser, the per-orchestration
#      aggregator and the ActionView button wrappers must all agree on it.
#
#   2. The per-orchestration diagnosis LEDGER (the "ViewModel") stored in
#      Zakira.Exchange under category 'orchestration-diagnoses', key =
#      orchestration name. ActionView cards are a pure projection ("View") of
#      this ledger. All lifecycle state (open / fix-requested / fix-applied /
#      fixed / dismissed / regressed), the list of distinct failures, their
#      occurrences, fix attempts and user notes live here - never in ActionView.
#
# Ledger payload shape (Data: JSON on the Zakira entry):
#   {
#     "schemaVersion": 1,
#     "orchestrationName": "raindrop-tracker",
#     "orchestrationPath": "P:/.../raindrop-tracker.yaml",
#     "orchestrationFound": true,
#     "status": "open" | "resolved",
#     "createdAt": "<iso>",
#     "updatedAt": "<iso>",
#     "lastPublishedHash": "<hex or empty>",
#     "failures": [
#       {
#         "signature": "<16 hex>",
#         "state": "open|fix-requested|fix-applied|fixed|dismissed|regressed",
#         "firstSeenAt": "<iso>", "lastSeenAt": "<iso>",
#         "occurrences": 3,
#         "runIds": ["..."], "executionIds": ["..."],
#         "failingSteps": [ { "name": "...", "errorCategory": "...", "error": "..." } ],
#         "rootCause": "...", "explanation": "...",
#         "fixTarget": "orchestration-yaml|orchestra-source|unknown",
#         "suggestedFix": "...", "confidence": "high|medium|low",
#         "regression": false, "regressionCount": 0,
#         "userNotes": "",
#         "fixAttempts": [
#           { "at": "<iso>", "userNotes": "...", "backup": "...",
#             "outcome": "applied|reverted", "recurredAfter": false,
#             "diffSummary": "..." }
#         ],
#         "lastDiagnosisAt": "<iso>"
#       }
#     ]
#   }
#
# Dot-source it from an Orchestra Script step or a button wrapper:
#   . (Join-Path $sharedScriptsDir 'diagnosis-lib.ps1')
#
# Callers that pass JSON to the Zakira CLI MUST set
# `$PSNativeCommandArgumentPassing = 'Standard'` so inner quotes survive.

$script:DiagnosisLedgerCategory = 'orchestration-diagnoses'

# States that represent an ACTIVE, still-actionable problem and are rendered as
# failure sections on the card. 'fixed' and 'dismissed' are terminal/hidden
# (a 'fixed' failure that recurs is promoted back to 'regressed' by the merge).
$script:DiagnosisVisibleStates = @('open', 'fix-requested', 'fix-applied', 'regressed')

function Get-DiagnosisLedgerCategory { return $script:DiagnosisLedgerCategory }
function Get-DiagnosisVisibleStates { return $script:DiagnosisVisibleStates }

function Resolve-ZakiraDbPath {
    # Rebuild the real Zakira db path from the environment when an empty value
    # or an unexpanded '{{...}}' template token arrives (the engine does not
    # expand template tokens inside input default values, and button wrappers
    # may be handed an empty path).
    param([string]$DbPath)
    if (-not [string]::IsNullOrWhiteSpace($DbPath) -and $DbPath -notlike '*{{*') {
        return [System.IO.Path]::GetFullPath($DbPath)
    }
    $cfg = $env:XDG_CONFIG_HOME
    if ([string]::IsNullOrWhiteSpace($cfg)) { $cfg = Join-Path $env:USERPROFILE '.config' }
    return [System.IO.Path]::GetFullPath((Join-Path (Join-Path $cfg 'orchestra') 'zakira.db'))
}

function Resolve-OrchestrationsRoot {
    # The dotfiles workspace root that Orchestra WATCHES. We always edit here
    # (never the compiled internal copy under %LOCALAPPDATA%/OrchestraHost/
    # orchestrations, which the watcher regenerates from these sources).
    param([string]$Provided)
    if (-not [string]::IsNullOrWhiteSpace($Provided) -and $Provided -notlike '*{{*' -and (Test-Path -LiteralPath $Provided)) {
        return (Resolve-Path -LiteralPath $Provided).Path
    }
    $cfg = $env:XDG_CONFIG_HOME
    if ([string]::IsNullOrWhiteSpace($cfg)) { $cfg = Join-Path $env:USERPROFILE '.config' }
    return [System.IO.Path]::GetFullPath((Join-Path $cfg 'Orchestra/workspace/orchestrations'))
}

function Get-DiagnosisDataJsonFromCliOutput {
    # Extract the `Data:` JSON payload span from `Zakira.Exchange get` output.
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

function ConvertTo-NormalizedErrorText {
    # Strip volatile substrings so the same underlying failure normalizes to a
    # stable string regardless of run-specific ids/timestamps/paths.
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = $Text.ToLowerInvariant()
    # GUIDs.
    $t = [regex]::Replace($t, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<guid>')
    # ISO-8601 timestamps.
    $t = [regex]::Replace($t, '\d{4}-\d{2}-\d{2}[t ]\d{2}:\d{2}:\d{2}(\.\d+)?(z|[+-]\d{2}:\d{2})?', '<ts>')
    # Bare clock times.
    $t = [regex]::Replace($t, '\d{1,2}:\d{2}:\d{2}(\.\d+)?', '<time>')
    # Windows drive paths and UNC-ish / posix paths.
    $t = [regex]::Replace($t, '[a-z]:\\[^\s''"|]+', '<path>')
    $t = [regex]::Replace($t, '(?:/[^\s''":|]+){2,}', '<path>')
    # 12-64 char hex runs (execution ids, hashes, sha).
    $t = [regex]::Replace($t, '\b[0-9a-f]{12,64}\b', '<hex>')
    # line:col and "line N".
    $t = [regex]::Replace($t, 'line \d+', 'line <n>')
    $t = [regex]::Replace($t, ':\d+:\d+', ':<n>:<n>')
    # Any other long standalone number.
    $t = [regex]::Replace($t, '\b\d{3,}\b', '<num>')
    # Collapse whitespace.
    $t = ([regex]::Replace($t, '\s+', ' ')).Trim()
    if ($t.Length -gt 600) { $t = $t.Substring(0, 600) }
    return $t
}

function Get-DiagnosisSignature {
    # Deterministic 16-hex signature for a set of failing steps. Order-independent
    # (steps are sorted) so re-ordering does not change the signature.
    param($FailingSteps)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($fs in @($FailingSteps)) {
        if ($null -eq $fs) { continue }
        $name = ([string]$fs.name).Trim().ToLowerInvariant()
        $cat  = ([string]$fs.errorCategory).Trim().ToLowerInvariant()
        $err  = ConvertTo-NormalizedErrorText ([string]$fs.error)
        $parts.Add("$name|$cat|$err")
    }
    if ($parts.Count -eq 0) { $parts.Add('unknown-failure') }
    $joined = (@($parts) | Sort-Object) -join "`n"
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try { $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($joined)) }
    finally { $sha.Dispose() }
    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant().Substring(0, 16)
}

function Set-NoteProp {
    # Assign a property whether or not it already exists. Direct assignment to a
    # non-existent property throws on a PSCustomObject (including ones freshly
    # deserialized from JSON by an older schema), so route every "might be new"
    # write through Add-Member -Force.
    param($Obj, [string]$Name, $Value)
    if ($null -eq $Obj) { return }
    if ($Obj.PSObject.Properties[$Name]) { $Obj.$Name = $Value }
    else { $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}

function Get-DiagnosisConfidenceRank {
    param([string]$Confidence)
    switch (([string]$Confidence).Trim().ToLowerInvariant()) {
        'high'   { return 3 }
        'medium' { return 2 }
        'low'    { return 1 }
        default  { return 0 }
    }
}

function Get-DiagnosisLedger {
    # Returns the parsed ledger object for an orchestration, or $null when no
    # ledger entry exists yet. Throws on unexpected CLI failures.
    param([string]$DbPath, [string]$OrchestrationName)
    $out = & dnx Zakira.Exchange --yes -- --db $DbPath get $script:DiagnosisLedgerCategory $OrchestrationName 2>&1
    $code = $LASTEXITCODE
    if ($code -eq 1) { return $null }
    if ($code -ne 0) {
        $text = if ($out -is [array]) { ($out -join "`n") } else { [string]$out }
        throw "Zakira get failed (exit $code) for $script:DiagnosisLedgerCategory/${OrchestrationName}: $text"
    }
    $json = Get-DiagnosisDataJsonFromCliOutput -Lines $out
    if ([string]::IsNullOrWhiteSpace($json)) { return $null }
    return (ConvertFrom-Json -InputObject $json -Depth 100)
}

function Limit-DiagnosisLedgerSize {
    # Safety net so the ledger always fits in a Zakira --data command-line
    # argument (Windows caps a process command line at ~32K chars). Trims the
    # largest free-text fields, then, if still too big, strips detail from
    # resolved/dismissed failures (keeping their signature + state). Mutates and
    # returns the ledger.
    param($Ledger, [int]$MaxChars = 24000)
    if ($null -eq $Ledger) { return $Ledger }
    $json = $Ledger | ConvertTo-Json -Depth 100 -Compress
    if ($json.Length -le $MaxChars) { return $Ledger }

    # Pass 1: cap per-failure free text + bound the growing arrays.
    foreach ($f in @($Ledger.failures)) {
        if (([string]$f.explanation).Length -gt 800) { Set-NoteProp $f 'explanation' (([string]$f.explanation).Substring(0, 800) + ' [trimmed]') }
        if (([string]$f.fixPlan).Length -gt 600) { Set-NoteProp $f 'fixPlan' (([string]$f.fixPlan).Substring(0, 600) + ' [trimmed]') }
        if (([string]$f.suggestedFix).Length -gt 1000) { Set-NoteProp $f 'suggestedFix' (([string]$f.suggestedFix).Substring(0, 1000) + ' [trimmed]') }
        if (([string]$f.rootCause).Length -gt 400) { Set-NoteProp $f 'rootCause' (([string]$f.rootCause).Substring(0, 400) + ' [trimmed]') }
        $steps = @()
        foreach ($s in @($f.failingSteps)) {
            $e = [string]$s.error
            if ($e.Length -gt 500) { $e = $e.Substring(0, 500) + ' [trimmed]' }
            $steps += [pscustomobject]@{ name = [string]$s.name; status = [string]$s.status; errorCategory = [string]$s.errorCategory; error = $e }
        }
        Set-NoteProp $f 'failingSteps' $steps
        if (@($f.runIds).Count -gt 25) { Set-NoteProp $f 'runIds' (@($f.runIds) | Select-Object -Last 25) }
        if (@($f.executionIds).Count -gt 25) { Set-NoteProp $f 'executionIds' (@($f.executionIds) | Select-Object -Last 25) }
        $atts = @($f.fixAttempts)
        if ($atts.Count -gt 5) { $atts = @($atts | Select-Object -Last 5) }
        foreach ($at in $atts) { if (([string]$at.diffSummary).Length -gt 300) { Set-NoteProp $at 'diffSummary' (([string]$at.diffSummary).Substring(0, 300) + ' [trimmed]') } }
        Set-NoteProp $f 'fixAttempts' $atts
    }
    $json = $Ledger | ConvertTo-Json -Depth 100 -Compress
    if ($json.Length -le $MaxChars) { return $Ledger }

    # Pass 2: strip detail from resolved/dismissed (non-visible) failures.
    foreach ($f in @($Ledger.failures)) {
        if ($script:DiagnosisVisibleStates -notcontains ([string]$f.state)) {
            Set-NoteProp $f 'explanation' ''
            Set-NoteProp $f 'fixPlan' ''
            Set-NoteProp $f 'suggestedFix' ''
            Set-NoteProp $f 'failingSteps' @()
        }
    }
    $json = $Ledger | ConvertTo-Json -Depth 100 -Compress
    if ($json.Length -le $MaxChars) { return $Ledger }

    # Pass 3 (last resort): hard-trim every failure's free text to the bone.
    foreach ($f in @($Ledger.failures)) {
        if (([string]$f.explanation).Length -gt 200) { Set-NoteProp $f 'explanation' (([string]$f.explanation).Substring(0, 200) + ' [trimmed]') }
        if (([string]$f.fixPlan).Length -gt 200) { Set-NoteProp $f 'fixPlan' (([string]$f.fixPlan).Substring(0, 200) + ' [trimmed]') }
        if (([string]$f.suggestedFix).Length -gt 200) { Set-NoteProp $f 'suggestedFix' (([string]$f.suggestedFix).Substring(0, 200) + ' [trimmed]') }
        Set-NoteProp $f 'failingSteps' @()
    }
    return $Ledger
}

function Save-DiagnosisLedger {
    # Idempotent edit-or-create of the ledger entry. Callers must have set
    # $PSNativeCommandArgumentPassing = 'Standard' so the JSON survives.
    #
    # IMPORTANT: the ledger JSON is passed as Zakira's --data command-line
    # argument. The plain `dnx` shim is `dnx.cmd`, which inherits cmd.exe's
    # ~8191-char command-line limit and fails large payloads with "The command
    # line is too long." Invoking via `dotnet dnx` runs the real .NET host
    # directly (32K CreateProcess limit), matching the workspace convention noted
    # in raindrop-processor.yaml. Limit-DiagnosisLedgerSize still bounds the
    # payload (<=24K) as a belt-and-suspenders guard.
    param([string]$DbPath, [string]$OrchestrationName, $Ledger, [string]$Author, [string]$Reason)
    if ([string]::IsNullOrWhiteSpace($Author)) { $Author = 'diagnosis-lib' }
    if ([string]::IsNullOrWhiteSpace($Reason)) { $Reason = 'diagnosis ledger update' }
    $Ledger = Limit-DiagnosisLedgerSize -Ledger $Ledger
    $data = $Ledger | ConvertTo-Json -Depth 100 -Compress
    $out = & dotnet dnx Zakira.Exchange --yes -- --db $DbPath edit $script:DiagnosisLedgerCategory $OrchestrationName `
        --data $data --author $Author --reason $Reason 2>&1
    if ($LASTEXITCODE -ne 0) {
        $out = & dotnet dnx Zakira.Exchange --yes -- --db $DbPath create $script:DiagnosisLedgerCategory $OrchestrationName `
            --data $data --author $Author --reason $Reason 2>&1
        if ($LASTEXITCODE -ne 0) {
            $text = if ($out -is [array]) { ($out -join "`n") } else { [string]$out }
            throw "Zakira save failed for $script:DiagnosisLedgerCategory/${OrchestrationName}: $text"
        }
    }
}

function New-DiagnosisLedger {
    param([string]$OrchestrationName, [string]$OrchestrationPath, [bool]$OrchestrationFound)
    $now = (Get-Date).ToUniversalTime().ToString('o')
    return [pscustomobject]@{
        schemaVersion      = 1
        orchestrationName  = $OrchestrationName
        orchestrationPath  = $OrchestrationPath
        orchestrationFound = $OrchestrationFound
        status             = 'open'
        createdAt          = $now
        updatedAt          = $now
        lastPublishedHash  = ''
        failures           = @()
    }
}

function Find-DiagnosisFailure {
    param($Ledger, [string]$Signature)
    if ($null -eq $Ledger) { return $null }
    return @($Ledger.failures) | Where-Object { [string]$_.signature -eq [string]$Signature } | Select-Object -First 1
}

function Merge-DiagnosisFailure {
    # Merge a single per-run diagnosis ($Incoming) into $Ledger.failures with
    # dedupe-by-signature + regression handling. Returns the updated ledger.
    #
    # $Incoming shape:
    #   { signature, runId, executionId, orchestrationName, orchestrationPath,
    #     orchestrationFound, failingSteps, rootCause, explanation, fixTarget,
    #     suggestedFix, confidence }
    param($Ledger, $Incoming)

    $now = (Get-Date).ToUniversalTime().ToString('o')
    if ($null -eq $Ledger) {
        $Ledger = New-DiagnosisLedger -OrchestrationName ([string]$Incoming.orchestrationName) `
            -OrchestrationPath ([string]$Incoming.orchestrationPath) `
            -OrchestrationFound ([bool]$Incoming.orchestrationFound)
    }

    $failures = @($Ledger.failures)
    $match = $failures | Where-Object { [string]$_.signature -eq [string]$Incoming.signature } | Select-Object -First 1

    if ($null -eq $match) {
        $newFailure = [pscustomobject]@{
            signature       = [string]$Incoming.signature
            state           = 'open'
            firstSeenAt     = $now
            lastSeenAt      = $now
            occurrences     = 1
            runIds          = @([string]$Incoming.runId)
            executionIds    = @([string]$Incoming.executionId)
            failingSteps    = $Incoming.failingSteps
            rootCause       = [string]$Incoming.rootCause
            explanation     = [string]$Incoming.explanation
            fixPlan         = [string]$Incoming.fixPlan
            fixTarget       = [string]$Incoming.fixTarget
            suggestedFix    = [string]$Incoming.suggestedFix
            confidence      = [string]$Incoming.confidence
            regression      = $false
            regressionCount = 0
            userNotes       = ''
            fixAttempts     = @()
            lastDiagnosisAt = $now
        }
        $failures = @($failures) + $newFailure
    }
    else {
        $known = @($match.runIds) -contains ([string]$Incoming.runId)
        if (-not $known -and -not [string]::IsNullOrWhiteSpace([string]$Incoming.runId)) {
            Set-NoteProp $match 'runIds'       @(@($match.runIds) + [string]$Incoming.runId)
            Set-NoteProp $match 'executionIds' @(@($match.executionIds) + [string]$Incoming.executionId)
            Set-NoteProp $match 'occurrences'  ([int]$match.occurrences + 1)
            Set-NoteProp $match 'lastSeenAt'   $now

            # Regression: the SAME failure recurred after we thought it was
            # handled. Reopen it and escalate; keep fixAttempts so the next
            # diagnosis can avoid repeating a fix that already failed.
            $state = [string]$match.state
            if ($state -eq 'fixed' -or $state -eq 'fix-applied') {
                Set-NoteProp $match 'state'           'regressed'
                Set-NoteProp $match 'regression'      $true
                Set-NoteProp $match 'regressionCount' ([int]$match.regressionCount + 1)
                # Mark the most recent fix attempt as having recurred.
                $attempts = @($match.fixAttempts)
                if ($attempts.Count -gt 0) { Set-NoteProp $attempts[$attempts.Count - 1] 'recurredAfter' $true }
                Set-NoteProp $match 'fixAttempts' $attempts
            }
            # A dismissed failure that recurs stays dismissed (suppressed) but
            # its occurrence counter keeps climbing for later triage.
        }

        # Analysis refresh: keep the existing write-up unless the incoming one is
        # "same or better" - higher confidence, or the existing is empty, or the
        # incoming explanation is materially longer (new evidence).
        $incRank = Get-DiagnosisConfidenceRank ([string]$Incoming.confidence)
        $curRank = Get-DiagnosisConfidenceRank ([string]$match.confidence)
        $incExpl = [string]$Incoming.explanation
        $curExpl = [string]$match.explanation
        $better = (-not [string]::IsNullOrWhiteSpace($incExpl)) -and (
            ($incRank -gt $curRank) -or
            [string]::IsNullOrWhiteSpace($curExpl) -or
            ($incExpl.Length -gt ($curExpl.Length + 40))
        )
        if ($better) {
            Set-NoteProp $match 'rootCause'    ([string]$Incoming.rootCause)
            Set-NoteProp $match 'explanation'  $incExpl
            Set-NoteProp $match 'fixPlan'      ([string]$Incoming.fixPlan)
            Set-NoteProp $match 'fixTarget'    ([string]$Incoming.fixTarget)
            Set-NoteProp $match 'suggestedFix' ([string]$Incoming.suggestedFix)
            Set-NoteProp $match 'confidence'   ([string]$Incoming.confidence)
            Set-NoteProp $match 'failingSteps' $Incoming.failingSteps
        }
        Set-NoteProp $match 'lastDiagnosisAt' $now
    }

    Set-NoteProp $Ledger 'failures' $failures
    if (-not [string]::IsNullOrWhiteSpace([string]$Incoming.orchestrationPath)) {
        Set-NoteProp $Ledger 'orchestrationPath' ([string]$Incoming.orchestrationPath)
    }
    if ($null -ne $Incoming.orchestrationFound) {
        Set-NoteProp $Ledger 'orchestrationFound' ([bool]$Incoming.orchestrationFound)
    }

    $openStates = @('open', 'fix-requested', 'fix-applied', 'regressed')
    $anyOpen = (@($Ledger.failures) | Where-Object { $openStates -contains ([string]$_.state) }).Count -gt 0
    $newStatus = if ($anyOpen) { 'open' } else { 'resolved' }
    Set-NoteProp $Ledger 'status' $newStatus
    Set-NoteProp $Ledger 'updatedAt' $now
    return $Ledger
}

function Set-DiagnosisFailureState {
    # Mutate the lifecycle state of one failure (by signature) in place. Used by
    # the ActionView "Mark fixed" / "Dismiss this failure" button wrappers.
    param($Ledger, [string]$Signature, [string]$State, [string]$UserNotes)
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $match = Find-DiagnosisFailure -Ledger $Ledger -Signature $Signature
    if ($null -eq $match) { return $false }
    Set-NoteProp $match 'state' $State
    if (-not [string]::IsNullOrWhiteSpace($UserNotes)) { Set-NoteProp $match 'userNotes' $UserNotes }
    Set-NoteProp $match 'stateChangedAt' $now
    $openStates = @('open', 'fix-requested', 'fix-applied', 'regressed')
    $anyOpen = (@($Ledger.failures) | Where-Object { $openStates -contains ([string]$_.state) }).Count -gt 0
    $newStatus = if ($anyOpen) { 'open' } else { 'resolved' }
    Set-NoteProp $Ledger 'status' $newStatus
    Set-NoteProp $Ledger 'updatedAt' $now
    return $true
}

function Get-DiagnosisVisibleFailures {
    # The failures rendered as active problem sections on the card.
    param($Ledger)
    if ($null -eq $Ledger) { return @() }
    return @(@($Ledger.failures) | Where-Object { $script:DiagnosisVisibleStates -contains ([string]$_.state) })
}

function Get-DiagnosisVisibleHash {
    # Stable hash of the user-visible failure set, used to decide whether a
    # re-publish is needed. Deliberately EXCLUDES the raw occurrence counter so
    # a known, still-open failure that simply recurred does not re-surface the
    # card every hour. It DOES include state + regressionCount so a regression,
    # a state change (fix applied / marked fixed / dismissed) or a brand-new
    # signature forces a re-publish.
    param($Ledger)
    $visible = Get-DiagnosisVisibleFailures -Ledger $Ledger
    $key = (@($visible | ForEach-Object {
                "$([string]$_.signature):$([string]$_.state):$([int]$_.regressionCount)"
            }) | Sort-Object) -join '|'
    if ([string]::IsNullOrWhiteSpace($key)) { return '' }
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try { $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($key)) }
    finally { $sha.Dispose() }
    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant().Substring(0, 16)
}

function Get-DiagnosisEntryId {
    # Stable ActionView entry id for an orchestration's diagnosis card. Slug +
    # short hash of the exact name avoids slug collisions between similar names.
    param([string]$OrchestrationName)
    $slug = ([regex]::Replace(([string]$OrchestrationName).ToLowerInvariant(), '[^a-z0-9]+', '-')).Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'unnamed' }
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try { $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$OrchestrationName)) }
    finally { $sha.Dispose() }
    $short = ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant().Substring(0, 8)
    return "diagnosis-$slug-$short"
}

function ConvertTo-DiagnosisCellText {
    param([string]$Text, [int]$Max = 300)
    if ($null -eq $Text) { return '' }
    $t = ([string]$Text) -replace '\r?\n', ' '
    $t = $t -replace '\s+', ' '
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max) + ' [more]' }
    return $t.Trim()
}

function New-DiagnosisActionViewEntry {
    # Render the ONE ActionView card for an orchestration's diagnosis ledger.
    # This is the single rendering path used by BOTH the scheduled aggregator
    # and the button wrappers, so what the user sees always matches the ledger.
    #
    # Script paths in action commands are absolute (resolved by the caller) so
    # the buttons - which run OUTSIDE any orchestration context - can find them.
    param(
        $Ledger,
        [string]$DbPath,
        [string]$SharedScriptsDir,
        [string]$ServerUrl,
        [string]$OrchestrationsRoot
    )

    $name    = [string]$Ledger.orchestrationName
    $srcPath = [string]$Ledger.orchestrationPath
    $found   = [bool]$Ledger.orchestrationFound
    $entryId = Get-DiagnosisEntryId $name
    $applyScript = [System.IO.Path]::GetFullPath((Join-Path $SharedScriptsDir 'diagnosis-apply-fix.ps1'))
    $markScript  = [System.IO.Path]::GetFullPath((Join-Path $SharedScriptsDir 'mark-diagnosis-failure.ps1'))

    $commonMarkArgs = @(
        '-DbPath', $DbPath,
        '-SharedScriptsDir', $SharedScriptsDir,
        '-ServerUrl', $ServerUrl,
        '-OrchestrationsRoot', $OrchestrationsRoot
    )

    function New-ApplyFixAction {
        param([string]$Signature)
        return [ordered]@{
            label          = 'Apply Fix'
            style          = 'primary'
            confirmMessage = "Apply the suggested fix to '$name'. This edits the dotfile YAML in your workspace (Orchestra recompiles the internal copy automatically; no git commit). Add notes below to steer the fix."
            parameters     = @(
                [ordered]@{
                    name        = 'notes'
                    label       = 'Notes / comments for the fixer'
                    type        = 'multiline'
                    required    = $false
                    placeholder = 'Optional: constraints or hints, e.g. "raise the timeout, do not reduce frames"'
                    helpText    = 'Passed verbatim into the fix prompt and recorded on the fix attempt.'
                },
                [ordered]@{
                    name    = 'rerun'
                    label   = "Also re-run '$name' after applying the fix"
                    type    = 'boolean'
                    default = 'false'
                }
            )
            command        = [ordered]@{
                type    = 'cli'
                program = 'pwsh'
                args    = @(
                    '-NoProfile', '-NoLogo', '-NonInteractive', '-File', $applyScript,
                    '-OrchestrationName', $name,
                    '-Signature', $Signature,
                    '-Notes', '{{param.notes}}',
                    '-Rerun', '{{param.rerun}}',
                    '-DbPath', $DbPath,
                    '-ServerUrl', $ServerUrl,
                    '-OrchestrationsRoot', $OrchestrationsRoot,
                    '-SharedScriptsDir', $SharedScriptsDir
                )
            }
            onSuccess      = 'keep'
        }
    }

    function New-MarkAction {
        param(
            [string]$Label, [string]$Style, [string]$Action, [string]$Signature,
            [string]$Confirm, [bool]$WithNotes
        )
        $params = @()
        $extra = @()
        if ($WithNotes) {
            $params = @([ordered]@{ name = 'notes'; label = 'Notes (optional)'; type = 'multiline'; required = $false })
            $extra = @('-Notes', '{{param.notes}}')
        }
        $cmdArgs = @('-NoProfile', '-NoLogo', '-NonInteractive', '-File', $markScript,
            '-Action', $Action, '-OrchestrationName', $name, '-Signature', $Signature) + $commonMarkArgs + $extra
        return [ordered]@{
            label          = $Label
            style          = $Style
            confirmMessage = $Confirm
            parameters     = $params
            command        = [ordered]@{ type = 'cli'; program = 'pwsh'; args = $cmdArgs }
            onSuccess      = 'keep'
        }
    }

    $visible = Get-DiagnosisVisibleFailures -Ledger $Ledger
    $anyRegression = (@($visible | Where-Object { [bool]$_.regression }).Count -gt 0)

    $content = New-Object System.Collections.Generic.List[object]

    # Header summary.
    $content.Add([ordered]@{
            type  = 'keyValue'
            label = 'Orchestration'
            pairs = [ordered]@{
                'Orchestration' = $name
                'Source file'   = if ([string]::IsNullOrWhiteSpace($srcPath)) { '(unresolved)' } else { $srcPath }
                'Open failures' = "$(@($visible).Count)"
                'Tracked total' = "$(@($Ledger.failures).Count)"
                'Status'        = [string]$Ledger.status
            }
        }) | Out-Null

    $failIndex = 0
    foreach ($f in $visible) {
        $failIndex++
        $sig   = [string]$f.signature
        $state = [string]$f.state
        $primaryStep = ''
        if (@($f.failingSteps).Count -gt 0) { $primaryStep = [string](@($f.failingSteps)[0].name) }
        $secTitle = "Failure $failIndex" + $(if ($primaryStep) { " - $primaryStep" } else { '' })
        $badge = $state
        if ([int]$f.occurrences -gt 1) { $badge = "$state x$([int]$f.occurrences)" }
        if ([bool]$f.regression) { $badge = "REGRESSION x$([int]$f.regressionCount)" }

        $sec = New-Object System.Collections.Generic.List[object]

        $expl = [string]$f.explanation
        if ($expl.Length -gt 1500) { $expl = $expl.Substring(0, 1500) + ' [more in ledger]' }
        $rc = [string]$f.rootCause
        $mdRoot = "**Root cause:** $rc`n`n**Explanation:** $expl"
        if ([bool]$f.regression) {
            $mdRoot = "> This failure recurred AFTER a fix was applied ($([int]$f.regressionCount)x). The diagnosis below accounts for the prior attempt(s).`n`n" + $mdRoot
        }
        $sec.Add([ordered]@{ type = 'markdown'; body = $mdRoot }) | Out-Null

        # Plain-language plan of what the fix will do, BEFORE the code snippet.
        $plan = [string]$f.fixPlan
        if (-not [string]::IsNullOrWhiteSpace($plan)) {
            if ($plan.Length -gt 1200) { $plan = $plan.Substring(0, 1200) + ' [more in ledger]' }
            $sec.Add([ordered]@{ type = 'markdown'; body = "### What the fix will do`n`n$plan" }) | Out-Null
        }

        $fix = [string]$f.suggestedFix
        if (-not [string]::IsNullOrWhiteSpace($fix)) {
            if ($fix.Length -gt 2000) { $fix = $fix.Substring(0, 2000) + "`n# [more in ledger]" }
            $sec.Add([ordered]@{ type = 'code'; label = 'Suggested fix (code)'; language = 'yaml'; body = $fix }) | Out-Null
        }

        $rows = @()
        foreach ($fs in @($f.failingSteps)) {
            $rows += , @(
                (ConvertTo-DiagnosisCellText ([string]$fs.name) 80),
                (ConvertTo-DiagnosisCellText ([string]$fs.errorCategory) 40),
                (ConvertTo-DiagnosisCellText ([string]$fs.error) 400)
            )
        }
        if ($rows.Count -gt 0) {
            $sec.Add([ordered]@{ type = 'table'; label = 'Failing steps'; columns = @('Step', 'Category', 'Error'); rows = $rows }) | Out-Null
        }

        $sec.Add([ordered]@{
                type  = 'keyValue'
                pairs = [ordered]@{
                    'Signature'   = $sig
                    'Fix target'  = [string]$f.fixTarget
                    'Confidence'  = [string]$f.confidence
                    'Occurrences' = "$([int]$f.occurrences)"
                    'First seen'  = [string]$f.firstSeenAt
                    'Last seen'   = [string]$f.lastSeenAt
                }
            }) | Out-Null

        $attempts = @($f.fixAttempts)
        if ($attempts.Count -gt 0) {
            $last = $attempts[$attempts.Count - 1]
            $histLines = New-Object System.Collections.Generic.List[string]
            $histLines.Add("**Fix attempts:** $($attempts.Count)") | Out-Null
            $histLines.Add("- Last attempt: $([string]$last.at) - outcome: $([string]$last.outcome)") | Out-Null
            if (-not [string]::IsNullOrWhiteSpace([string]$last.userNotes)) { $histLines.Add("- Your notes: $([string]$last.userNotes)") | Out-Null }
            if (-not [string]::IsNullOrWhiteSpace([string]$last.backup)) { $histLines.Add("- Backup: $([string]$last.backup)") | Out-Null }
            if ([bool]$last.recurredAfter) { $histLines.Add('- The failure RECURRED after this attempt.') | Out-Null }
            $sec.Add([ordered]@{ type = 'markdown'; body = ($histLines -join "`n") }) | Out-Null
        }

        # Section-scoped actions vary by lifecycle state.
        $secActions = New-Object System.Collections.Generic.List[object]
        if ($state -eq 'fix-applied') {
            [void]$secActions.Add((New-MarkAction -Label "Re-run '$name'" -Style 'primary' -Action 'rerun' -Signature $sig -Confirm "Re-run '$name' now to verify the applied fix?" -WithNotes $false))
            [void]$secActions.Add((New-MarkAction -Label 'Revert' -Style 'danger' -Action 'revert' -Signature $sig -Confirm "Restore '$name' from the pre-fix backup?" -WithNotes $false))
        }
        else {
            if ($found -and ([string]$f.fixTarget -eq 'orchestration-yaml')) {
                [void]$secActions.Add((New-ApplyFixAction -Signature $sig))
            }
        }
        [void]$secActions.Add((New-MarkAction -Label 'Mark fixed' -Style 'success' -Action 'fixed' -Signature $sig -Confirm "Mark this failure of '$name' as fixed? (It will re-open automatically as a regression if it recurs.)" -WithNotes $true))
        [void]$secActions.Add((New-MarkAction -Label 'Dismiss this failure' -Style 'default' -Action 'dismissed' -Signature $sig -Confirm 'Dismiss this failure? It will be suppressed even if it recurs.' -WithNotes $false))

        $content.Add([ordered]@{
                type            = 'section'
                title           = $secTitle
                badge           = $badge
                defaultCollapsed = $false
                content         = $sec.ToArray()
                actions         = $secActions.ToArray()
            }) | Out-Null
    }

    # Collapsed history of resolved/dismissed failures.
    $history = @(@($Ledger.failures) | Where-Object { $script:DiagnosisVisibleStates -notcontains ([string]$_.state) })
    if ($history.Count -gt 0) {
        $hrows = @()
        foreach ($h in $history) {
            $primaryStep = ''
            if (@($h.failingSteps).Count -gt 0) { $primaryStep = [string](@($h.failingSteps)[0].name) }
            $hrows += , @(
                (ConvertTo-DiagnosisCellText $primaryStep 80),
                (ConvertTo-DiagnosisCellText ([string]$h.state) 20),
                (ConvertTo-DiagnosisCellText ([string]$h.rootCause) 200),
                "$([int]$h.occurrences)"
            )
        }
        $content.Add([ordered]@{
                type            = 'section'
                title           = 'Resolved / dismissed history'
                badge           = "$($history.Count)"
                defaultCollapsed = $true
                content         = @(
                    [ordered]@{ type = 'table'; columns = @('Step', 'State', 'Root cause', 'Seen'); rows = $hrows }
                )
            }) | Out-Null
    }

    $openCount = @($visible).Count
    $title = "Diagnosis: $name - $openCount open failure(s)"
    if ($anyRegression) { $title += ' (regression)' }
    $severity = if ($anyRegression) { 'critical' } else { 'high' }

    return [ordered]@{
        schemaVersion = '1'
        id            = $entryId
        type          = 'failed-orchestration-diagnosis'
        source        = 'diagnose-orchestration-failures'
        title         = $title
        subtitle      = "$(@($Ledger.failures).Count) distinct failure(s) tracked - status: $([string]$Ledger.status)"
        severity      = $severity
        icon          = 'stethoscope'
        tags          = @('diagnostics', 'self-healing', 'orchestra', $name, $entryId)
        groupId       = $entryId
        pinned        = $anyRegression
        content       = $content.ToArray()
    }
}

function Submit-DiagnosisEntry {
    # Write the entry to a temp file and upsert it via ActionView.Cli. The stable
    # `id` means re-submitting updates the same card in place.
    param($Entry)
    $json = $Entry | ConvertTo-Json -Depth 60
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('diag-entry-' + [guid]::NewGuid().ToString('N') + '.json')
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmp, $json, $enc)
    try {
        $out = & dnx ActionView.Cli --yes -- add --file $tmp --wait 2>&1
        if ($LASTEXITCODE -ne 0) {
            $text = if ($out -is [array]) { ($out -join "`n") } else { [string]$out }
            throw "ActionView.Cli add failed (exit $LASTEXITCODE): $text"
        }
        return ($out -join "`n")
    }
    finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
}

function Publish-DiagnosisCard {
    # Render + submit the card, then stamp lastPublishedHash and persist. Returns
    # the CLI output. Caller decides WHETHER to publish (see Get-DiagnosisVisibleHash).
    param(
        $Ledger, [string]$DbPath, [string]$SharedScriptsDir,
        [string]$ServerUrl, [string]$OrchestrationsRoot, [string]$Author
    )
    $entry = New-DiagnosisActionViewEntry -Ledger $Ledger -DbPath $DbPath `
        -SharedScriptsDir $SharedScriptsDir -ServerUrl $ServerUrl -OrchestrationsRoot $OrchestrationsRoot
    $res = Submit-DiagnosisEntry -Entry $entry
    Set-NoteProp $Ledger 'lastPublishedHash' (Get-DiagnosisVisibleHash $Ledger)
    Set-NoteProp $Ledger 'lastPublishedAt' ((Get-Date).ToUniversalTime().ToString('o'))
    Save-DiagnosisLedger -DbPath $DbPath -OrchestrationName ([string]$Ledger.orchestrationName) `
        -Ledger $Ledger -Author $Author -Reason 'publish diagnosis card'
    return $res
}

function Clear-DiagnosisCard {
    # Dismiss (archive) the card when nothing is visible anymore. Best-effort.
    param($Ledger, [string]$DbPath, [string]$Author)
    $id = Get-DiagnosisEntryId ([string]$Ledger.orchestrationName)
    $out = & dnx ActionView.Cli --yes -- dismiss $id 2>&1
    Set-NoteProp $Ledger 'lastPublishedHash' ''
    Save-DiagnosisLedger -DbPath $DbPath -OrchestrationName ([string]$Ledger.orchestrationName) `
        -Ledger $Ledger -Author $Author -Reason 'clear resolved diagnosis card'
    return ($out -join "`n")
}

function Invoke-OrchestraOrchestration {
    # Trigger an Orchestra orchestration from OUTSIDE an orchestration context
    # (i.e. from an ActionView button wrapper or a Script step). The Orchestra
    # CLI is a .NET tool run via `dnx` (like npx for .NET: auto-installs then
    # executes without a global install), which is why `orchestra` is not on
    # PATH. Invocation shape mirrors the rest of this workspace:
    #     dnx Orchestra --yes -- run <name> --param k=v ... --server <url> --by <id>
    #
    # By default this is FIRE-AND-FORGET (detached) so an ActionView button
    # returns immediately - the triggered orchestration re-publishes the card
    # when it finishes. Pass -Wait to run synchronously and capture the result.
    #
    # Returns { method, ok, launched, output }.
    param(
        [string]$Name,
        [hashtable]$Parameters = @{},
        [string]$ServerUrl = '',
        [string]$By = 'actionview-button',
        [switch]$Wait
    )
    $toolArgs = @('Orchestra', '--yes', '--', 'run', $Name)
    foreach ($k in $Parameters.Keys) { $toolArgs += @('--param', ("$k=" + [string]$Parameters[$k])) }
    if (-not [string]::IsNullOrWhiteSpace($ServerUrl)) { $toolArgs += @('--server', $ServerUrl) }
    if (-not [string]::IsNullOrWhiteSpace($By)) { $toolArgs += @('--by', $By) }
    $toolArgs += '--quiet'

    if ($Wait) {
        # The call operator passes each array element as a distinct argv, so
        # values with spaces (paths) survive without manual quoting.
        $out = & dnx @toolArgs 2>&1
        $code = $LASTEXITCODE
        return [pscustomobject]@{ method = 'dnx'; ok = ($code -eq 0); launched = $true; output = (@($out) -join "`n") }
    }

    # Detached launch. Manually double-quote any argument containing whitespace
    # (the values here - identifiers, hex signatures, true/false, file paths -
    # never contain embedded double-quotes). Start-Process without -Wait returns
    # immediately and the child keeps running after this script exits.
    $argString = (($toolArgs | ForEach-Object {
                $a = [string]$_
                if ($a -match '\s') { '"' + $a + '"' } else { $a }
            }) -join ' ')
    try {
        Start-Process -FilePath 'dnx' -ArgumentList $argString -WindowStyle Hidden | Out-Null
        return [pscustomobject]@{ method = 'dnx'; ok = $true; launched = $true; output = "launched: dnx Orchestra run $Name" }
    }
    catch {
        return [pscustomobject]@{ method = 'dnx'; ok = $false; launched = $false; output = "Failed to launch dnx Orchestra run ${Name}: $($_.Exception.Message)" }
    }
}
