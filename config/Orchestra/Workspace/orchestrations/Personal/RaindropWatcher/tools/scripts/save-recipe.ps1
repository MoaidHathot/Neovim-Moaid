#!/usr/bin/env pwsh
# Writes a recipe markdown file into a configured recipes directory.
# Used by the recipe processors after the synth step has produced clean markdown.
#
# Usage:
#   save-recipe.ps1 -RecipesDirectory <dir> -SourcePath <md> -Title <title> [-Slug <slug>] [-SourceUrl <url>]
#
# Emits a single JSON object on stdout:
#   { "ok": true, "savedPath": "...", "slug": "...", "overwritten": false }

param(
    [Parameter(Mandatory=$true)] [string]$RecipesDirectory,
    [Parameter(Mandatory=$true)] [string]$SourcePath,
    [Parameter(Mandatory=$true)] [string]$Title,
    [string]$Slug,
    [string]$SourceUrl
)

function Write-Result($obj) {
    $obj | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

function To-Slug([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return 'untitled' }
    $s = $s.ToLowerInvariant()
    $s = [regex]::Replace($s, '[^a-z0-9\-]+', '-')
    $s = [regex]::Replace($s, '-{2,}', '-')
    $s = $s.Trim('-')
    if ($s.Length -gt 80) { $s = $s.Substring(0, 80).Trim('-') }
    if (-not $s) { $s = 'untitled' }
    return $s
}

try {
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "source markdown not found: $SourcePath"
    }
    if (-not (Test-Path -LiteralPath $RecipesDirectory)) {
        New-Item -ItemType Directory -Path $RecipesDirectory -Force | Out-Null
    }

    if (-not $Slug) { $Slug = To-Slug $Title }
    $candidate = Join-Path $RecipesDirectory "$Slug.md"

    # If file exists with identical content -> overwritten=false. Otherwise add
    # a short hash suffix to keep history visible.
    $overwritten = $false
    if (Test-Path -LiteralPath $candidate) {
        $existing = Get-Content -LiteralPath $candidate -Raw -ErrorAction SilentlyContinue
        $incoming = Get-Content -LiteralPath $SourcePath -Raw
        if ($existing -ne $incoming) {
            $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
            $candidate = Join-Path $RecipesDirectory "$Slug-$stamp.md"
        }
        $overwritten = ($existing -ne $incoming)
    }

    # Build a front-matter block prepended to the recipe body.
    $body = Get-Content -LiteralPath $SourcePath -Raw
    $front = @(
        '---'
        "title: ""$($Title -replace '"','\"')"""
        "source_url: ""$SourceUrl"""
        "saved_at: ""$(Get-Date -Format 'o')"""
        "saved_by: raindrop-watcher"
        'tags: [recipe]'
        '---'
        ''
    ) -join "`n"

    # Avoid double front-matter if the synth output already includes one.
    if ($body.StartsWith('---')) {
        Set-Content -LiteralPath $candidate -Value $body -NoNewline -Encoding UTF8
    } else {
        Set-Content -LiteralPath $candidate -Value ($front + $body) -NoNewline -Encoding UTF8
    }

    Write-Result @{
        ok = $true
        savedPath = $candidate
        slug = $Slug
        overwritten = $overwritten
    }
} catch {
    Write-Result @{
        ok = $false
        error = $_.Exception.Message
    }
}
