#requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Integration test: parse the promoted orchestration with Orchestra's own engine,
# not a third-party YAML reader. Catches anything the schema check cannot.

$binDir  = 'P:\Github\Orchestra\src\Orchestra.Cli\bin\Release\net10.0'
$yaml    = 'P:\Github\Neovim-Moaid\config\Orchestra\workspace\orchestrations\Personal\Connect\connect-evidence-pack.yaml'
$catalog = 'P:\Github\Neovim-Moaid\config\Orchestra\orchestra.mcp.json'

# Pre-load every assembly in the CLI output folder so the CLR never needs an
# AssemblyResolve hook. A PowerShell scriptblock handler would otherwise be
# invoked on a non-PowerShell thread during process teardown, which crashes with
# "There is no Runspace available to run scripts in this thread".
foreach ($dll in (Get-ChildItem -LiteralPath $binDir -Filter '*.dll' -File)) {
    try { [System.Reflection.Assembly]::LoadFrom($dll.FullName) | Out-Null } catch { }
}
$engine = [System.Reflection.Assembly]::LoadFrom((Join-Path $binDir 'Orchestra.Engine.dll'))

$parser = $engine.GetType('Orchestra.Engine.OrchestrationParser')
if (-not $parser) { throw 'OrchestrationParser type not found in Orchestra.Engine.dll' }
$mcpType = $engine.GetType('Orchestra.Engine.Mcp')
if (-not $mcpType) { throw 'Mcp type not found' }

# Build the available-MCP set from the real catalog so MCP references resolve.
$names = @((Get-Content -LiteralPath $catalog -Raw | ConvertFrom-Json).mcps | ForEach-Object { $_.name })
$mcps = [System.Array]::CreateInstance($mcpType, $names.Count)
for ($i = 0; $i -lt $names.Count; $i++) {
    $m = [System.Activator]::CreateInstance($mcpType)
    $prop = $mcpType.GetProperty('Name')
    if ($prop -and $prop.CanWrite) { $prop.SetValue($m, $names[$i]) }
    $mcps.SetValue($m, $i)
}

$method = $parser.GetMethods() | Where-Object {
    $_.Name -eq 'ParseOrchestrationFile' -and $_.GetParameters().Count -eq 2
} | Select-Object -First 1
if (-not $method) { throw 'ParseOrchestrationFile(string, Mcp[]) overload not found' }

try {
    $o = $method.Invoke($null, @($yaml, $mcps))
} catch {
    $inner = $_.Exception
    while ($inner.InnerException) { $inner = $inner.InnerException }
    Write-Output "FAIL  Orchestra engine rejected the orchestration:"
    Write-Output "      $($inner.GetType().Name): $($inner.Message)"
    exit 1
}

$steps = $o.Steps
Write-Output "PASS  Orchestra engine parsed the orchestration"
Write-Output "      Name        : $($o.Name)"
Write-Output "      Model       : $($o.DefaultModel)"
Write-Output "      Steps       : $($steps.Count)"

$byName = @{}
foreach ($s in $steps) { $byName[$s.Name] = $s }

$expected = 'fetch-work-items-worked-on', 'aggregate-timeline', 'persist-report'
foreach ($e in $expected) {
    if (-not $byName.ContainsKey($e)) { Write-Output "FAIL  engine did not materialise step '$e'"; exit 1 }
}
Write-Output "PASS  All three new steps materialised by the engine"

$persist = $byName['persist-report']
Write-Output "      persist-report type: $($persist.GetType().Name)"

# Every dependsOn must resolve against engine-materialised names.
$bad = @()
foreach ($s in $steps) {
    foreach ($d in @($s.DependsOn)) {
        if ($d -and -not $byName.ContainsKey($d)) { $bad += "$($s.Name) -> $d" }
    }
}
if ($bad.Count) { Write-Output "FAIL  unresolved dependencies: $($bad -join ', ')"; exit 1 }
Write-Output "PASS  All dependsOn edges resolve post-parse"

Write-Output ''
Write-Output 'RESULT: engine-level parse test passed'
