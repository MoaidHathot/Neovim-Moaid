#!/usr/bin/env pwsh
# Downloads a chosen list of image URLs to a sidecar directory next to a
# saved recipe markdown file, so the recipe is self-contained on disk.
#
# Usage:
#   save-article-images.ps1 -ImagesJson '<json array of {src, alt}>' `
#                           -SidecarDirectory '<absolute path>' `
#                           [-MaxDownloads 8] [-TimeoutSeconds 20]
#                           [-UserAgent ...]
#
#   -- or --
#
#   save-article-images.ps1 -ImagesJson '<json>' `
#                           -RecipesDirectory '<dir>' `
#                           -Title '<recipe title>' `
#                           [-MaxDownloads 8] ...
#       (the sidecar dir is computed as `<RecipesDirectory>/<slug>-images/`
#        using the same slug derivation as save-recipe.ps1, so the images
#        end up next to the saved recipe markdown)
#
# Stdin (alternative to -ImagesJson): a JSON array of `{src, alt}` objects.
#
# Stdout (single JSON object):
#   {
#     "ok": true|false,
#     "sidecarDirectory": "<dir>",
#     "downloaded": [
#       { "src": "...", "alt": "...", "localPath": "...", "fileUri": "file:///..." }
#     ],
#     "failed":     [ { "src": "...", "alt": "...", "error": "..." } ],
#     "skipped":    [ { "src": "...", "reason": "..." } ]
#   }
#
# Exits 0 even on partial failures so the caller (Prompt step) can decide.
# Exits non-zero only if SidecarDirectory cannot be created.

param(
    [string]$ImagesJson,
    [string]$SidecarDirectory,
    [string]$RecipesDirectory,
    [string]$Title,
    [int]$MaxDownloads = 8,
    [int]$TimeoutSeconds = 20,
    [string]$UserAgent = 'Mozilla/5.0 (RaindropWatcher; +orchestra) Chrome/120 Safari/537.36'
)

$ErrorActionPreference = 'Stop'

function To-RecipeSlug([string]$s) {
    # MUST match the derivation in save-recipe.ps1 so the sidecar dir lines
    # up with the saved recipe file's slug.
    if ([string]::IsNullOrWhiteSpace($s)) { return 'untitled' }
    $s = $s.ToLowerInvariant()
    $s = [regex]::Replace($s, '[^a-z0-9\-]+', '-')
    $s = [regex]::Replace($s, '-{2,}', '-')
    $s = $s.Trim('-')
    if ($s.Length -gt 80) { $s = $s.Substring(0, 80).Trim('-') }
    if (-not $s) { $s = 'untitled' }
    return $s
}

if (-not $SidecarDirectory) {
    if (-not $RecipesDirectory -or -not $Title) {
        @{ ok = $false; error = "either -SidecarDirectory or (-RecipesDirectory + -Title) must be provided" } | ConvertTo-Json -Compress
        exit 1
    }
    $slug = To-RecipeSlug $Title
    $SidecarDirectory = Join-Path $RecipesDirectory "$slug-images"
}

if (-not $ImagesJson) {
    try { $ImagesJson = [Console]::In.ReadToEnd() } catch {}
}
$ImagesJson = if ($ImagesJson) { $ImagesJson.Trim() } else { '' }

$images = @()
if ($ImagesJson) {
    try {
        $parsed = $ImagesJson | ConvertFrom-Json
        if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string])) {
            $images = @($parsed)
        } else {
            $images = @($parsed)
        }
    } catch {
        @{ ok = $false; error = "could not parse ImagesJson: $($_.Exception.Message)" } | ConvertTo-Json -Compress
        exit 0
    }
}

# Make sure the sidecar exists. This is the only path that exits non-zero.
try {
    if (-not (Test-Path -LiteralPath $SidecarDirectory)) {
        New-Item -ItemType Directory -Path $SidecarDirectory -Force | Out-Null
    }
} catch {
    @{ ok = $false; error = "could not create sidecar dir: $($_.Exception.Message)"; sidecarDirectory = $SidecarDirectory } | ConvertTo-Json -Compress
    exit 1
}

$downloaded = @()
$failed     = @()
$skipped    = @()
$count = 0

function Get-ExtensionFromContentType([string]$ct) {
    if (-not $ct) { return '.bin' }
    $ct = $ct.ToLowerInvariant()
    if ($ct.Contains('jpeg') -or $ct.Contains('jpg')) { return '.jpg' }
    if ($ct.Contains('png'))  { return '.png' }
    if ($ct.Contains('gif'))  { return '.gif' }
    if ($ct.Contains('webp')) { return '.webp' }
    if ($ct.Contains('avif')) { return '.avif' }
    if ($ct.Contains('svg'))  { return '.svg' }
    return '.bin'
}

function Make-Slug([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return 'img' }
    $s = $s.ToLowerInvariant()
    $s = [regex]::Replace($s, '[^a-z0-9]+', '-')
    $s = $s.Trim('-')
    if ($s.Length -gt 40) { $s = $s.Substring(0, 40).Trim('-') }
    if ([string]::IsNullOrWhiteSpace($s)) { return 'img' }
    return $s
}

function Get-UrlHash([string]$src) {
    # SHA1 first-12-hex of the URL = stable, content-identity-ish key.
    # We use this as the FILENAME PREFIX so re-runs against the same image
    # URL produce the same on-disk path. The download path then checks
    # `Test-Path` first and short-circuits as "already-downloaded".
    $h = [System.Security.Cryptography.SHA1]::Create()
    try {
        return [BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($src))).Replace('-','').Substring(0,12).ToLowerInvariant()
    } finally {
        $h.Dispose()
    }
}

function Find-ExistingByHash([string]$dir, [string]$hash) {
    # Returns the first file path in $dir whose name starts with `img-<hash>-`.
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $candidates = Get-ChildItem -LiteralPath $dir -File -Filter ("img-$hash-*") -ErrorAction SilentlyContinue
    if ($candidates -and $candidates.Count -gt 0) { return $candidates[0].FullName }
    return $null
}

foreach ($img in $images) {
    if ($count -ge $MaxDownloads) {
        $skipped += [pscustomobject]@{ src = $img.src; reason = 'max-downloads-reached' }
        continue
    }
    $src = $img.src
    if ([string]::IsNullOrWhiteSpace($src)) {
        $skipped += [pscustomobject]@{ src = $null; reason = 'empty-src' }
        continue
    }
    if ($src -match '^data:') {
        $skipped += [pscustomobject]@{ src = $src; reason = 'data-uri-not-supported' }
        continue
    }

    $hash = Get-UrlHash $src
    $altSlug = Make-Slug ($img.alt | Out-String).Trim()
    $tmpName = "img-$hash-$altSlug"
    $count++

    # Idempotency: if a file matching `img-<hash>-*` already exists in the
    # sidecar dir, skip the download and return the existing path as if we
    # just downloaded it. This handles retries cleanly -- no re-downloads,
    # no -8hex- suffix bloat.
    $existing = Find-ExistingByHash $SidecarDirectory $hash
    if ($existing) {
        $downloaded += [pscustomobject]@{
            src       = $src
            alt       = $img.alt
            localPath = $existing
            fileUri   = ([System.Uri]::new($existing)).AbsoluteUri
            cached    = $true
        }
        continue
    }

    try {
        $tmpPath = Join-Path $SidecarDirectory ($tmpName + '.tmp')
        $resp = Invoke-WebRequest -Uri $src `
            -UserAgent $UserAgent `
            -TimeoutSec $TimeoutSeconds `
            -MaximumRedirection 5 `
            -OutFile $tmpPath `
            -PassThru `
            -ErrorAction Stop
        $ct = ''
        if ($resp -and $resp.Headers -and $resp.Headers['Content-Type']) {
            $ct = ($resp.Headers['Content-Type'] -join '; ')
        }
        # Refuse non-image content (e.g., HTML error page served at the URL).
        if ($ct -and -not ($ct.ToLowerInvariant().Contains('image/'))) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction Ignore
            $failed += [pscustomobject]@{ src = $src; alt = $img.alt; error = "non-image content-type: $ct" }
            continue
        }
        $ext = Get-ExtensionFromContentType $ct
        if ($ext -eq '.bin') {
            # Fall back to URL extension when content-type is unhelpful.
            try {
                $u = [System.Uri]::new($src)
                $urlExt = [System.IO.Path]::GetExtension($u.AbsolutePath)
                if ($urlExt) { $ext = $urlExt }
            } catch {}
        }
        $finalPath = Join-Path $SidecarDirectory ($tmpName + $ext)
        # By construction `tmpName` is unique per URL (hash) -- if a file with
        # this exact path exists already, it's from a prior partial run and
        # we can safely overwrite (the bytes should be the same content).
        Move-Item -LiteralPath $tmpPath -Destination $finalPath -Force
        $fileUri = ([System.Uri]::new($finalPath)).AbsoluteUri
        $downloaded += [pscustomobject]@{
            src       = $src
            alt       = $img.alt
            localPath = $finalPath
            fileUri   = $fileUri
            cached    = $false
        }
    } catch {
        Remove-Item -LiteralPath (Join-Path $SidecarDirectory ($tmpName + '.tmp')) -Force -ErrorAction Ignore
        $failed += [pscustomobject]@{ src = $src; alt = $img.alt; error = $_.Exception.Message }
    }
}

@{
    ok                = $true
    sidecarDirectory  = $SidecarDirectory
    downloaded        = $downloaded
    failed            = $failed
    skipped           = $skipped
} | ConvertTo-Json -Depth 6 -Compress
