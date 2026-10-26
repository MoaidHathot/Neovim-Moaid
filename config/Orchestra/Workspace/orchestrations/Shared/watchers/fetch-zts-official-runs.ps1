#Requires -Version 7.0
<#
.SYNOPSIS
    Orchestra watcher fetcher (protocol v1): recent ZTS-Official CI/CD pipeline runs that
    are relevant to the configured user.

.DESCRIPTION
    Deterministic port of the `discover-ci-runs` / `discover-cd-runs` / `pre-filter-runs`
    (relevance part) steps of the retired `zts-official-pipeline-auto-discoverer`
    orchestration. Lists the newest builds of each configured definition through the
    Azure DevOps Build REST API (`az rest`, no azure-devops extension needed) and keeps
    the runs requested by, or triggered by a pull request authored by, the target user.

    Deduplication is Orchestra's job: the watcher's `dedup.key` is `{{item.recordKey}}`
    (`ci:<runId>` / `cd:<runId>`), which replaces the hand-rolled `auto-discovered-claims`
    seen-set the old orchestration kept in Zakira. This script has no side effects.

    stdin  (from Orchestra): { protocolVersion, watcher, cursor, subscribers, config }
    stdout (to Orchestra):   { protocolVersion: "1", items: [ <run>... ], cursor }

    config (fetch.config in orchestra.watchers.json):
      organization           "msazure"
      project                "One"
      definitions            [ { id: "384921", name: "ZTS-Official", kind: "ci" }, ... ]
      targetUserUniqueName   "moaidhathot@microsoft.com"
      targetUserDisplayName  "Moaid Hathot"
      top                    25   (builds per definition, newest first)

    Each item is the same run object the dispatcher already understands as
    `trackedRunJson`, plus `recordKey` and `id`.
#>
$ErrorActionPreference = 'Stop'

$request = [Console]::In.ReadToEnd() | ConvertFrom-Json -Depth 20
$config = $request.config
if ($null -eq $config) { throw 'fetch.config is required (organization, project, definitions, targetUserUniqueName).' }

$organization = [string]$config.organization
$project = [string]$config.project
$targetUniqueLower = ([string]$config.targetUserUniqueName).ToLowerInvariant()
$targetDisplay = [string]$config.targetUserDisplayName
$top = if ($config.PSObject.Properties['top'] -and $config.top) { [int]$config.top } else { 25 }
$definitions = @($config.definitions)
if ([string]::IsNullOrWhiteSpace($organization) -or [string]::IsNullOrWhiteSpace($project) -or $definitions.Count -eq 0) {
    throw 'fetch.config must set organization, project and at least one definition.'
}

try { Get-Command az -ErrorAction Stop | Out-Null } catch {
    throw 'az CLI is not available on PATH; cannot discover pipeline runs.'
}
# az's embedded Python defaults to cp1252 on Windows and dies on non-ASCII display names.
$env:PYTHONIOENCODING = 'utf-8'

$orgUrl = "https://dev.azure.com/$organization"
# Azure DevOps OAuth resource ID -- the constant az CLI uses for ADO calls.
$adoResource = '499b84ac-1321-427f-aa17-267ca6975798'

function ConvertTo-IsoUtcString {
    param($value)
    if ($null -eq $value) { return '' }
    if ($value -is [datetime]) { return ([datetime]$value).ToUniversalTime().ToString('o') }
    if ($value -is [datetimeoffset]) { return ([datetimeoffset]$value).UtcDateTime.ToString('o') }
    return [string]$value
}

function Invoke-AzRestJson {
    param([Parameter(Mandatory)][string]$Uri, [string[]]$UriParameters = @(), [string]$What = 'request')
    # stderr goes to a temp file: az emits cp1252 warnings on stderr that would corrupt the JSON if merged.
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $raw = & az rest --method get --uri $Uri --uri-parameters @UriParameters --resource $adoResource -o json 2>$stderrFile
        if ($LASTEXITCODE -ne 0) {
            $stderr = Get-Content -Raw -LiteralPath $stderrFile -ErrorAction SilentlyContinue
            throw "az rest $What failed with exit $LASTEXITCODE. stderr: $stderr"
        }
        return (($raw | ForEach-Object { [string]$_ }) -join "`n") | ConvertFrom-Json -Depth 100
    } finally {
        Remove-Item -LiteralPath $stderrFile -ErrorAction SilentlyContinue
    }
}

$items = [System.Collections.Generic.List[object]]::new()

foreach ($definition in $definitions) {
    $definitionIdRaw = [string]$definition.id
    $definitionName = [string]$definition.name
    $kind = ([string]$definition.kind).ToLowerInvariant()
    if ($kind -notin @('ci', 'cd')) { throw "definition '$definitionName' has kind '$kind'; expected 'ci' or 'cd'." }
    $definitionIdInt = [int]$definitionIdRaw

    # `$top` is single-quoted so PowerShell does not interpolate it; --uri-parameters lets az
    # re-encode the query (a literal `&` in --uri breaks because az.cmd goes through cmd.exe).
    $envelope = Invoke-AzRestJson -Uri "$orgUrl/$project/_apis/build/builds" `
        -UriParameters @('api-version=7.1-preview.7', "definitions=$definitionIdRaw", 'queryOrder=queueTimeDescending', "`$top=$top") `
        -What "builds list ($kind def $definitionIdRaw)"
    $list = if ($null -ne $envelope.value) { $envelope.value } else { @() }

    foreach ($b in @($list)) {
        if ($null -eq $b) { continue }

        $resolvedDefId = $definitionIdInt
        if ($null -ne $b.definition -and $null -ne $b.definition.id) { $resolvedDefId = [int]$b.definition.id }
        $resolvedDefName = $definitionName
        if ($null -ne $b.definition -and $b.definition.name) { $resolvedDefName = [string]$b.definition.name }

        $requestedForObj = $null
        if ($null -ne $b.requestedFor) {
            $requestedForObj = [ordered]@{
                displayName = [string]$b.requestedFor.displayName
                uniqueName  = [string]$b.requestedFor.uniqueName
                id          = [string]$b.requestedFor.id
            }
        }
        $requestedByObj = $null
        if ($null -ne $b.requestedBy) {
            $requestedByObj = [ordered]@{
                displayName = [string]$b.requestedBy.displayName
                uniqueName  = [string]$b.requestedBy.uniqueName
                id          = [string]$b.requestedBy.id
            }
        }

        $pullRequests = @()
        $triggerInfo = $b.triggerInfo
        if ($null -ne $triggerInfo) {
            $prNumber = $null
            try { $prNumber = $triggerInfo.'pr.number' } catch { $prNumber = $null }
            if (-not $prNumber) { try { $prNumber = $triggerInfo.'pr.id' } catch { $prNumber = $null } }
            if ($prNumber) {
                $pullRequests = @([ordered]@{
                    id           = [string]$prNumber
                    title        = [string]$triggerInfo.'pr.title'
                    sourceBranch = [string]$triggerInfo.'pr.sourceBranch'
                    targetBranch = [string]$triggerInfo.'pr.targetBranch'
                    draft        = [string]$triggerInfo.'pr.draft'
                    providerName = [string]$triggerInfo.'pr.providerName'
                    author       = [ordered]@{
                        displayName = [string]$triggerInfo.'pr.senderName'
                        uniqueName  = [string]$triggerInfo.'pr.senderEmail'
                    }
                })
            }
        }

        # ---- Relevance filter (identical to the old pre-filter-runs step) ----
        $reqUnique = if ($requestedForObj) { $requestedForObj.uniqueName } else { '' }
        $reqDisplay = if ($requestedForObj) { $requestedForObj.displayName } else { '' }
        $matchByRequesterUnique = (-not [string]::IsNullOrWhiteSpace($reqUnique) -and $reqUnique.ToLowerInvariant() -eq $targetUniqueLower)
        $matchByRequesterDisplay = (-not [string]::IsNullOrWhiteSpace($reqDisplay) -and -not [string]::IsNullOrWhiteSpace($targetDisplay) -and [string]::Equals($reqDisplay, $targetDisplay, [System.StringComparison]::OrdinalIgnoreCase))
        $prUnique = if ($pullRequests.Count -gt 0) { [string]$pullRequests[0].author.uniqueName } else { '' }
        $matchByPr = (-not [string]::IsNullOrWhiteSpace($prUnique) -and $prUnique.ToLowerInvariant() -eq $targetUniqueLower)
        if (-not ($matchByRequesterUnique -or $matchByRequesterDisplay -or $matchByPr)) { continue }

        $runId = [string]$b.id
        $queueTimeIso = ConvertTo-IsoUtcString $b.queueTime
        $finishTimeIso = ConvertTo-IsoUtcString $b.finishTime
        $recordKey = "${kind}:$runId"

        [void]$items.Add([ordered]@{
            id                 = $recordKey
            recordKey          = $recordKey
            pipelineType       = $kind
            definitionId       = $resolvedDefId
            definitionName     = $resolvedDefName
            runId              = $runId
            buildNumber        = [string]$b.buildNumber
            status             = [string]$b.status
            result             = [string]$b.result
            queueTime          = $queueTimeIso
            startTime          = ConvertTo-IsoUtcString $b.startTime
            finishTime         = $finishTimeIso
            requestedFor       = $requestedForObj
            requestedBy        = $requestedByObj
            reason             = [string]$b.reason
            sourceBranch       = [string]$b.sourceBranch
            sourceVersion      = [string]$b.sourceVersion
            triggeredByBuild   = $null
            triggeredByRelease = $null
            pullRequests       = $pullRequests
            commits            = @()
            webUrl             = "https://dev.azure.com/$organization/$project/_build/results?buildId=$runId"
            rawEvidence        = "build $runId $($b.status)/$($b.result) queued=$queueTimeIso finished=$finishTimeIso reason=$($b.reason)"
        })
    }
}

$response = [ordered]@{
    protocolVersion = '1'
    items           = $items.ToArray()
    cursor          = $request.cursor
    diagnostics     = [ordered]@{ message = "$($items.Count) relevant run(s) across $($definitions.Count) definition(s)" }
}
[Console]::Out.Write((ConvertTo-Json -InputObject $response -Depth 100 -Compress))
exit 0
