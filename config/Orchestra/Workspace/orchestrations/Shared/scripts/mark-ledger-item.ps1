# mark-ledger-item.ps1
#
# Backs the per-item "Mark done" / "Dismiss" / "Archive" buttons on
# ActionView entries that surface Zakira-tracked items (action items,
# waiting-on asks, etc.). Performs an idempotent get-merge-write on a
# single Zakira.Exchange entry so the entry's Data: payload retains all
# of its existing fields and only the lifecycle fields are updated.
#
# Why a standalone script instead of `tracker-item-mutate` orchestration:
# ActionView CLI actions can call any program at click time. They cannot
# easily invoke an Orchestra orchestration via the data-plane MCP (that
# would require a long-running orchestra-host HTTP call from inside the
# UI action). A small synchronous Pwsh wrapper that does the Zakira
# CLI work in-process is the cheapest reliable path. tracker-item-mutate
# remains the canonical pattern for orchestration-to-orchestration
# mutations.
#
# Usage (called by ActionView action buttons):
#   pwsh -NoProfile -NoLogo -File mark-ledger-item.ps1 `
#     -Category action-items-ledger `
#     -Key ai:<itemId> `
#     -Action completed `
#     [-Reason 'optional free-form reason'] `
#     [-DatabasePath C:\custom\zakira.db]
#
# Action values map to status field updates and a stamped closedAt:
#   completed -> status=completed, closeReason=manual-via-actionview
#   dismissed -> status=dismissed, closeReason=dismissed-via-actionview
#   archived  -> status=archived,  closeReason=archived-via-actionview
#   reopened  -> status=open,      closedAt=null, closeReason=null
#
# Exit codes:
#   0  success
#   1  no entry found at category/key
#   2  CLI invocation failed
#   3  malformed input

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Category,
    [Parameter(Mandatory)][string]$Key,
    [Parameter(Mandatory)][ValidateSet('completed', 'dismissed', 'archived', 'reopened')][string]$Action,
    [string]$Reason = '',
    [string]$DatabasePath = ''
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'

if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $configHome = $env:XDG_CONFIG_HOME
    if ([string]::IsNullOrWhiteSpace($configHome)) {
        $configHome = Join-Path $env:USERPROFILE '.config'
    }
    $DatabasePath = Join-Path $configHome 'orchestra/zakira.db'
}

if (-not (Test-Path -LiteralPath $DatabasePath)) {
    [Console]::Error.WriteLine("Zakira database not found at: $DatabasePath")
    exit 3
}

try { Get-Command dnx -ErrorAction Stop | Out-Null } catch {
    [Console]::Error.WriteLine("dnx is not on PATH; cannot reach Zakira.Exchange CLI.")
    exit 2
}

function Get-DataJsonFromCliOutput {
    param([string[]]$Lines)
    if ($null -eq $Lines -or $Lines.Count -eq 0) { return $null }
    $dataIdx = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ([string]$Lines[$i] -match '^\s*Data:\s*') { $dataIdx = $i; break }
    }
    if ($dataIdx -lt 0) { return $null }
    $endIdx = $Lines.Count
    for ($j = $dataIdx + 1; $j -lt $Lines.Count; $j++) {
        if ([string]$Lines[$j] -match '^\s*(Author|Reason|Tags|Custom|Created|Last Modified):\s*') {
            $endIdx = $j; break
        }
    }
    $span = ($Lines[$dataIdx..($endIdx - 1)] | ForEach-Object { [string]$_ }) -join "`n"
    return ($span -replace '^\s*Data:\s*', '').Trim()
}

function Merge-Deep {
    param($Target, $Patch)
    if ($null -eq $Target) { return $Patch }
    if ($null -eq $Patch) { return $Target }
    if ($Patch -isnot [pscustomobject] -or $Target -isnot [pscustomobject]) {
        return $Patch
    }
    $merged = [ordered]@{}
    foreach ($p in $Target.PSObject.Properties) {
        $merged[$p.Name] = $p.Value
    }
    foreach ($p in $Patch.PSObject.Properties) {
        if ($merged.Contains($p.Name) -and $merged[$p.Name] -is [pscustomobject] -and $p.Value -is [pscustomobject]) {
            $merged[$p.Name] = Merge-Deep -Target $merged[$p.Name] -Patch $p.Value
        } else {
            $merged[$p.Name] = $p.Value
        }
    }
    return [pscustomobject]$merged
}

$nowIso = (Get-Date).ToUniversalTime().ToString('o')

# Build the patch based on action.
$patchObj = switch ($Action) {
    'completed' { [pscustomobject]@{ status = 'completed'; closedAt = $nowIso; closeReason = 'manual-via-actionview' } }
    'dismissed' { [pscustomobject]@{ status = 'dismissed'; closedAt = $nowIso; closeReason = 'dismissed-via-actionview' } }
    'archived'  { [pscustomobject]@{ status = 'archived';  closedAt = $nowIso; closeReason = 'archived-via-actionview'  } }
    'reopened'  { [pscustomobject]@{ status = 'open';      closedAt = $null;   closeReason = $null } }
}

if (-not [string]::IsNullOrWhiteSpace($Reason)) {
    $patchObj | Add-Member -NotePropertyName closeReason -NotePropertyValue $Reason -Force
}
$patchObj | Add-Member -NotePropertyName lastMutatedAt -NotePropertyValue $nowIso -Force
$patchObj | Add-Member -NotePropertyName lastMutatedBy -NotePropertyValue 'actionview-button' -Force

# Get existing entry.
$cliOutput = & dnx Zakira.Exchange --yes -- --db $DatabasePath get $Category $Key 2>&1
$cliExit = $LASTEXITCODE

if ($cliExit -eq 1) {
    [Console]::Error.WriteLine("Entry not found: $Category/$Key")
    exit 1
}
if ($cliExit -ne 0) {
    $cliText = if ($cliOutput -is [array]) { ($cliOutput -join "`n") } else { [string]$cliOutput }
    [Console]::Error.WriteLine("Zakira get failed (exit $cliExit) for $Category/${Key}: $cliText")
    exit 2
}

$dataJson = Get-DataJsonFromCliOutput -Lines $cliOutput
$previousData = $null
if ($dataJson) {
    try {
        $previousData = ConvertFrom-Json -InputObject $dataJson -ErrorAction Stop
    } catch {
        # Hard-fail rather than silently destroying every original field.
        # A parse failure here usually means the stored Data was written
        # by a caller that did not preserve JSON quoting (classic PS 7.x
        # $PSNativeCommandArgumentPassing=Windows bug). Surfacing the
        # error lets the user fix the upstream writer rather than
        # discovering corruption later. Use stderr directly (not
        # Write-Error) so the script's `exit 2` actually runs under
        # $ErrorActionPreference='Stop'.
        [Console]::Error.WriteLine("Failed to parse existing Data payload for $Category/${Key}: $($_.Exception.Message). Refusing to overwrite to avoid silent field loss; fix the upstream writer (likely a missing `$PSNativeCommandArgumentPassing = 'Standard') and retry.")
        exit 2
    }
}

$base = if ($null -eq $previousData) { [pscustomobject]@{} } else { $previousData }
$merged = Merge-Deep -Target $base -Patch $patchObj
$newDataJson = $merged | ConvertTo-Json -Depth 100 -Compress

$reasonText = if ([string]::IsNullOrWhiteSpace($Reason)) { "actionview button -> $Action" } else { $Reason }
$editOutput = & dnx Zakira.Exchange --yes -- --db $DatabasePath edit $Category $Key `
    --data $newDataJson `
    --author 'actionview-button' `
    --reason $reasonText 2>&1
$editExit = $LASTEXITCODE
if ($editExit -ne 0) {
    $editText = if ($editOutput -is [array]) { ($editOutput -join "`n") } else { [string]$editOutput }
    [Console]::Error.WriteLine("Zakira edit failed (exit $editExit) for $Category/${Key}: $editText")
    exit 2
}

# Concise success output for the ActionView toast / log.
"OK $Category/$Key -> $Action @ $nowIso"
exit 0
