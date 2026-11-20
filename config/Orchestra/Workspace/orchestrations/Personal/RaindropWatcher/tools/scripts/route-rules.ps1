# Pure classification of bookmark metadata; never dereference the URL.
param([string]$Url, [string]$Title, [string]$TagsJson, [string]$Note)
$ErrorActionPreference = 'Stop'
$uri = [uri]$Url
if (!$uri.IsAbsoluteUri) { throw 'Expected an absolute bookmark URL.' }
$hostName = $uri.IdnHost.ToLowerInvariant().TrimEnd('.') -replace '^www\.', ''
$path = $uri.AbsolutePath
$video = $uri.IsFile -or $path -match '\.(mp4|mov|mkv|webm|m4v)$' -or
    $hostName -in @('youtube.com','m.youtube.com','youtu.be','vimeo.com','player.vimeo.com','web.microsoftstream.com','medius.studios.ms') -or
    ($hostName -like '*.sharepoint.com' -and $path -match '/stream\.aspx$' -and $uri.Query) -or
    ($hostName -in @('build.microsoft.com','ignite.microsoft.com') -and $path -match '^/sessions/') -or
    ($hostName -eq 'learn.microsoft.com' -and $path -match '/sessions/') -or
    ($hostName -eq 'events.microsoft.com' -and $path -match '/session/') -or
    (($hostName -eq 'twitch.tv' -or $hostName -like '*.twitch.tv') -and $path -match '^/videos/') -or
    ($hostName -eq 'tiktok.com' -and $path -match '^/@[^/]+/video/')

$tags = ConvertFrom-Json -InputObject $TagsJson -NoEnumerate
if ($tags -isnot [array]) { throw 'tags must be a JSON array.' }
$intentTags = @{}
foreach ($tag in $tags) {
    if ($tag -isnot [string]) { throw 'Expected string tags.' }
    $key = $tag.Trim().ToLowerInvariant()
    if ($key -in @('recipe','cooking','food')) { $intentTags['recipe'] = $key }
    if ($key -in @('session','talk','lecture','keynote','conference','webinar','course')) { $intentTags['session'] = $key }
}
$intent = $null
$basis = $null
if ($intentTags.Count -gt 1) { throw 'Conflicting explicit recipe and session tags; no route selected.' }
if ($intentTags.Count -eq 1) {
    $intent = @($intentTags.Keys)[0]
    $basis = "explicit tag '$($intentTags[$intent])'"
} elseif ($hostName -in @('build.microsoft.com','ignite.microsoft.com','events.microsoft.com','learn.microsoft.com','web.microsoftstream.com') -and $path -match 'session|keynote|talk') {
    $intent = 'session'
    $basis = 'known Microsoft session URL'
}

[ordered]@{
    medium = if ($video) { 'video' } else { 'article' }
    intent = $intent
    basis = $basis
    needsDecision = $null -eq $intent
    # A JSON string so Orchestra can extract it as a template leaf without interpolating JSON syntax.
    evidence = [ordered]@{ host = $hostName; path = $path; title = $Title; tags = $tags; note = $Note } | ConvertTo-Json -Compress
} | ConvertTo-Json -Compress
