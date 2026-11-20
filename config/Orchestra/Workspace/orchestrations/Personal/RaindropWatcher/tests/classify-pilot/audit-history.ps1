# Offline: estimate which historical bookmarks would have needed inference. Outputs counts, not inputs.
param([Parameter(Mandatory)][string]$HistoryDir)
$ErrorActionPreference = 'Stop'
$latest = @{}
$count = 0
foreach ($dir in Get-ChildItem -LiteralPath $HistoryDir -Directory) {
    $file = Join-Path $dir.FullName 'run.json'
    if (!(Test-Path -LiteralPath $file)) { continue }
    $run = [IO.File]::ReadAllText($file) | ConvertFrom-Json -AsHashtable -DateKind String -Depth 100
    if ($run.orchestrationName -ne 'raindrop-processor') { continue }
    $count++
    $p = $run.parameters
    if (!$p.url -or !$p.raindropId) { continue }
    $started = [DateTimeOffset]::Parse($run.startedAt)
    if (!$latest.Contains($p.raindropId) -or $started -gt $latest[$p.raindropId].started) {
        $latest[$p.raindropId] = @{started = $started; params = $p}
    }
}
$counts = [ordered]@{ records = $count; uniqueBookmarks = $latest.Count; hardRoute = 0; needsDecision = 0; invalid = 0 }
foreach ($item in $latest.Values) {
    $p = $item.params
    try {
        $tags = if ($p.tags) { $p.tags } else { '[]' }
        $rule = & (Join-Path $PSScriptRoot '../../tools/scripts/route-rules.ps1') $p.url $p.title $tags ([string]$p.note) | ConvertFrom-Json
        if ($rule.needsDecision) { $counts.needsDecision++ } else { $counts.hardRoute++ }
    } catch { $counts.invalid++ }
}
$counts | ConvertTo-Json
