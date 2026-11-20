# Credential-free contract tests against the production classifier scripts.
$ErrorActionPreference = 'Stop'
function Check($condition, [string]$message) { if (!$condition) { throw $message } }
function Rejects([scriptblock]$action, [string]$message) {
    try { & $action | Out-Null } catch { return }
    throw "Expected rejection: $message"
}
$rulesScript = Join-Path $PSScriptRoot '../../tools/scripts/route-rules.ps1'
$resultScript = Join-Path $PSScriptRoot '../../tools/scripts/route-result.ps1'
$urls = @(
    @('https://www.youtube.com/watch?v=1', 'video'), @('https://m.youtube.com/shorts/1', 'video'),
    @('https://youtu.be/1', 'video'), @('https://vimeo.com/1', 'video'), @('https://player.vimeo.com/video/1', 'video'),
    @('https://tenant.sharepoint.com/a/stream.aspx?id=1', 'video'), @('https://tenant.sharepoint.com/a/doc', 'article'),
    @('https://web.microsoftstream.com/video/1', 'video'), @('https://build.microsoft.com/sessions/1', 'video'),
    @('https://ignite.microsoft.com/sessions/1', 'video'), @('https://learn.microsoft.com/en-us/sessions/1', 'video'),
    @('https://medius.studios.ms/channel', 'video'), @('https://events.microsoft.com/en-us/session/1', 'video'),
    @('https://www.twitch.tv/videos/1', 'video'), @('https://www.tiktok.com/@author/video/1', 'video'),
    @('https://cdn.example.org/demo.MKV?version=1', 'video'), @('file:///D:/media/movie', 'video'),
    @('https://youtube.com.example.org/video/1', 'article'), @('https://example.org/a?download=a.mp4', 'article'),
    @('https://learn.microsoft.com/en-us/dotnet/guide', 'article')
)
foreach ($case in $urls) {
    $rules = & $rulesScript $case[0] 'fixture' '[]' '' | ConvertFrom-Json
    Check ($rules.medium -ceq $case[1]) "Wrong medium for $($case[0])"
}
# All six pairs, including article/session. A bogus model payload on a hard override is ignored.
foreach ($medium in 'video','article') {
    foreach ($intent in 'recipe','session','generic') {
        $url = if ($medium -eq 'video') { 'https://youtu.be/1' } else { 'https://example.org/p' }
        $tag = @{recipe='["COOKING","food"]'; session='["TaLk"]'; generic='[]'}[$intent]
        $json = & $rulesScript $url 'Title' $tag "Note with `"quotes`"`nand non-ASCII: café."
        $r = $json | ConvertFrom-Json
        Check ($r.needsDecision -eq ($intent -eq 'generic')) 'Wrong intent override'
        Check (($r.evidence | ConvertFrom-Json).note -ceq "Note with `"quotes`"`nand non-ASCII: café.") 'Evidence escaping'
        $answer = if ($r.needsDecision) { '{"answers":{"intent":{"kind":"choice","value":"generic","tied":false}}}' } else { 'not a model response' }
        $out = & $resultScript $json $answer | ConvertFrom-Json
        $lane = if ($medium -eq 'article' -and $intent -eq 'session') { 'generic' } else { $intent }
        Check ((($out.PSObject.Properties.Name | Sort-Object) -join ',') -ceq 'intent,medium,processor,reasoning') 'Unexpected output fields'
        Check ($out.intent -ceq $intent -and $out.medium -ceq $medium -and $out.processor -ceq "raindrop-$medium-$lane-processor" -and $out.reasoning) 'Invalid route envelope'
    }
}
$tagged = & $rulesScript 'https://build.microsoft.com/sessions/1' 'A talk' '["Food"]' '' | ConvertFrom-Json
Check (!$tagged.needsDecision -and $tagged.intent -ceq 'recipe') 'A Microsoft session URL must not override a user tag'
Rejects { & $rulesScript 'https://youtu.be/test' 'Title' '["talk","recipe"]' '' } 'conflicting explicit overrides'
Rejects { & $rulesScript 'https://youtu.be/test' 'Title' '"recipe"' '' } 'tags not an array'
$raw = & $rulesScript 'https://example.org/p' 'Title' '[]' ''
foreach ($badAnswer in @('', '{}', '{"answers":{"intent":{"kind":"refused"}}}',
    '{"answers":{"intent":{"kind":"choice","value":"generic","tied":true}}}',
    '{"answers":{"intent":{"kind":"choice","value":"nonexistent","tied":false}}}')) {
    Rejects { & $resultScript $raw $badAnswer } 'absent, refused, tied or unrecognized intent'
}
'PASS: medium URL rules, six contract routes, precedence, evidence escaping, and failure cases.'
