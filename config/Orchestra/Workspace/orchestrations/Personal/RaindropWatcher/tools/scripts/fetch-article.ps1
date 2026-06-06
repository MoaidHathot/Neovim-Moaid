#!/usr/bin/env pwsh
# Fetches a URL via Invoke-WebRequest, strips obvious chrome (scripts, styles,
# templates), extracts a list of non-ad image candidates, and emits a JSON
# envelope describing the result so a downstream Prompt step can decide
# whether to fall back to Playwright.
#
# Usage:
#   fetch-article.ps1 <url> [-MaxChars 60000] [-TimeoutSeconds 30]
#                           [-UserAgent ...] [-MaxImageCandidates 30]
#
# Stdout (single JSON object):
#   {
#     "ok": true|false,
#     "url": "<requested>",
#     "finalUrl": "<after-redirects>",
#     "status": 200,
#     "contentType": "text/html; charset=utf-8",
#     "title": "<page title or null>",
#     "rawLength": 123456,
#     "textLength": 12000,
#     "text": "...",
#     "wordCount": 1200,
#     "looksThin": false,
#     "images": [                       # NEW: ad-filtered candidates
#       { "src": "<absolute URL>",
#         "alt": "<alt text or empty>",
#         "context": "<short surrounding caption / figcaption if any>",
#         "width": <int|null>,
#         "height": <int|null>,
#         "skippedReasons": []          # always [] for candidates we keep;
#                                       #   ad-likely images are dropped entirely
#       }
#     ],
#     "error": null
#   }
#
# Image filtering policy (drop a candidate if ANY of these match):
#   - tracking pixels (1x1 or width/height <= 4)
#   - declared width/height < 200 (likely decorative / icon)
#   - src starts with `data:` (inline placeholders)
#   - host or path contains known ad-network substrings (doubleclick, googlesyndication,
#     adservice, googleadservices, adnxs, ads-twitter, taboola, outbrain, criteo,
#     scorecardresearch, quantserve, mathtag, casalemedia, rubiconproject, openx,
#     pubmatic, advertising)
#   - src matches `[._-](ads?|banner|sponsor|promo)([._-/?]|$)` (path conventions)
#   - parent class/id contains: ad, ads, sponsor, banner, promo, advert
#   - inside <aside>, <footer>, <header>, <nav>  (best-effort regex)
#
# Always exits 0; the downstream Prompt step inspects `ok` and `looksThin`
# and picks which `images` candidates to ultimately embed.

param(
    [Parameter(Mandatory=$true, Position=0)] [string]$Url,
    [int]$MaxChars = 60000,
    [int]$TimeoutSeconds = 30,
    [int]$MaxImageCandidates = 30,
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

function Get-AttributeValue([string]$tag, [string]$name) {
    if ([string]::IsNullOrEmpty($tag) -or [string]::IsNullOrEmpty($name)) { return $null }
    $pattern = "\b$([regex]::Escape($name))\s*=\s*(?:""([^""]*)""|'([^']*)'|([^\s>]+))"
    $m = [regex]::Match($tag, $pattern, 'IgnoreCase')
    if (-not $m.Success) { return $null }
    foreach ($i in 1..3) { if ($m.Groups[$i].Success) { return [System.Net.WebUtility]::HtmlDecode($m.Groups[$i].Value) } }
    return $null
}

function Resolve-ImageUrl([string]$src, [string]$baseUrl) {
    if ([string]::IsNullOrWhiteSpace($src)) { return $null }
    $src = $src.Trim()
    if ($src.StartsWith('data:', [StringComparison]::OrdinalIgnoreCase)) { return $null }
    try {
        $base = [System.Uri]::new($baseUrl)
        $abs = [System.Uri]::new($base, $src)
        return $abs.AbsoluteUri
    } catch {
        return $src
    }
}

function Is-AdLikely([string]$src, [string]$rawTag, [string]$enclosing) {
    if ([string]::IsNullOrEmpty($src)) { return $true }
    $adHosts = @(
        'doubleclick', 'googlesyndication', 'adservice', 'googleadservices',
        'adnxs', 'ads-twitter', 'taboola', 'outbrain', 'criteo',
        'scorecardresearch', 'quantserve', 'mathtag', 'casalemedia',
        'rubiconproject', 'openx', 'pubmatic', 'advertising', 'amazon-adsystem',
        'mediavine', 'adsafeprotected'
    )
    foreach ($h in $adHosts) {
        if ($src.ToLowerInvariant().Contains($h)) { return $true }
    }
    if ($src -match '(?i)[._\-/](ads?|banner|sponsor|promo|advert)([._\-/?=]|$)') { return $true }
    # Check enclosing element / parent classes.
    if ($enclosing -and $enclosing -match '(?i)\b(ad|ads|sponsor|banner|promo|advert|sidebar)\b') { return $true }
    # Check the img tag's own class/id.
    $cls = Get-AttributeValue $rawTag 'class'
    $id  = Get-AttributeValue $rawTag 'id'
    foreach ($attr in @($cls, $id)) {
        if ($attr -and $attr -match '(?i)\b(ad|ads|sponsor|banner|promo|advert)\b') { return $true }
    }
    return $false
}

function Extract-Images([string]$html, [string]$baseUrl, [int]$max) {
    $results = @()
    if ([string]::IsNullOrEmpty($html)) { return ,$results }

    # Cut out obvious non-content regions for parent-class checks. We use a
    # working copy where aside/footer/header/nav are wrapped with a marker,
    # so we can detect "inside chrome" cheaply.
    $marked = $html

    # Identify each <img> occurrence with its surrounding context.
    $imgRegex = [regex]::new('<img\b([^>]*)>', 'IgnoreCase')
    $matches  = $imgRegex.Matches($marked)
    foreach ($m in $matches) {
        if ($results.Count -ge $max) { break }
        $tag = $m.Value
        $start = $m.Index
        # Take ~400 chars of preceding context to detect ancestor chrome.
        $contextStart = [Math]::Max(0, $start - 600)
        $context = $marked.Substring($contextStart, $start - $contextStart)
        # Rough check: are we inside a footer/header/aside/nav that wasn't closed
        # before this <img>?
        $insideChrome = $false
        foreach ($tagName in @('aside','footer','header','nav')) {
            $openMatch  = ([regex]::Matches($context, "<$tagName\b", 'IgnoreCase')).Count
            $closeMatch = ([regex]::Matches($context, "</$tagName>", 'IgnoreCase')).Count
            if ($openMatch -gt $closeMatch) { $insideChrome = $true; break }
        }
        if ($insideChrome) { continue }

        # Pull src (handle srcset/data-src lazy-loaded variants).
        $src = Get-AttributeValue $tag 'src'
        if (-not $src) { $src = Get-AttributeValue $tag 'data-src' }
        if (-not $src) { $src = Get-AttributeValue $tag 'data-lazy-src' }
        if (-not $src) {
            $srcset = Get-AttributeValue $tag 'srcset'
            if ($srcset) {
                # Take first URL from srcset (best-effort).
                $first = ($srcset -split ',')[0].Trim()
                $src = ($first -split '\s+')[0]
            }
        }
        $abs = Resolve-ImageUrl $src $baseUrl
        if (-not $abs) { continue }
        if (Is-AdLikely $abs $tag $context) { continue }

        $alt = Get-AttributeValue $tag 'alt'
        if (-not $alt) { $alt = '' }
        $w = $null; $h = $null
        $ws = Get-AttributeValue $tag 'width'
        $hs = Get-AttributeValue $tag 'height'
        if ($ws -and [int]::TryParse($ws, [ref]$null)) { $w = [int]$ws }
        if ($hs -and [int]::TryParse($hs, [ref]$null)) { $h = [int]$hs }
        if (($w -ne $null -and $w -lt 200) -or ($h -ne $null -and $h -lt 200)) { continue }
        if (($w -ne $null -and $w -le 4) -or ($h -ne $null -and $h -le 4)) { continue }

        # Try to capture a figcaption sibling for richer context.
        $tailEnd = [Math]::Min($marked.Length - $m.Index - $m.Length, 600)
        $tail = $marked.Substring($m.Index + $m.Length, $tailEnd)
        $cap = ''
        $capMatch = [regex]::Match($tail, '<figcaption\b[^>]*>([\s\S]{0,500}?)</figcaption>', 'IgnoreCase')
        if ($capMatch.Success) {
            $cap = ($capMatch.Groups[1].Value -replace '<[^>]+>', ' ').Trim()
            $cap = [System.Net.WebUtility]::HtmlDecode($cap)
            $cap = ($cap -replace '\s+', ' ').Trim()
            if ($cap.Length -gt 240) { $cap = $cap.Substring(0, 240) + '...' }
        }

        $results += [pscustomobject]@{
            src = $abs
            alt = $alt
            context = $cap
            width = $w
            height = $h
            skippedReasons = @()
        }
    }
    # De-dup by src (keep first occurrence).
    $seen = @{}
    $deduped = @()
    foreach ($it in $results) {
        if (-not $seen.ContainsKey($it.src)) {
            $seen[$it.src] = $true
            $deduped += $it
        }
    }
    return ,$deduped
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
    $finalUrl = $resp.BaseResponse.RequestMessage.RequestUri.AbsoluteUri

    # Extract image candidates from the ORIGINAL HTML (not the stripped text).
    $images = @()
    try {
        $images = Extract-Images $body $finalUrl $MaxImageCandidates
    } catch {
        Write-Warning ("fetch-article: image extraction failed: {0}" -f $_.Exception.Message)
        $images = @()
    }

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
        finalUrl = $finalUrl
        status = [int]$resp.StatusCode
        contentType = ($resp.Headers['Content-Type'] -join '; ')
        title = $title
        rawLength = $body.Length
        textLength = $stripped.Length
        text = $excerpt
        wordCount = $words
        looksThin = [bool]$looksThin
        images = $images
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
        images = @()
        error = $_.Exception.Message
    }
}
