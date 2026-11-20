param([string]$RulesJson, [string]$DecisionJson)
$ErrorActionPreference = 'Stop'
$rules = ConvertFrom-Json -InputObject $RulesJson
$intent = $rules.intent
$basis = $rules.basis
if ($rules.needsDecision) {
    $answer = (ConvertFrom-Json -InputObject $DecisionJson).answers.intent
    if ($answer.kind -ne 'choice' -or $answer.tied -ne $false) { throw 'Missing, refused or tied intent; no route selected.' }
    $intent = $answer.value
    $basis = "model selected '$intent' from bookmark metadata"
}
if ($rules.medium -notin @('video','article') -or $intent -notin @('recipe','session','generic')) {
    throw 'Invalid medium or intent; no route selected.'
}
# There are six valid pairs but only five registered processors. Keep the descriptive intent.
$lane = if ($rules.medium -eq 'article' -and $intent -eq 'session') { 'generic' } else { $intent }
[ordered]@{
    medium = $rules.medium
    intent = $intent
    processor = "raindrop-$($rules.medium)-$lane-processor"
    reasoning = "URL rule selected $($rules.medium); $basis."
} | ConvertTo-Json -Compress
