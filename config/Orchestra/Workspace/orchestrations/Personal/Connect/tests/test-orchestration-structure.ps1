#requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$yamlPath = 'P:\Github\Neovim-Moaid\config\Orchestra\workspace\orchestrations\Personal\Connect\connect-evidence-pack.yaml'
$catalog  = 'P:\Github\Neovim-Moaid\config\Orchestra\orchestra.mcp.json'

$fail = [System.Collections.Generic.List[string]]::new()
$warn = [System.Collections.Generic.List[string]]::new()
function Fail($m) { $fail.Add($m) }
function Warn($m) { $warn.Add($m) }
function V($o, [string]$k) {
    if ($null -eq $o) { return $null }
    if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($k)) { return $o[$k] } else { return $null } }
    if ($o.PSObject.Properties.Name -contains $k) { return $o.$k }
    return $null
}

# --------------------------------------------------------------- 1. YAML parse
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Install-Module powershell-yaml -Scope CurrentUser -Force -AllowClobber | Out-Null
}
Import-Module powershell-yaml -ErrorAction Stop
$raw = Get-Content -LiteralPath $yamlPath -Raw
try { $doc = ConvertFrom-Yaml $raw } catch { Fail "YAML does not parse: $($_.Exception.Message)"; $doc = $null }
if (-not $doc) { $fail | ForEach-Object { Write-Output "FAIL  $_" }; exit 1 }
Write-Output "PASS  YAML parses"

# ------------------------------------------------------------ 2. encoding/EOL
$bytes = [System.IO.File]::ReadAllBytes($yamlPath)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { Fail 'File has a UTF-8 BOM' } else { Write-Output 'PASS  No BOM' }
if ($raw.Contains("`r")) { Fail 'File contains CR (^M) characters' } else { Write-Output 'PASS  LF-only line endings' }

# -------------------------------------------------------- 3. required top keys
foreach ($k in 'name','description','steps','defaultModel') {
    if (-not $doc.Contains($k)) { Fail "Missing top-level key: $k" }
}
if ($doc.name -ne 'connect-evidence-pack') { Fail "Unexpected name: $($doc.name)" }
if ($doc.defaultModel -ne 'claude-opus-4.8') { Fail "defaultModel must be claude-opus-4.8 (AGENTS.md), got: $($doc.defaultModel)" }
Write-Output "PASS  Top-level keys (name=$($doc.name), model=$($doc.defaultModel))"

# ------------------------------------------------- 4. no ephemeral remnants
foreach ($t in @($doc.tags)) {
    if ($t -in @('ephemeral','temp','self-healing')) { Fail "Ephemeral tag left behind: $t" }
}
if ($doc.Contains('metadata')) {
    foreach ($k in 'ephemeral','selfHealing','attempt','parentRunId') {
        if (($doc.metadata -is [System.Collections.IDictionary] -and $doc.metadata.Contains($k))) { Fail "Ephemeral metadata left behind: metadata.$k" }
    }
}
Write-Output "PASS  No ephemeral tags/metadata"

# --------------------------------------------------------------- 5. inputs
$inputNames = @()
if ($doc.Contains('inputs')) { $inputNames = @($doc.inputs.Keys) }
foreach ($req in 'startDate','endDate') {
    if ($req -notin $inputNames) { Fail "Missing required input: $req" }
    elseif (-not (V $doc.inputs[$req] 'required')) { Fail "Input '$req' should be required" }
}
foreach ($opt in 'outputDirectory','domainHints') {
    if ($opt -notin $inputNames) { Fail "Missing optional input: $opt" }
    elseif ((V $doc.inputs[$opt] 'required')) { Fail "Input '$opt' should be optional" }
}
Write-Output "PASS  Inputs: $($inputNames -join ', ')"

# ------------------------------------------- 6. steps: names, graph, cycles
$steps = @($doc.steps)
$names = @($steps | ForEach-Object { V $_ 'name' })
$dupes = @($names | Group-Object | Where-Object Count -gt 1)
foreach ($d in $dupes) { Fail "Duplicate step name: $($d.Name)" }

$nameSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$names)
foreach ($s in $steps) {
    foreach ($dep in @(V $s 'dependsOn')) {
        if ($dep -and -not $nameSet.Contains($dep)) { Fail "Step '$((V $s 'name'))' dependsOn unknown step '$dep'" }
    }
}

# topological sort -> cycle detection
$indeg = @{}; $adj = @{}
foreach ($n in $names) { $indeg[$n] = 0; $adj[$n] = [System.Collections.Generic.List[string]]::new() }
foreach ($s in $steps) {
    foreach ($dep in @(V $s 'dependsOn')) {
        if ($dep -and $nameSet.Contains($dep)) { $adj[$dep].Add((V $s 'name')); $indeg[(V $s 'name')]++ }
    }
}
$q = [System.Collections.Generic.Queue[string]]::new()
foreach ($n in $names) { if ($indeg[$n] -eq 0) { $q.Enqueue($n) } }
$seen = 0
while ($q.Count) { $n = $q.Dequeue(); $seen++; foreach ($m in $adj[$n]) { $indeg[$m]--; if ($indeg[$m] -eq 0) { $q.Enqueue($m) } } }
if ($seen -ne $names.Count) { Fail "Dependency cycle detected ($seen of $($names.Count) steps reachable)" }
Write-Output "PASS  $($names.Count) steps, dependency graph acyclic, all refs resolve"

# --------------------------------------- 7. required new steps are present
foreach ($n in 'fetch-work-items-worked-on','aggregate-timeline','persist-report') {
    if ($n -notin $names) { Fail "Expected new step missing: $n" }
}
Write-Output 'PASS  New steps present (fetch-work-items-worked-on, aggregate-timeline, persist-report)'

# persist-report must not depend on the review loop
$persist = $steps | Where-Object name -eq 'persist-report'
if (@(V $persist 'dependsOn') -contains 'review-report') { Fail 'persist-report must not depend on review-report (defeats durability)' }
if (@(V $persist 'dependsOn') -notcontains 'render-report') { Fail 'persist-report must depend on render-report' }
if ((V $persist 'type') -ne 'Script') { Fail "persist-report must be a Script step, got $((V $persist 'type'))" }
if (-not (V $persist 'shell')) { Fail 'persist-report missing required "shell"' }
Write-Output "PASS  persist-report: Script/$((V $persist 'shell')), dependsOn=[$(@(V $persist 'dependsOn') -join ',')]"

# new work-item pass must feed aggregation
$aggWi = $steps | Where-Object name -eq 'aggregate-work-items'
if (@(V $aggWi 'dependsOn') -notcontains 'fetch-work-items-worked-on') { Fail 'aggregate-work-items does not depend on fetch-work-items-worked-on' }
if ((V $aggWi 'userPrompt') -notmatch 'fetch-work-items-worked-on\.output') { Fail 'aggregate-work-items prompt does not consume fetch-work-items-worked-on.output' }
Write-Output 'PASS  work-item gap closed (new pass wired into aggregation)'

$render = $steps | Where-Object name -eq 'render-report'
if (@(V $render 'dependsOn') -notcontains 'aggregate-timeline') { Fail 'render-report does not depend on aggregate-timeline' }
if ((V $render 'userPrompt') -notmatch 'aggregate-timeline\.output') { Fail 'render-report prompt does not consume aggregate-timeline.output' }
Write-Output 'PASS  timeline wired into render-report'

# ------------------------------------------------- 8. MCP references resolve
$declared = @()
if ($doc.Contains('mcps')) { $declared = @($doc.mcps | ForEach-Object { V $_ 'name' }) }
$known = @()
if (Test-Path -LiteralPath $catalog) {
    $known = @((Get-Content -LiteralPath $catalog -Raw | ConvertFrom-Json).mcps | ForEach-Object { V $_ 'name' })
} else { Warn "MCP catalog not found at $catalog" }
$available = @($declared + $known | Sort-Object -Unique)
$used = @($steps | ForEach-Object { V $_ 'mcps' } | Where-Object { $_ } | ForEach-Object { $_ } | Sort-Object -Unique)
foreach ($m in $used) { if ($m -notin $available) { Fail "Step references unknown MCP '$m' (not inline, not in catalog)" } }
Write-Output "PASS  MCPs used [$($used -join ', ')] all resolve (inline: $($declared -join ',') | catalog: $($known.Count) entries)"

# ------------------------------- 9. template refs point at real steps/inputs
$allText = $raw
$stepRefs = [regex]::Matches($allText, '\{\{\s*([a-zA-Z0-9_-]+)\.output\s*\}\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
foreach ($r in $stepRefs) { if (-not $nameSet.Contains($r)) { Fail "Template references output of unknown step '$r'" } }
Write-Output "PASS  $($stepRefs.Count) distinct step-output refs all resolve"

$paramRefs = [regex]::Matches($allText, '\{\{\s*param\.([a-zA-Z0-9_]+)\s*\}\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
foreach ($r in $paramRefs) { if ($r -notin $inputNames) { Fail "Template references undeclared input '{{param.$r}}'" } }
Write-Output "PASS  param refs resolve: $($paramRefs -join ', ')"

$varNames = @(); if ($doc.Contains('variables')) { $varNames = @($doc.variables.Keys) }
$varRefs = [regex]::Matches($allText, '\{\{\s*vars\.([a-zA-Z0-9_]+)\s*\}\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
foreach ($r in $varRefs) { if ($r -notin $varNames) { Fail "Template references undeclared variable '{{vars.$r}}'" } }
Write-Output "PASS  vars refs resolve: $($varRefs -join ', ')"

# -------------------------------------- 10. no hardcoded identity / internals
foreach ($p in 'moaid','hathot','msazure','visualstudio\.com','dev\.azure\.com','@microsoft\.com') {
    $m = [regex]::Matches($allText, $p, 'IgnoreCase')
    if ($m.Count -gt 0) {
        $ctx = @()
        foreach ($x in $m) {
            $lineNo = ($allText.Substring(0, $x.Index) -split "`n").Count
            $line = ($allText -split "`n")[$lineNo - 1]
            if ($line -notmatch 'raw\.githubusercontent\.com|MoaidHathot/orchestra') { $ctx += "line ${lineNo}: $($line.Trim())" }
        }
        if ($ctx) { Fail "Hardcoded internal/identity string '$p' -> $($ctx -join ' | ')" }
    }
}
Write-Output 'PASS  No hardcoded identity, org URLs, or emails'

# ------------------------------------------------------------------- verdict
Write-Output ''
foreach ($w in $warn) { Write-Output "WARN  $w" }
if ($fail.Count) {
    foreach ($f in $fail) { Write-Output "FAIL  $f" }
    Write-Output ''
    Write-Output "RESULT: $($fail.Count) failure(s)"
    exit 1
}
Write-Output "RESULT: all checks passed ($($names.Count) steps)"
