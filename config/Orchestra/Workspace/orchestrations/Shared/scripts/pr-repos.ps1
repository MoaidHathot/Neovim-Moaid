# pr-repos.ps1
#
# Single source of truth for "which repositories does the PR-review
# pipeline operate on, and where does each one live on disk?".
#
# WHY THIS EXISTS
# ---------------
# The PR orchestrations used to hardcode `organization/project/repository`
# as YAML `variables:` in every file (7 copies of the same triple). That
# made the pipeline single-repo by construction, and it published the repo
# names into a public dotfiles repository.
#
# The repository list now lives OUTSIDE this repository, in OneDrive:
#
#     $env:ONEDRIVE\Orchestra\Orchestrations\PullRequests\repos.json
#
# This file therefore contains NO repository names or URLs and is safe to
# publish. If the config is missing we throw loudly rather than silently
# degrading to a default repo -- a silent fallback would make PRs from an
# unmapped repository resolve against the WRONG local checkout (see
# Resolve-PrRepoPath below for why that is dangerous).
#
# CONFIG SCHEMA
# -------------
#   {
#     "version": 1,
#     "organization": "<ado-org>",         // default for every entry
#     "project": "<ado-project>",          // default for every entry
#     "repositories": [
#       {
#         "repository": "<ado-repo-name>", // must match the PR URL segment
#         "repoPath":   "<local clone>",   // dedicated PowerReview clone
#         "enabled":    true,              // optional, default true
#         "organization": "...",           // optional per-entry override
#         "project": "..."                 // optional per-entry override
#       }
#     ]
#   }
#
# `repoPath` must point at a DEDICATED clone parked on the default branch,
# not at your day-to-day working clone. PowerReview fetches PR branches and
# registers/removes linked worktrees in whatever repo it is given; pointing
# it at a working clone leaves residue behind whenever a review crashes.
#
# USAGE
# -----
# Dot-source it; this file defines functions and has no side effects at
# load time:
#
#     . "$PSScriptRoot/../Shared/scripts/pr-repos.ps1"
#     $targets = Get-PrRepoTargets
#     $repoPath = Resolve-PrRepoPath -PrUrl $prUrl
#
# From an Orchestra inline `script:` step the path is templated in:
#
#     . '{{orchestration.sourceDirectory}}/../Shared/scripts/pr-repos.ps1'

# Deliberately does NOT call Set-StrictMode. This file is dot-sourced into
# other scripts, and Set-StrictMode applies to the CALLER's scope -- turning it
# on here would silently change the semantics of every consuming step (e.g.
# making `$obj.missingProperty` throw instead of returning $null). Property
# access below is defensive via PSObject.Properties instead.

# Module-scoped memo so a step that calls Resolve-PrRepoPath in a loop does
# not re-read and re-parse the JSON for every PR.
$script:PrRepoConfigCache = $null

function Get-PrRepoConfigPath {
    <#
    .SYNOPSIS
        Absolute path to the private repository-list config.
    .DESCRIPTION
        Resolved from $env:ONEDRIVE. Throws if OneDrive is not configured
        or the file is absent -- callers must not run with a partial repo
        list, because a partial list silently stops reviewing some repos.
    #>
    [CmdletBinding()]
    param()

    $oneDrive = [string]$env:ONEDRIVE
    if ([string]::IsNullOrWhiteSpace($oneDrive)) {
        throw "ONEDRIVE environment variable is not set; cannot locate the PR repository config."
    }

    $path = Join-Path $oneDrive 'Orchestra/Orchestrations/PullRequests/repos.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "PR repository config not found at '$path'. Create it (see pr-repos.ps1 header for the schema) or verify OneDrive has finished syncing."
    }

    return $path
}

function Get-PrRepoConfig {
    <#
    .SYNOPSIS
        Parsed + validated repository config.
    .PARAMETER Force
        Bypass the in-process cache and re-read from disk.
    #>
    [CmdletBinding()]
    param([switch]$Force)

    if (-not $Force -and $null -ne $script:PrRepoConfigCache) {
        return $script:PrRepoConfigCache
    }

    $path = Get-PrRepoConfigPath

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding utf8
        $config = ConvertFrom-Json -InputObject $raw -Depth 20 -ErrorAction Stop
    } catch {
        throw "Failed to parse PR repository config '$path': $($_.Exception.Message)"
    }

    if ($null -eq $config.PSObject.Properties['repositories'] -or $null -eq $config.repositories) {
        throw "PR repository config '$path' has no 'repositories' array."
    }

    $defaultOrg = if ($config.PSObject.Properties['organization']) { [string]$config.organization } else { '' }
    $defaultProject = if ($config.PSObject.Properties['project']) { [string]$config.project } else { '' }

    $entries = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in @($config.repositories)) {
        if ($null -eq $entry) { continue }

        $repository = if ($entry.PSObject.Properties['repository']) { [string]$entry.repository } else { '' }
        if ([string]::IsNullOrWhiteSpace($repository)) {
            throw "PR repository config '$path' contains an entry with no 'repository' name."
        }

        $repoPath = if ($entry.PSObject.Properties['repoPath']) { [string]$entry.repoPath } else { '' }
        if ([string]::IsNullOrWhiteSpace($repoPath)) {
            throw "PR repository config '$path': entry '$repository' has no 'repoPath'."
        }

        # A duplicate repository name would make Resolve-PrRepoPath
        # non-deterministic, so reject it rather than silently picking one.
        if (-not $seen.Add($repository)) {
            throw "PR repository config '$path' lists repository '$repository' more than once."
        }

        $org = if ($entry.PSObject.Properties['organization'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.organization)) {
            [string]$entry.organization
        } else { $defaultOrg }

        $project = if ($entry.PSObject.Properties['project'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.project)) {
            [string]$entry.project
        } else { $defaultProject }

        if ([string]::IsNullOrWhiteSpace($org)) {
            throw "PR repository config '$path': entry '$repository' has no organization (and no top-level default)."
        }
        if ([string]::IsNullOrWhiteSpace($project)) {
            throw "PR repository config '$path': entry '$repository' has no project (and no top-level default)."
        }

        $enabled = $true
        if ($entry.PSObject.Properties['enabled']) { $enabled = [bool]$entry.enabled }

        [void]$entries.Add([pscustomobject]@{
            repository   = $repository
            repoPath     = $repoPath
            organization = $org
            project      = $project
            enabled      = $enabled
            orgUrl       = "https://dev.azure.com/$org"
            prUrlPrefix  = "https://dev.azure.com/$org/$project/_git/$repository/pullrequest/"
        })
    }

    if ($entries.Count -eq 0) {
        throw "PR repository config '$path' has an empty 'repositories' array."
    }

    $script:PrRepoConfigCache = [pscustomobject]@{
        path         = $path
        repositories = $entries.ToArray()
    }

    return $script:PrRepoConfigCache
}

function Get-PrRepoTargets {
    <#
    .SYNOPSIS
        The enabled repositories the pipeline should enumerate.
    .PARAMETER IncludeDisabled
        Also return entries with "enabled": false.
    .PARAMETER SkipPathValidation
        Do not verify that each repoPath is a git clone. Used by the
        pruner, which needs to reason about paths that may have gone away.
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludeDisabled,
        [switch]$SkipPathValidation
    )

    $config = Get-PrRepoConfig
    $targets = @($config.repositories | Where-Object { $IncludeDisabled -or $_.enabled })

    if ($targets.Count -eq 0) {
        throw "PR repository config '$($config.path)' has no enabled repositories."
    }

    if (-not $SkipPathValidation) {
        foreach ($target in $targets) {
            Assert-PrRepoPath -Target $target -ConfigPath $config.path
        }
    }

    return $targets
}

function Assert-PrRepoPath {
    <#
    .SYNOPSIS
        Verify a configured repoPath is a usable local git clone.
    .DESCRIPTION
        Checked with a plain Test-Path on the .git entry rather than
        `git rev-parse`, so validating N repositories costs no subprocesses.
        Handles both a .git directory and a .git file (linked worktree).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Target,
        [string]$ConfigPath = '<config>'
    )

    if (-not (Test-Path -LiteralPath $Target.repoPath)) {
        throw "PR repository config '$ConfigPath': repoPath for '$($Target.repository)' does not exist: '$($Target.repoPath)'. Clone it first (a dedicated clone parked on the default branch)."
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Target.repoPath '.git'))) {
        throw "PR repository config '$ConfigPath': repoPath for '$($Target.repository)' is not a git repository: '$($Target.repoPath)'."
    }
}

function Get-PrRepoNameFromUrl {
    <#
    .SYNOPSIS
        Extract the Azure DevOps repository name from a PR URL.
    .DESCRIPTION
        Returns $null when the URL is not an Azure DevOps PR URL, so
        callers can produce their own error message with more context.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$PrUrl)

    if ([string]::IsNullOrWhiteSpace($PrUrl)) { return $null }

    # Matches both dev.azure.com/{org}/{project}/_git/{repo}/pullrequest/{id}
    # and {org}.visualstudio.com/{project}/_git/{repo}/pullrequest/{id}, with
    # or without an optional legacy collection segment, because the repo name
    # is always the segment immediately after `_git/`.
    if ($PrUrl -match '/_git/([^/?#]+)/pullrequest/\d+') {
        return [System.Uri]::UnescapeDataString($Matches[1])
    }

    return $null
}

function Resolve-PrRepoPath {
    <#
    .SYNOPSIS
        Local clone path for the repository a PR belongs to.
    .DESCRIPTION
        This is what gets passed to `powerreview open --repo-path`. It
        THROWS for an unmapped repository and never falls back to a
        default, deliberately.

        Rationale: PowerReview resolves `repoPath ?? config.repo_base_path`
        and then runs `git worktree add <path> <pr-source-branch>` in
        whatever repo it lands on. If the fallback repo happens to contain
        a branch with the same name -- `main`, `dev`, or any `dependabot/*`
        name, all of which recur verbatim across repositories -- the
        worktree is created from the WRONG repository's source. The review
        agents then read the wrong files while the diff and threads come
        from the right PR, and post confidently wrong comments. Failing
        loudly is strictly better.
    .PARAMETER PrUrl
        Full pull request URL.
    .PARAMETER SkipPathValidation
        Return the configured path without checking it exists on disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PrUrl,
        [switch]$SkipPathValidation
    )

    $repoName = Get-PrRepoNameFromUrl -PrUrl $PrUrl
    if ([string]::IsNullOrWhiteSpace($repoName)) {
        throw "Could not extract a repository name from PR URL '$PrUrl'; expected '.../_git/<repo>/pullrequest/<id>'."
    }

    $config = Get-PrRepoConfig
    $match = @($config.repositories | Where-Object {
        [string]::Equals($_.repository, $repoName, [System.StringComparison]::OrdinalIgnoreCase)
    })

    if ($match.Count -eq 0) {
        $known = (@($config.repositories | ForEach-Object { $_.repository }) -join ', ')
        throw "Repository '$repoName' (from '$PrUrl') is not present in '$($config.path)'. Known repositories: $known. Refusing to guess a local clone."
    }

    $target = $match[0]

    if (-not $SkipPathValidation) {
        Assert-PrRepoPath -Target $target -ConfigPath $config.path
    }

    return $target.repoPath
}
