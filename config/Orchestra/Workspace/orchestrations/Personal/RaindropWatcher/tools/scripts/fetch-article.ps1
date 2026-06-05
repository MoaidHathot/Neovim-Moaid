#!/usr/bin/env pwsh
# Fetches a URL via Invoke-WebRequest, strips obvious chrome (scripts, styles,
# templates), and emits a JSON envelope describing the result so a downstream
# Prompt step can decide whether to fall back to Playwright.
#
# Usage:
#   fetch-article.ps1 <url> [-MaxChars 60000] [-TimeoutSeconds 30] [-UserAgent ...]
#
# Stdout (single JSON object):
#   {
#     "ok": true|false,
#     "url": "<requested>",
#     "finalUrl": "<after-redirects>",
#     "status": 200,
#     "contentType": "text/html; charset=utf-8",
#     "title": "<page title or null>",
#     "rawLength": 123456,            # bytes of original body
#     "textLength": 12000,            # length of cleaned-text excerpt
#     "text": "...",                  # cleaned-text excerpt, capped at MaxChars
#     "looksThin": false,             # heuristic flag the LLM should consult
#     "error": null                   # populated when ok=false
#   }
#
# Always exits 0; the downstream Prompt step inspects `ok` and `looksThin`.

param(
    [Parameter(Mandatory=$true, Position=0)] [string]$Url,
    [int]$MaxChars = 60000,
    [int]$TimeoutSeconds = 30,
    [string]$UserAgent = 'Mozilla/5.0 (RaindropWatcher; +orchestra) Chrome/120 Safari/537.36'
)

function Write-Result($obj) {
    $obj | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

function Strip-Html([string]$html) {
    if ([string]::IsNullOrEmpty($html)) { return '' }
    # Drop script / style / noscript / template / svg blocks (with content).
    $html = [regex]::Replace($html, '<script\b[^>]*>[\s\S]*?</script>', ' ', 'IgnoreCase')
    $html = [regex]::Replace($html, '<style\b[^>]*>[\s\S]*?</style>', ' ', 'IgnoreCase')
    $html = [regex]::Replace($html, '<noscript\b[^>]*>[\s\S]*?</noscript>', ' ', 'IgnoreCase')
    $html = [regex]::Replace($html, '<template\b[^>]*>[\s\S]*?</template>', ' ', 'IgnoreCase')
    $html = [regex]::Replace($html, '<svg\b[^>]*>[\s\S]*?</svg>', ' ', 'IgnoreCase')
    $html = [regex]::Replace($html, '<!--[\s\S]*?-->', ' ')
    # Replace block-level tags with newlines so paragraphs survive.
    $html = [regex]::Replace($html, '</(p|div|li|h[1-6]|tr|br|section|article|header|footer|nav|aside)>', "`n", 'IgnoreCase')
    # Strip all other tags.
    $html = [regex]::Replace($html, '<[^>]+>', ' ')
    # Decode common HTML entities.
    $html = [System.Net.WebUtility]::HtmlDecode($html)
    # Collapse whitespace.
    $html = [regex]::Replace($html, '[ \t\f\v]+', ' ')
    $html = [regex]::Replace($html, '\r\n?', "`n")
    $html = [regex]::Replace($html, '\n{3,}', "`n`n")
    return $html.Trim()
}

function Get-Title([string]$html) {
    if ([string]::IsNullOrEmpty($html)) { return $null }
    $m = [regex]::Match($html, '<title\b[^>]*>([\s\S]*?)</title>', 'IgnoreCase')
    if ($m.Success) {
        $t = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value).Trim()
        if ($t.Length -gt 0) { return $t }
    }
    return $null
}

try {
    $headers = @{
        'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        'Accept-Language' = 'en-US,en;q=0.9'
    }
    $resp = Invoke-WebRequest -Uri $Url `
        -Headers $headers `
        -UserAgent $UserAgent `
        -TimeoutSec $TimeoutSeconds `
        -MaximumRedirection 5 `
        -ErrorAction Stop `
        -SkipHttpErrorCheck

    $body = if ($resp.Content -is [byte[]]) {
        [System.Text.Encoding]::UTF8.GetString($resp.Content)
    } else { [string]$resp.Content }

    $stripped = Strip-Html $body
    $excerpt = if ($stripped.Length -le $MaxChars) { $stripped } else { $stripped.Substring(0, $MaxChars) }
    $title = Get-Title $body

    # Thin = looks like a JS shell / login wall / Cloudflare interstitial.
    $words = ($stripped -split '\s+' | Where-Object { $_ }).Count
    $looksThin = (
        $stripped.Length -lt 500 -or
        $words -lt 80 -or
        $stripped -match 'Please enable JavaScript' -or
        $stripped -match 'Just a moment\.\.\.' -or
        $stripped -match 'Checking your browser' -or
        $stripped -match 'Sign in to' -and $stripped -match 'access'
    )

    Write-Result @{
        ok = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400)
        url = $Url
        finalUrl = $resp.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
        status = [int]$resp.StatusCode
        contentType = ($resp.Headers['Content-Type'] -join '; ')
        title = $title
        rawLength = $body.Length
        textLength = $stripped.Length
        text = $excerpt
        wordCount = $words
        looksThin = [bool]$looksThin
        error = $null
    }
} catch {
    Write-Result @{
        ok = $false
        url = $Url
        finalUrl = $null
        status = 0
        contentType = $null
        title = $null
        rawLength = 0
        textLength = 0
        text = ''
        wordCount = 0
        looksThin = $true
        error = $_.Exception.Message
    }
}
