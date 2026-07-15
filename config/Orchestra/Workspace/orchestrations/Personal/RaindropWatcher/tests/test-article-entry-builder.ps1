#!/usr/bin/env pwsh
# Integration test for build-article-actionview-entry.ps1 -- the deterministic
# replacement for the LLM create-action-view-entry step that used to hang on large
# articles. Verifies the produced entry is schema-valid (ActionView.Cli validate
# --strict) and structurally correct (Analysis body, Visual-evidence extraction,
# workflow-tag stripping, subtitle from metadata, Reprocess action).
#
# Exit 0 = all pass; 1 = failure.

param(
    [string]$Builder = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/scripts/build-article-actionview-entry.ps1')
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:pass = 0; $script:fail = 0
function Assert([bool]$c, [string]$m) {
    if ($c) { $script:pass++; Write-Host "  PASS  $m" -ForegroundColor Green }
    else    { $script:fail++; Write-Host "  FAIL  $m" -ForegroundColor Red }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("article-entry-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $md = Join-Path $tmp 'analysis.md'
    @"
# Analysis - *Test Article*

**TL;DR.** A short deterministic test analysis.

![hero image](https://cdn.example.com/hero.png)

## Detail
Some prose with a second figure.

![figure two](https://cdn.example.com/fig2.jpg)
"@ | Set-Content -LiteralPath $md -Encoding utf8

    $readable = '{"mode":"http","finalUrl":"https://example.com/a","title":"Test Article","byline":"Jane Doe","siteName":"Example","publishedAt":"2026-01-02"}'
    $out = Join-Path $tmp 'entry.json'
    $reproc = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/scripts/reprocess-raindrop.ps1'

    Write-Host "[1] build entry with 2 inline images + workflow tag to strip" -ForegroundColor Cyan
    & pwsh -NoProfile -File $Builder -RaindropId 555001 -Title 'Test Article' -Url 'https://example.com/a' `
        -TagsJson '["failed","ai","research"]' -Note 'my note' -AddedAt '2026-01-01T00:00:00Z' `
        -SynthesisFile $md -ReadableJson $readable -Source raindrop-article-generic-processor `
        -ReprocessScript $reproc -OutFile $out *> $null
    Assert (Test-Path $out) "builder wrote the entry file"

    $v = (& dnx ActionView.Cli --yes -- validate --file $out --strict 2>&1 | Out-String)
    $vok = $false; try { $vok = ($v | ConvertFrom-Json).ok } catch { }
    Assert ($vok -eq $true) "entry is schema-valid (ActionView.Cli validate --strict): $($v.Trim())"

    $e = Get-Content $out -Raw | ConvertFrom-Json
    Assert ($e.id -eq 'raindrop-555001-article') "id = raindrop-555001-article"
    Assert ($e.type -eq 'raindrop-article') "type = raindrop-article"
    Assert ($e.subtitle -eq 'Jane Doe | Example | 2026-01-02') "subtitle built from byline|site|date (got '$($e.subtitle)')"
    Assert (($e.tags -contains 'raindrop') -and ($e.tags -contains 'article') -and ($e.tags -contains 'ai') -and ($e.tags -contains 'research')) "user tags kept + raindrop/article added"
    Assert ($e.tags -notcontains 'failed') "workflow tag 'failed' stripped from entry tags"
    $analysis = ($e.content | Where-Object { $_.title -eq 'Analysis' }).content[0].body
    Assert ($analysis -match 'A short deterministic test analysis') "Analysis section carries the synthesis markdown"
    $ve = $e.content | Where-Object { $_.title -eq 'Visual evidence' }
    Assert ($ve -and $ve.badge -eq '2 images') "Visual evidence section built from 2 inline images (badge='$($ve.badge)')"
    Assert (($e.content | Where-Object { $_.type -eq 'keyValue' }).pairs.'Fetch mode' -eq 'http') "Source keyValue carries fetch mode"
    $reprocAction = $e.actions | Where-Object { $_.label -match 'Reprocess' }
    Assert ($reprocAction -and ($reprocAction.command.args -contains '555001')) "Reprocess action targets the raindrop id"

    Write-Host "`n[2] no images + empty tags -> no Visual evidence, minimal tags" -ForegroundColor Cyan
    $md2 = Join-Path $tmp 'plain.md'; "# Plain`n`nNo images here." | Set-Content -LiteralPath $md2 -Encoding utf8
    $out2 = Join-Path $tmp 'entry2.json'
    & pwsh -NoProfile -File $Builder -RaindropId 555002 -Title 'Plain' -Url 'https://example.com/b' `
        -TagsJson '[]' -SynthesisFile $md2 -ReadableJson '{"mode":"playwright"}' `
        -ReprocessScript $reproc -OutFile $out2 *> $null
    $e2 = Get-Content $out2 -Raw | ConvertFrom-Json
    $v2ok = $false; try { $v2ok = ((& dnx ActionView.Cli --yes -- validate --file $out2 --strict 2>&1 | Out-String) | ConvertFrom-Json).ok } catch { }
    Assert ($v2ok -eq $true) "no-image entry is schema-valid"
    Assert (($e2.content | Where-Object { $_.title -eq 'Visual evidence' }).Count -eq 0) "no Visual evidence section when there are no images"
    Assert (@($e2.tags).Count -eq 2 -and ($e2.tags -contains 'raindrop') -and ($e2.tags -contains 'article')) "empty user tags -> just raindrop/article"

    Write-Host "`n[3] missing synthesis file -> falls back, still valid" -ForegroundColor Cyan
    $out3 = Join-Path $tmp 'entry3.json'
    & pwsh -NoProfile -File $Builder -RaindropId 555003 -Title 'Fallback' -Url 'https://example.com/c' `
        -SynthesisFile (Join-Path $tmp 'does-not-exist.md') -FallbackText 'fallback analysis text' `
        -ReadableJson '{}' -ReprocessScript $reproc -OutFile $out3 *> $null
    $e3 = Get-Content $out3 -Raw | ConvertFrom-Json
    $v3ok = $false; try { $v3ok = ((& dnx ActionView.Cli --yes -- validate --file $out3 --strict 2>&1 | Out-String) | ConvertFrom-Json).ok } catch { }
    Assert ($v3ok -eq $true) "fallback entry is schema-valid"
    Assert ((($e3.content | Where-Object { $_.title -eq 'Analysis' }).content[0].body) -match 'fallback analysis text') "uses FallbackText when synthesis file is missing"
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction Ignore
}

Write-Host "`n==== $($script:pass) passed, $($script:fail) failed ====" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
