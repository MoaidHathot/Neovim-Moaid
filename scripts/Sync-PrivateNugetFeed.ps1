#Requires -Version 5.1
<#
.SYNOPSIS
    Mirrors the latest published version of every NuGet package you own into a
    private local folder feed.

.DESCRIPTION
    Tools resolved through `dnx` normally query every configured NuGet source,
    which on a corporate network costs ~10s per invocation because of the remote
    auth round-trip. Pointing `dnx --source` at a local folder feed drops that to
    ~0.4s. This script keeps that feed current.

    It is idempotent: a version already present in the feed is never re-fetched,
    so repeat runs transfer no data and are safe to schedule or run from DSC.

    Package discovery uses nuget.org's search endpoint filtered by owner, so
    newly published packages are picked up without editing this script. Version
    resolution deliberately goes through -Source (the same feed downloads come
    from) rather than nuget.org, so we never resolve a version the download
    source hasn't mirrored yet.

.PARAMETER FeedPath
    Target folder feed. Defaults to $env:PRIVATE_LOCAL_NUGET_FEED, which
    configurations/configuration.dev.dsc.yaml sets machine-wide.

.PARAMETER Owner
    nuget.org account whose packages should be mirrored.

.PARAMETER Source
    NuGet source used for version resolution and download. Must be a source
    reachable from this machine; nuget.org itself is often blocked on corporate
    networks, where an internal proxy feed is used instead.

.PARAMETER StableOnly
    Ignore prerelease versions. By default the newest version wins even when it
    is a prerelease.

.PARAMETER PruneOldVersions
    After a successful sync, delete versions superseded by the one just
    confirmed. Off by default; the feed only grows unless you ask for this.

.EXAMPLE
    ./Sync-PrivateNugetFeed.ps1
    Sync using the machine's configured feed path.

.EXAMPLE
    ./Sync-PrivateNugetFeed.ps1 -WhatIf
    Report what would be downloaded without writing anything.

.EXAMPLE
    ./Sync-PrivateNugetFeed.ps1 -FeedPath 'C:\nuget\local-feed' -PruneOldVersions
    Sync and drop superseded versions.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $FeedPath = $env:PRIVATE_LOCAL_NUGET_FEED,
    [string] $Owner = 'MoaidHathot',
    [string] $Source = 'azure-default',
    [string] $SearchEndpoint = 'https://azuresearch-usnc.nuget.org/query',
    [switch] $StableOnly,
    [switch] $PruneOldVersions,
    [int]    $ThrottleLimit = 8
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($FeedPath)) {
    throw "FeedPath not supplied and PRIVATE_LOCAL_NUGET_FEED is not set. Pass -FeedPath or run configurations/configuration.dev.dsc.yaml."
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet CLI not found on PATH."
}

if (-not (Test-Path -LiteralPath $FeedPath)) {
    if ($PSCmdlet.ShouldProcess($FeedPath, 'Create feed directory')) {
        New-Item -ItemType Directory -Path $FeedPath -Force | Out-Null
    }
}

Write-Host "Feed   : $FeedPath"
Write-Host "Source : $Source"

# --- discovery -------------------------------------------------------------
# nuget.org's search endpoint supports owner: filtering and is reachable even on
# networks that block api.nuget.org. Its per-package "version" field reports the
# latest *stable* only, so it is used for ids exclusively - versions come later.
$ids = @()
$discovery = 'search endpoint'
try {
    $skip = 0
    $take = 100
    while ($true) {
        $uri = '{0}?q=owner:{1}&take={2}&skip={3}&prerelease=true' -f $SearchEndpoint, $Owner, $take, $skip
        $response = Invoke-RestMethod -Uri $uri -TimeoutSec 30
        if (-not $response.data -or $response.data.Count -eq 0) { break }
        $ids += $response.data.id
        $skip += $take
        if ($skip -ge $response.totalHits) { break }
    }
} catch {
    Write-Warning "Discovery via $SearchEndpoint failed: $($_.Exception.Message)"
    Write-Warning "Falling back to refreshing package ids already present in the feed."
    $discovery = 'existing feed contents'
    $ids = @(Get-ChildItem -LiteralPath $FeedPath -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
}

$ids = @($ids | Sort-Object -Unique)
if ($ids.Count -eq 0) {
    Write-Warning "No packages discovered. Nothing to do."
    return
}
Write-Host "Discovered $($ids.Count) package(s) via $discovery"

# --- resolve latest version per package ------------------------------------
# Held as text, not a scriptblock: ForEach-Object -Parallel refuses scriptblocks
# passed via $using:, so each runspace reconstitutes it instead. The sequential
# branch exists for Windows PowerShell 5.1, which has no -Parallel.
$resolveOneText = @'
param($Id, $Source, $StableOnly)
$searchArgs = @($Id, '--source', $Source, '--exact-match', '--format', 'json')
if (-not $StableOnly) { $searchArgs += '--prerelease' }
$raw = & dotnet package search @searchArgs 2>$null | Out-String
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
    return [pscustomobject]@{ Id = $Id; Version = $null; Error = "search failed (exit $LASTEXITCODE)" }
}
$packages = ($raw | ConvertFrom-Json).searchResult.packages | Where-Object { $_ }
if (-not $packages) {
    return [pscustomobject]@{ Id = $Id; Version = $null; Error = "not found on '$Source'" }
}
# dotnet package search returns versions newest-first.
return [pscustomobject]@{ Id = $Id; Version = @($packages)[0].version; Error = $null }
'@

if ($PSVersionTable.PSVersion.Major -ge 7) {
    $resolved = $ids | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        & ([scriptblock]::Create($using:resolveOneText)) $_ $using:Source $using:StableOnly
    }
} else {
    $resolveOne = [scriptblock]::Create($resolveOneText)
    $resolved = $ids | ForEach-Object { & $resolveOne $_ $Source $StableOnly }
}

# --- decide what is missing -------------------------------------------------
$upToDate = [System.Collections.Generic.List[string]]::new()
$missing = [System.Collections.Generic.List[object]]::new()
$failed = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $resolved) {
    if ($entry.Error) {
        $failed.Add("$($entry.Id): $($entry.Error)")
        continue
    }
    $versionDir = Join-Path $FeedPath (Join-Path $entry.Id.ToLowerInvariant() $entry.Version)
    $present = Test-Path -LiteralPath $versionDir -PathType Container
    if ($present) {
        $present = @(Get-ChildItem -LiteralPath $versionDir -Filter *.nupkg -ErrorAction SilentlyContinue).Count -gt 0
    }
    if ($present) { $upToDate.Add("$($entry.Id) $($entry.Version)") }
    else { $missing.Add($entry) }
}

Write-Host "Up to date : $($upToDate.Count)"
Write-Host "Missing    : $($missing.Count)"

# --- download missing versions ---------------------------------------------
$downloaded = [System.Collections.Generic.List[string]]::new()

if ($missing.Count -gt 0) {
    foreach ($entry in $missing) { Write-Host "  need $($entry.Id) $($entry.Version)" }

    if ($PSCmdlet.ShouldProcess("$($missing.Count) package(s)", "Download into $FeedPath")) {
        $staging = Join-Path ([System.IO.Path]::GetTempPath()) ("nugetsync-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        try {
            # @(...) is load-bearing: with a single missing package ForEach-Object
            # returns a scalar string, and splatting a scalar yields malformed
            # arguments that make dotnet exit 1.
            $specs = @($missing | ForEach-Object { "$($_.Id)@$($_.Version)" })
            $downloadArgs = $specs + @('--prerelease', '-s', $Source, '-o', $staging)
            $output = & dotnet package download $downloadArgs 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                # Never swallow this. A silent download failure is indistinguishable
                # from an up-to-date feed, which is exactly how a broken feed hides.
                Write-Warning "dotnet package download exited $LASTEXITCODE"
                @($output -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 8) |
                    ForEach-Object { Write-Warning "  $_" }
            }

            foreach ($entry in $missing) {
                $sourceDir = Join-Path $staging (Join-Path $entry.Id.ToLowerInvariant() $entry.Version)
                if (-not (Test-Path -LiteralPath $sourceDir)) {
                    $failed.Add("$($entry.Id) $($entry.Version): download produced no output")
                    continue
                }
                $destDir = Join-Path $FeedPath (Join-Path $entry.Id.ToLowerInvariant() $entry.Version)
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null

                # .nupkg.sha512 is mandatory: without it NuGet silently fails to
                # discover the package in a hierarchical folder feed.
                $files = Get-ChildItem -LiteralPath $sourceDir -File |
                    Where-Object { $_.Extension -in '.nupkg', '.nuspec' -or $_.Name -like '*.sha512' }
                $files | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $destDir -Force }

                $hasNupkg = @(Get-ChildItem -LiteralPath $destDir -Filter *.nupkg).Count -gt 0
                $hasSha = @(Get-ChildItem -LiteralPath $destDir -Filter *.sha512).Count -gt 0
                if ($hasNupkg -and $hasSha) { $downloaded.Add("$($entry.Id) $($entry.Version)") }
                else { $failed.Add("$($entry.Id) $($entry.Version): incomplete copy (nupkg=$hasNupkg sha512=$hasSha)") }
            }
        } finally {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- optional prune ---------------------------------------------------------
$pruned = [System.Collections.Generic.List[string]]::new()

if ($PruneOldVersions) {
    foreach ($entry in $resolved) {
        if ($entry.Error) { continue }
        $packageDir = Join-Path $FeedPath $entry.Id.ToLowerInvariant()
        if (-not (Test-Path -LiteralPath $packageDir)) { continue }
        $stale = Get-ChildItem -LiteralPath $packageDir -Directory | Where-Object { $_.Name -ne $entry.Version }
        foreach ($dir in $stale) {
            if ($PSCmdlet.ShouldProcess($dir.FullName, 'Remove superseded version')) {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force
                $pruned.Add("$($entry.Id) $($dir.Name)")
            }
        }
    }
}

# --- summary ----------------------------------------------------------------
Write-Host ""
Write-Host "=== summary ==="
Write-Host "discovered : $($ids.Count)"
Write-Host "up to date : $($upToDate.Count)"
Write-Host "downloaded : $($downloaded.Count)"
if ($downloaded.Count) { $downloaded | ForEach-Object { Write-Host "  + $_" } }
if ($PruneOldVersions) {
    Write-Host "pruned     : $($pruned.Count)"
    if ($pruned.Count) { $pruned | ForEach-Object { Write-Host "  - $_" } }
}
Write-Host "failed     : $($failed.Count)"
if ($failed.Count) {
    $failed | ForEach-Object { Write-Warning "  $_" }
    exit 1
}
