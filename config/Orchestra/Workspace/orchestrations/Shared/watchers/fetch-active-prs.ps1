#Requires -Version 7.0
<#
.SYNOPSIS
    Orchestra watcher fetcher (protocol v1): the configured user's active Azure DevOps pull
    requests - either the ones they authored (`mode: authored`) or the ones they are asked
    to review (`mode: assigned`) - each carrying a change token that moves whenever review
    activity happens.

.DESCRIPTION
    Deterministic port of `pr-comment-tracker.fetch-my-prs` and
    `pr-auto-reviewer.fetch-assigned-prs` + `filter-prs`. Enumerates every enabled repository
    from the private repo list (Shared/scripts/pr-repos.ps1 -> $env:ONEDRIVE/.../repos.json),
    lists active PRs per repository through the git REST API (`az rest`, no identity lookup,
    no azure-devops extension) and filters client-side.

    Why a change token: the old trackers re-dispatched EVERY active PR every hour and let the
    dispatcher's LLM work out whether anything happened. The watcher instead fires only when
    the token changes. The token folds in:
      * lastMergeSourceCommitId  - a new iteration was pushed
      * isDraft                  - draft -> published
      * latestActivity           - newest non-system comment written by someone OTHER than
                                   the configured user (a reviewer commented on my PR, or a
                                   PR author replied to a review thread), from
                                   .../pullrequests/{id}/threads
    The subscribing dispatcher still performs its own Zakira/PowerReview state checks, so a
    token change that turns out to need no work costs one dispatcher run and nothing else.

    stdin  (from Orchestra): { protocolVersion, watcher, cursor, subscribers, config }
    stdout (to Orchestra):   { protocolVersion: "1", items: [ <pr>... ], cursor }

    config (fetch.config):
      mode                   "authored" | "assigned"
      userUniqueName         "MoaidHathot@microsoft.com"
      userDisplayName        "Moaid Hathot"   (assigned mode drops PRs created by this display name too)
      includeThreadActivity  true             (set false to skip the per-PR threads call)

    Item shape is a superset of what both old trackers emitted (`prData` for the dispatchers):
      id, title, status, isDraft, createdBy, createdByUniqueName, creationDate, sourceRefName,
      targetRefName, reviewers[] (display names), url, apiUrl, lastMergeSourceCommitId,
      organization, project, repository, repoPath, latestActivity, changeToken
#>
$ErrorActionPreference = 'Stop'

$request = [Console]::In.ReadToEnd() | ConvertFrom-Json -Depth 20
$config = $request.config
if ($null -eq $config) { throw 'fetch.config is required (mode, userUniqueName, userDisplayName).' }

$mode = ([string]$config.mode).ToLowerInvariant()
if ($mode -notin @('authored', 'assigned')) { throw "fetch.config.mode must be 'authored' or 'assigned' (got '$mode')." }
$userUnique = [string]$config.userUniqueName
$userDisplay = [string]$config.userDisplayName
if ([string]::IsNullOrWhiteSpace($userUnique)) { throw 'fetch.config.userUniqueName is required.' }
$includeThreadActivity = $true
if ($config.PSObject.Properties['includeThreadActivity'] -and $null -ne $config.includeThreadActivity) {
    $includeThreadActivity = [bool]$config.includeThreadActivity
}

try { Get-Command az -ErrorAction Stop | Out-Null } catch {
    throw 'az CLI is not available on PATH; cannot fetch pull requests.'
}
$env:PYTHONIOENCODING = 'utf-8'

. (Join-Path $PSScriptRoot '..\scripts\pr-repos.ps1')

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

# ---- Repository-ID cache (same file the old trackers used; repo IDs are effectively immutable) ----
$cacheRoot = Join-Path $env:LOCALAPPDATA 'Orchestra\pr-auto-reviewer'
if (-not (Test-Path $cacheRoot)) { New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null }
$cachePath = Join-Path $cacheRoot 'repo-cache.json'
$cacheMaxAgeDays = 30
$cacheMap = @{}
if (Test-Path $cachePath) {
    try {
        $cacheDoc = Get-Content $cachePath -Raw | ConvertFrom-Json
        if ($cacheDoc -and $cacheDoc.PSObject.Properties['entries']) {
            foreach ($prop in $cacheDoc.entries.PSObject.Properties) { $cacheMap[$prop.Name] = $prop.Value }
        } elseif ($cacheDoc -and $cacheDoc.PSObject.Properties['key']) {
            $cacheMap[[string]$cacheDoc.key] = $cacheDoc
        }
    } catch { $cacheMap = @{} }
}
$cacheDirty = $false

function Get-RepositoryId {
    param([Parameter(Mandatory)]$Target)
    $cacheKey = "$($Target.organization)|$($Target.project)|$($Target.repository)"
    if ($cacheMap.ContainsKey($cacheKey)) {
        $cached = $cacheMap[$cacheKey]
        try {
            if ($cached -and $cached.repositoryId -and $cached.cachedAt) {
                if (((Get-Date) - [datetime]::Parse([string]$cached.cachedAt)).TotalDays -lt $cacheMaxAgeDays) {
                    return [string]$cached.repositoryId
                }
            }
        } catch { }
    }

    $repoObj = Invoke-AzRestJson -Uri "$($Target.orgUrl)/$($Target.project)/_apis/git/repositories/$($Target.repository)" `
        -UriParameters @('api-version=7.1-preview.1') -What "repository lookup '$($Target.project)/$($Target.repository)'"
    $id = [string]$repoObj.id
    if ([string]::IsNullOrWhiteSpace($id)) { throw "Could not resolve repository ID for '$($Target.project)/$($Target.repository)'." }
    $script:cacheMap[$cacheKey] = [pscustomobject]@{ key = $cacheKey; repositoryId = $id; cachedAt = (Get-Date).ToString('o') }
    $script:cacheDirty = $true
    return $id
}

function Get-LatestOtherActivity {
    # Newest non-system comment on the PR written by someone other than the configured user.
    param([Parameter(Mandatory)][string]$ThreadsUri)
    $envelope = Invoke-AzRestJson -Uri $ThreadsUri -UriParameters @('api-version=7.1-preview.1') -What 'threads list'
    $latest = $null
    foreach ($thread in @($envelope.value)) {
        if ($null -eq $thread) { continue }
        foreach ($comment in @($thread.comments)) {
            if ($null -eq $comment) { continue }
            if ([string]$comment.commentType -eq 'system') { continue }
            if ($comment.isDeleted -eq $true) { continue }
            $author = if ($null -ne $comment.author) { [string]$comment.author.uniqueName } else { '' }
            if ([string]::Equals($author, $userUnique, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $stamp = $comment.lastUpdatedDate
            if ($null -eq $stamp) { $stamp = $comment.publishedDate }
            $ts = $null
            try { $ts = [datetimeoffset]::Parse([string](ConvertTo-IsoUtcString $stamp)) } catch { $ts = $null }
            if ($null -ne $ts -and ($null -eq $latest -or $ts -gt $latest)) { $latest = $ts }
        }
    }
    if ($null -eq $latest) { return '' }
    return $latest.UtcDateTime.ToString('o')
}

$items = [System.Collections.Generic.List[object]]::new()

# Throws if repos.json is missing/malformed or a configured clone is absent - intentional,
# a partial repo list would silently stop watching whichever repos went missing.
foreach ($target in @(Get-PrRepoTargets)) {
    $repoId = Get-RepositoryId -Target $target
    $listBase = "$($target.orgUrl)/$($target.project)/_apis/git/repositories/$repoId/pullrequests"
    $envelope = Invoke-AzRestJson -Uri $listBase -UriParameters @('api-version=7.1-preview.1', 'searchCriteria.status=active', '$top=200') `
        -What "pullrequests list '$($target.project)/$($target.repository)'"
    $allActive = if ($null -ne $envelope.value) { $envelope.value } else { @() }

    foreach ($p in @($allActive)) {
        if ($null -eq $p) { continue }
        $createdByName = ''
        $createdByUnique = ''
        if ($null -ne $p.createdBy) {
            $createdByName = [string]$p.createdBy.displayName
            $createdByUnique = [string]$p.createdBy.uniqueName
        }

        $keep = $false
        if ($mode -eq 'authored') {
            # uniqueName only - Azure DevOps can hold several identities sharing a display name.
            $keep = [string]::Equals($createdByUnique, $userUnique, [System.StringComparison]::OrdinalIgnoreCase)
        } else {
            $isReviewer = $null -ne $p.reviewers -and @($p.reviewers | Where-Object {
                    $_ -and $_.uniqueName -and [string]::Equals([string]$_.uniqueName, $userUnique, [System.StringComparison]::OrdinalIgnoreCase)
                }).Count -gt 0
            $isOwn = [string]::Equals($createdByUnique, $userUnique, [System.StringComparison]::OrdinalIgnoreCase) -or
                (-not [string]::IsNullOrWhiteSpace($userDisplay) -and [string]::Equals($createdByName, $userDisplay, [System.StringComparison]::OrdinalIgnoreCase))
            $keep = $isReviewer -and -not $isOwn
        }
        if (-not $keep) { continue }

        $prId = [int]$p.pullRequestId
        $lastCommit = ''
        if ($null -ne $p.lastMergeSourceCommit -and $p.lastMergeSourceCommit.commitId) { $lastCommit = [string]$p.lastMergeSourceCommit.commitId }
        $isDraftVal = $false
        if ($null -ne $p.isDraft) { $isDraftVal = [bool]$p.isDraft }
        $reviewerNames = @()
        if ($null -ne $p.reviewers) {
            $reviewerNames = @(@($p.reviewers) | ForEach-Object { [string]$_.displayName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        $latestActivity = ''
        if ($includeThreadActivity) {
            $latestActivity = Get-LatestOtherActivity -ThreadsUri "$listBase/$prId/threads"
        }

        $webUrl = "$($target.prUrlPrefix)$prId"
        [void]$items.Add([ordered]@{
            id                      = $prId
            title                   = [string]$p.title
            status                  = [string]$p.status
            isDraft                 = $isDraftVal
            createdBy               = $createdByName
            createdByUniqueName     = $createdByUnique
            creationDate            = ConvertTo-IsoUtcString $p.creationDate
            sourceRefName           = [string]$p.sourceRefName
            targetRefName           = [string]$p.targetRefName
            reviewers               = $reviewerNames
            url                     = $webUrl
            apiUrl                  = [string]$p.url
            lastMergeSourceCommitId = $lastCommit
            organization            = $target.organization
            project                 = $target.project
            repository              = $target.repository
            repoPath                = $target.repoPath
            latestActivity          = $latestActivity
            changeToken             = "$lastCommit|$isDraftVal|$latestActivity"
        })
    }
}

if ($cacheDirty) {
    $entriesObj = [ordered]@{}
    foreach ($k in $cacheMap.Keys) { $entriesObj[$k] = $cacheMap[$k] }
    [pscustomobject]@{ version = 2; entries = [pscustomobject]$entriesObj } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cachePath -Encoding utf8
}

$response = [ordered]@{
    protocolVersion = '1'
    items           = $items.ToArray()
    cursor          = $request.cursor
    diagnostics     = [ordered]@{ message = "$($items.Count) active $mode PR(s)" }
}
[Console]::Out.Write((ConvertTo-Json -InputObject $response -Depth 100 -Compress))
exit 0
