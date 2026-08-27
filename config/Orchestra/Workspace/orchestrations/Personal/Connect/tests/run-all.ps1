#requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Runs every test for connect-evidence-pack.yaml.
#
#   pwsh -File tests/run-all.ps1
#
# None of these need a running Orchestra host, network access, or MCP auth.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tests = @(
    @{ Name = 'Orchestration structure'  ; Path = Join-Path $here 'test-orchestration-structure.ps1' }
    @{ Name = 'Orchestra engine parse'   ; Path = Join-Path $here 'test-engine-parse.ps1' }
    @{ Name = 'persist-report script'    ; Path = Join-Path $here 'test-persist-report-script.ps1' }
)

$failed = @()
foreach ($t in $tests) {
    Write-Output ''
    Write-Output "=== $($t.Name) ".PadRight(70, '=')
    & pwsh -NoProfile -File $t.Path
    if ($LASTEXITCODE -ne 0) { $failed += $t.Name }
}

Write-Output ''
Write-Output ('=' * 70)
if ($failed.Count) {
    Write-Output "FAILED: $($failed -join ', ')"
    exit 1
}
Write-Output "All $($tests.Count) test suites passed."
