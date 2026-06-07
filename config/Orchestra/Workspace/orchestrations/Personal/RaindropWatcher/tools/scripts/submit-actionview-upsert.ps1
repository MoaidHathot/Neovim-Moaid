#!/usr/bin/env pwsh
# Idempotent ActionView submit + auto-inline local images.
#
# Pipeline per call:
#   1. Read the entry JSON file.
#   2. Find every `file:///<drive>:/...` URI that points to an image
#      (jpg/jpeg/png/gif/webp/avif/svg) and replace it with a
#      `data:<mime>;base64,...` data URI. ActionView's browser-based
#      renderer at http://localhost:5180 blocks file:// URIs for security
#      reasons (mixed-content / CSP), so entries that embed local-frame
#      paths would render broken images otherwise. Data URIs render inline.
#   3. Extract the entry `id`.
#   4. Delete any prior entry with the same id (idempotent upsert).
#   5. Add the (rewritten) entry.
#
# Safety caps prevent runaway entry sizes:
#   - max -MaxInlineBytes of source-file bytes embedded per entry
#     (the resulting JSON is ~33% larger because of base64).
#   - per-file cap of -MaxPerFileBytes.
#   - missing or oversized files are left as-is in the markdown (so other
#     images in the same entry still come through; the broken ones still
#     show broken, but at least they don't blow up the whole entry).
#
# Usage:
#   submit-actionview-upsert.ps1 -EntryFile <path>
#                                [-MaxInlineBytes 5242880]    # 5 MB total
#                                [-MaxPerFileBytes 524288]    # 512 KB per file
#                                [-NoInline]                  # skip step 2
#
# Stdout: forwards `ActionView.Cli add` output.
# Stderr: a JSON line with inlining stats (informational only).
#
# Exit codes:
#   0  - add succeeded (delete may or may not have removed a prior entry)
#   1  - bad arguments / entry file unreadable / entry id missing
#   2+ - non-zero ActionView add exit code (passed through)

param(
    [Parameter(Mandatory=$true)] [string]$EntryFile,
    [int]$MaxInlineBytes  = 5242880,   # 5 MB total source bytes per entry
    [int]$MaxPerFileBytes = 524288,    # 512 KB per file
    [switch]$NoInline
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $EntryFile)) {
    Write-Error "submit-actionview-upsert: entry file not found: $EntryFile"
    exit 1
}

# --- helpers ---------------------------------------------------------------
function Get-MimeFromPath([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    switch ($ext) {
        '.jpg'  { return 'image/jpeg' }
        '.jpeg' { return 'image/jpeg' }
        '.png'  { return 'image/png'  }
        '.gif'  { return 'image/gif'  }
        '.webp' { return 'image/webp' }
        '.avif' { return 'image/avif' }
        '.svg'  { return 'image/svg+xml' }
        default { return $null }
    }
}

function Convert-FileUriToLocalPath([string]$uriBody) {
    # `$uriBody` is everything after `file:///`, e.g. `C:/temp/foo/bar.jpg`.
    # Returns a Windows local path (backslashes, %xx-decoded).
    $decoded = [System.Net.WebUtility]::UrlDecode($uriBody)
    return ($decoded -replace '/','\')
}

# --- 1) Load the entry -----------------------------------------------------
$rawText = Get-Content -LiteralPath $EntryFile -Raw -Encoding UTF8

# Parse separately to grab the `id`. We work on the raw text afterward so
# JSON formatting is preserved through the rewrite.
$entry = $null
try {
    $entry = $rawText | ConvertFrom-Json
} catch {
    Write-Error "submit-actionview-upsert: entry file is not valid JSON: $($_.Exception.Message)"
    exit 1
}

$entryId = $entry.id
if ([string]::IsNullOrWhiteSpace($entryId)) {
    Write-Error "submit-actionview-upsert: entry JSON is missing the 'id' field (this script requires a stable id for upsert semantics; use 'dnx ActionView.Cli add --file ...' directly when you want an auto-generated id)"
    exit 1
}

# --- 2) Inline file:// image URIs as data: URIs ----------------------------
$inlineStats = [ordered]@{
    inlined          = 0
    skippedMissing   = 0
    skippedTooLarge  = 0
    skippedBudget    = 0
    skippedUnknownExt= 0
    totalSourceBytes = 0
}

$rewrittenText = $rawText

if (-not $NoInline) {
    # Match `file:///<drive>:/<rest>.<ext>` where <ext> is a known image
    # extension. Stop at characters that can't legitimately appear in a
    # JSON-embedded URI (quote, whitespace, closing markdown paren). We
    # also handle the JSON-escaped form `file:\/\/\/<drive>:\/...` where
    # the serializer chose to escape forward slashes (rare but valid).
    $patterns = @(
        # Common form: forward slashes left unescaped.
        '(?i)file:///([A-Za-z]:/[^"\s)\\]+?\.(?:jpg|jpeg|png|gif|webp|avif|svg))',
        # Escaped form: backslash-escaped slashes (\\/ in JSON source).
        '(?i)file:\\\/\\\/\\\/([A-Za-z]:\\/[^"\s)]+?\.(?:jpg|jpeg|png|gif|webp|avif|svg))'
    )

    foreach ($pattern in $patterns) {
        $rewrittenText = [regex]::Replace($rewrittenText, $pattern, {
            param($m)
            $uriBody = $m.Groups[1].Value
            # Normalize escaped slashes back to forward slashes for path conversion.
            $uriBody = $uriBody -replace '\\/','/'
            $localPath = Convert-FileUriToLocalPath $uriBody
            $mime = Get-MimeFromPath $localPath
            if (-not $mime) {
                $script:inlineStats.skippedUnknownExt++
                return $m.Value
            }
            if (-not (Test-Path -LiteralPath $localPath)) {
                $script:inlineStats.skippedMissing++
                return $m.Value
            }
            $info = Get-Item -LiteralPath $localPath
            if ($info.Length -gt $MaxPerFileBytes) {
                $script:inlineStats.skippedTooLarge++
                return $m.Value
            }
            if (($script:inlineStats.totalSourceBytes + $info.Length) -gt $MaxInlineBytes) {
                $script:inlineStats.skippedBudget++
                return $m.Value
            }
            try {
                $bytes = [System.IO.File]::ReadAllBytes($localPath)
            } catch {
                $script:inlineStats.skippedMissing++
                return $m.Value
            }
            $b64 = [Convert]::ToBase64String($bytes)
            $script:inlineStats.inlined++
            $script:inlineStats.totalSourceBytes += $info.Length
            return "data:$mime;base64,$b64"
        })
    }
}

# Write the rewritten entry to a temp file (don't mutate the upstream
# orchestration-output file -- it's shared with the run audit trail).
$submitFile = $EntryFile
if (-not $NoInline -and $inlineStats.inlined -gt 0) {
    $submitFile = Join-Path $env:TEMP ("av-upsert-" + [guid]::NewGuid().ToString('N') + ".json")
    Set-Content -LiteralPath $submitFile -Value $rewrittenText -Encoding UTF8 -NoNewline
}

# Stats to stderr so callers scraping stdout aren't affected.
[Console]::Error.WriteLine(($inlineStats | ConvertTo-Json -Compress))

try {
    # --- 3) Try to delete any prior entry with the same id ---------------
    # Failure is expected on the first ever run (no such entry), so swallow.
    & dnx ActionView.Cli --yes -- delete $entryId --force 2>$null | Out-Null
    # Note: $LASTEXITCODE is non-zero here when the entry doesn't exist;
    # that is fine, we treat it as a no-op. Do NOT propagate it.

    # --- 4) Add the (possibly-rewritten) entry ---------------------------
    & dnx ActionView.Cli --yes -- add --file $submitFile
    $addExit = $LASTEXITCODE
} finally {
    if ($submitFile -ne $EntryFile -and (Test-Path -LiteralPath $submitFile)) {
        Remove-Item -LiteralPath $submitFile -Force -ErrorAction Ignore
    }
}

exit $addExit
