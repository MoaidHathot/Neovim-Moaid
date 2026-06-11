# flag-as-not-an-ask.ps1
#
# Backs the per-item "Not an ask" button on waiting-on-tracker
# ActionView entries. Performs a dual-write:
#
#   1. Marks the ledger entry as dismissed-as-not-an-ask. The waiting-
#      on ledger record's `status` becomes `dismissed`, with a
#      distinctive `closeReason` so the daily summary can distinguish
#      this from user-driven dismissal.
#   2. Creates an entry in the false-positive trainer category
#      (default `ask-extraction-ignore`) so the pass2-verify step of
#      future waiting-on-tracker runs filters out near-duplicate
#      candidates from the same recipient.
#
# The trainer entry is keyed by a SHA1 of (normalizedPattern,
# recipient) so the same (pattern, recipient) pair always hashes to
# the same key. This means repeated "Not an ask" clicks on similar
# messages from the same sender converge on a single trainer entry
# instead of accumulating.
#
# Why a dedicated wrapper instead of teaching mark-ledger-item.ps1
# another -Action: this script needs to READ the original ledger entry
# to extract askText + recipient, COMPUTE the pattern hash, and WRITE
# to two separate Zakira categories. That's enough additional moving
# parts to deserve its own file.
#
# Usage (called by ActionView action buttons):
#   pwsh -NoProfile -NoLogo -File flag-as-not-an-ask.ps1 `
#     -LedgerCategory waiting-on-ledger `
#     -LedgerKey wo:<askIdHash> `
#     [-IgnoreCategory ask-extraction-ignore] `
#     [-DatabasePath C:\custom\zakira.db]
#
# Exit codes:
#   0  success
#   1  ledger entry not found
#   2  CLI invocation failed / malformed data
#   3  bad input

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LedgerCategory,
    [Parameter(Mandatory)][string]$LedgerKey,
    [string]$IgnoreCategory = 'ask-extraction-ignore',
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

function Get-NormalizedPattern {
    # Mirror of the pattern used by waiting-on-tracker's pass2-verify:
    # lowercase, alphanumeric+space only, single-space collapsed, max
    # 80 chars. Stable across runs and across the orchestration and
    # this wrapper.
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $lower = $Text.ToLowerInvariant()
    $stripped = $lower -replace '[^a-z0-9 ]', ''
    $collapsed = ($stripped -replace '\s+', ' ').Trim()
    if ($collapsed.Length -gt 80) { $collapsed = $collapsed.Substring(0, 80) }
    return $collapsed
}

function Get-PatternHash {
    param([string]$Pattern, [string]$Recipient)
    $input = "$Pattern|$Recipient"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($input)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try { $hashBytes = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
    $hex = ($hashBytes | ForEach-Object { $_.ToString('x2') }) -join ''
    return $hex.Substring(0, 16)
}

# Read the ledger entry so we can derive the pattern.
$cliOutput = & dnx Zakira.Exchange --yes -- --db $DatabasePath get $LedgerCategory $LedgerKey 2>&1
$cliExit = $LASTEXITCODE
if ($cliExit -eq 1) {
    [Console]::Error.WriteLine("Ledger entry not found: $LedgerCategory/$LedgerKey")
    exit 1
}
if ($cliExit -ne 0) {
    $cliText = if ($cliOutput -is [array]) { ($cliOutput -join "`n") } else { [string]$cliOutput }
    [Console]::Error.WriteLine("Zakira get failed (exit $cliExit) for $LedgerCategory/${LedgerKey}: $cliText")
    exit 2
}

$dataJson = Get-DataJsonFromCliOutput -Lines $cliOutput
if (-not $dataJson) {
    [Console]::Error.WriteLine("Ledger entry $LedgerCategory/$LedgerKey has no Data payload.")
    exit 2
}

try {
    $ledger = ConvertFrom-Json -InputObject $dataJson -ErrorAction Stop
} catch {
    [Console]::Error.WriteLine("Failed to parse ledger entry payload for $LedgerCategory/${LedgerKey}: $($_.Exception.Message)")
    exit 2
}

$askText   = if ($ledger.PSObject.Properties['askText'])   { [string]$ledger.askText }   else { '' }
$recipient = if ($ledger.PSObject.Properties['recipient']) { [string]$ledger.recipient } else { '' }
$source    = if ($ledger.PSObject.Properties['source'])    { [string]$ledger.source }    else { 'unknown' }

if ([string]::IsNullOrWhiteSpace($askText)) {
    [Console]::Error.WriteLine("Ledger entry $LedgerCategory/$LedgerKey is missing askText; cannot derive ignore pattern.")
    exit 2
}
if ([string]::IsNullOrWhiteSpace($recipient)) {
    # No recipient -> still mark dismissed but skip the trainer write,
    # since the pattern would not be selective enough to be useful.
    Write-Warning "Ledger entry $LedgerCategory/$LedgerKey has no recipient; skipping trainer write but still dismissing the ask."
    $recipient = ''
}

$pattern = Get-NormalizedPattern -Text $askText
$nowIso = (Get-Date).ToUniversalTime().ToString('o')
$trainerWritten = $false
$trainerKey = $null

if (-not [string]::IsNullOrWhiteSpace($recipient) -and -not [string]::IsNullOrWhiteSpace($pattern)) {
    $patternHash = Get-PatternHash -Pattern $pattern -Recipient $recipient
    $trainerKey = "nonask:$patternHash"

    $trainerPayload = [pscustomobject]@{
        pattern         = $pattern
        recipient       = $recipient
        source          = $source
        originalAskId   = $LedgerKey
        originalAskText = $askText
        createdAt       = $nowIso
        createdBy       = 'flag-as-not-an-ask'
    } | ConvertTo-Json -Compress

    # Create (or edit if it already exists, which is fine - the
    # idempotent path means clicking "Not an ask" on the same
    # pattern from the same recipient twice is a no-op write).
    $trainerOut = & dnx Zakira.Exchange --yes -- --db $DatabasePath create $IgnoreCategory $trainerKey `
        --data $trainerPayload `
        --author 'actionview-button' `
        --reason 'not-an-ask false-positive trainer entry' 2>&1
    if ($LASTEXITCODE -ne 0) {
        $trainerOut = & dnx Zakira.Exchange --yes -- --db $DatabasePath edit $IgnoreCategory $trainerKey `
            --data $trainerPayload `
            --author 'actionview-button' `
            --reason 'not-an-ask false-positive trainer entry (refresh)' 2>&1
        if ($LASTEXITCODE -ne 0) {
            $trainerText = if ($trainerOut -is [array]) { ($trainerOut -join "`n") } else { [string]$trainerOut }
            [Console]::Error.WriteLine("Failed to write trainer entry $IgnoreCategory/${trainerKey}: $trainerText")
            exit 2
        }
    }
    $trainerWritten = $true
}

# Dismiss the ledger entry. We do this LAST so that if the trainer
# write fails the ask remains visible for retry.
$dismissPatch = [pscustomobject]@{
    status        = 'dismissed'
    closedAt      = $nowIso
    closeReason   = 'not-an-ask-via-actionview'
    notAnAsk      = $true
    trainerKey    = $trainerKey
    lastMutatedAt = $nowIso
    lastMutatedBy = 'actionview-button'
}

# Compose the merged data preserving every field on the ledger entry.
$merged = [ordered]@{}
foreach ($p in $ledger.PSObject.Properties) { $merged[$p.Name] = $p.Value }
foreach ($p in $dismissPatch.PSObject.Properties) { $merged[$p.Name] = $p.Value }
$mergedJson = ([pscustomobject]$merged) | ConvertTo-Json -Depth 100 -Compress

$editOut = & dnx Zakira.Exchange --yes -- --db $DatabasePath edit $LedgerCategory $LedgerKey `
    --data $mergedJson `
    --author 'actionview-button' `
    --reason 'flagged as not-an-ask via actionview button' 2>&1
if ($LASTEXITCODE -ne 0) {
    $editText = if ($editOut -is [array]) { ($editOut -join "`n") } else { [string]$editOut }
    [Console]::Error.WriteLine("Zakira edit failed for $LedgerCategory/${LedgerKey}: $editText")
    exit 2
}

# Concise success line for the ActionView toast.
$trainerSummary = if ($trainerWritten) { "trainer=$trainerKey" } else { 'trainer=skipped' }
"OK $LedgerCategory/$LedgerKey -> not-an-ask @ $nowIso ($trainerSummary)"
exit 0
