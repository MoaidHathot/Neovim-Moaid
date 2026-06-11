# resolve-user-identity.ps1
#
# Resolves the signed-in user's identity (UPN, displayName, Graph id)
# without ever hardcoding it in an orchestration file. Caches the result
# in Zakira (default category `user-identity:cache`, key `default`) with
# a configurable TTL so repeat callers do not re-hit Graph.
#
# Token handling:
#   - NEVER stores a token anywhere. The Microsoft Graph access token
#     comes from `az account get-access-token --scope https://graph.
#     microsoft.com/.default` per call when the cache misses. The az CLI
#     manages its own token cache (DPAPI-encrypted on Windows via the
#     MSAL Windows-Hello / Web Account Manager integration). We do not
#     copy the token into Zakira, into the orchestration logs, or into
#     any environment variable.
#   - For testing only, the env var GRAPH_ACCESS_TOKEN_PREFILL may be
#     set in-memory by a parent process. It is read once and never
#     written anywhere. Do NOT persist this env var to your shell
#     profile or any dotfile.
#
# Inputs (positional args):
#   $args[0]   dbPath            (Zakira SQLite db path)
#   $args[1]   cacheCategory     (default 'user-identity:cache')
#   $args[2]   cacheKey          (default 'default')
#   $args[3]   maxAgeHours       (default '24')
#   $args[4]   forceRefreshRaw   (default 'false'; 'true' to bypass cache)
#
# Output JSON:
#   {
#     "uniqueName":  "moaidhathot@microsoft.com",
#     "displayName": "Moaid Hathot",
#     "id":          "<graph object id when available>",
#     "source":      "cache | az+graph | az-only",
#     "resolvedAt":  "<UTC iso>",
#     "cacheAgeMin": <number or null>
#   }
#
# IMPORTANT: Invoked via positional `$args` from Orchestra `scriptFile:`
# steps. Do NOT add a `[CmdletBinding()] param()` block; that would
# break the implicit positional invocation.

$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'

$dbPath          = $args[0]
$cacheCategory   = if ($args.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace([string]$args[1])) { [string]$args[1] } else { 'user-identity:cache' }
$cacheKey        = if ($args.Count -gt 2 -and -not [string]::IsNullOrWhiteSpace([string]$args[2])) { [string]$args[2] } else { 'default' }
$maxAgeHours     = if ($args.Count -gt 3 -and -not [string]::IsNullOrWhiteSpace([string]$args[3])) { [int]$args[3] } else { 24 }
$forceRefreshRaw = if ($args.Count -gt 4) { [string]$args[4] } else { 'false' }
$forceRefresh    = [string]::Equals($forceRefreshRaw.Trim(), 'true', [System.StringComparison]::OrdinalIgnoreCase)

if ([string]::IsNullOrWhiteSpace($dbPath)) {
    [Console]::Error.WriteLine("dbPath argument is required.")
    exit 3
}
if (-not (Test-Path -LiteralPath $dbPath)) {
    [Console]::Error.WriteLine("Zakira database not found at: $dbPath")
    exit 3
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

# Cache lookup.
if (-not $forceRefresh) {
    $cacheOut = & dnx Zakira.Exchange --yes -- --db $dbPath get $cacheCategory $cacheKey 2>&1
    if ($LASTEXITCODE -eq 0) {
        $dataJson = Get-DataJsonFromCliOutput -Lines $cacheOut
        if ($dataJson) {
            try {
                $cached = ConvertFrom-Json -InputObject $dataJson -ErrorAction Stop
                $resolvedAtRaw = if ($cached.PSObject.Properties['resolvedAt']) { [string]$cached.resolvedAt } else { '' }
                if (-not [string]::IsNullOrWhiteSpace($resolvedAtRaw)) {
                    try {
                        $resolvedUtc = [datetimeoffset]::Parse($resolvedAtRaw, [System.Globalization.CultureInfo]::InvariantCulture).UtcDateTime
                        $ageMin = ((Get-Date).ToUniversalTime() - $resolvedUtc).TotalMinutes
                        if ($ageMin -lt ($maxAgeHours * 60)) {
                            # Cache hit - emit cached payload with refreshed `source`.
                            $cached | Add-Member -NotePropertyName source -NotePropertyValue 'cache' -Force
                            $cached | Add-Member -NotePropertyName cacheAgeMin -NotePropertyValue ([math]::Round($ageMin, 1)) -Force
                            $cached | ConvertTo-Json -Depth 20 -Compress
                            exit 0
                        }
                    } catch { }
                }
            } catch { }
        }
    }
}

# Cache miss / forced refresh - resolve via az + Graph.
try { Get-Command az -ErrorAction Stop | Out-Null } catch {
    [Console]::Error.WriteLine("az CLI is not on PATH; cannot resolve identity.")
    exit 2
}

# Step 1: UPN via az account show (cheapest, always available when signed in).
$azShowRaw = & az account show -o json 2>&1
if ($LASTEXITCODE -ne 0) {
    $azText = if ($azShowRaw -is [array]) { ($azShowRaw -join "`n") } else { [string]$azShowRaw }
    [Console]::Error.WriteLine("az account show failed (exit $LASTEXITCODE): $azText. Sign in with 'az login' first.")
    exit 2
}
$azText = if ($azShowRaw -is [array]) { ($azShowRaw | ForEach-Object { [string]$_ }) -join "`n" } else { [string]$azShowRaw }
try {
    $azObj = ConvertFrom-Json -InputObject $azText -ErrorAction Stop
} catch {
    [Console]::Error.WriteLine("az account show returned non-JSON output: $azText")
    exit 2
}
$upn = if ($azObj.user -and $azObj.user.name) { [string]$azObj.user.name } else { '' }
if ([string]::IsNullOrWhiteSpace($upn)) {
    [Console]::Error.WriteLine("az account show did not include user.name; cannot resolve UPN.")
    exit 2
}

# Step 2: Graph /me for displayName + id (best-effort; az UPN is enough by itself).
$displayName = $null
$graphId = $null
$source = 'az-only'

# Read a token from env first (in-memory only); fall back to az.
$token = $env:GRAPH_ACCESS_TOKEN_PREFILL
if ([string]::IsNullOrWhiteSpace($token)) {
    $tokenRaw = & az account get-access-token --scope 'https://graph.microsoft.com/.default' -o json 2>&1
    if ($LASTEXITCODE -eq 0) {
        $tokenText = if ($tokenRaw -is [array]) { ($tokenRaw | ForEach-Object { [string]$_ }) -join "`n" } else { [string]$tokenRaw }
        try {
            $tokenObj = ConvertFrom-Json -InputObject $tokenText -ErrorAction Stop
            $token = [string]$tokenObj.accessToken
        } catch { }
    }
}

if (-not [string]::IsNullOrWhiteSpace($token)) {
    try {
        $meResp = Invoke-RestMethod -Method Get -Uri 'https://graph.microsoft.com/v1.0/me' `
            -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json' } `
            -TimeoutSec 15
        if ($meResp) {
            if ($meResp.PSObject.Properties['displayName'] -and -not [string]::IsNullOrWhiteSpace([string]$meResp.displayName)) {
                $displayName = [string]$meResp.displayName
            }
            if ($meResp.PSObject.Properties['id']) {
                $graphId = [string]$meResp.id
            }
            # Prefer Graph UPN when available (canonical).
            if ($meResp.PSObject.Properties['userPrincipalName'] -and -not [string]::IsNullOrWhiteSpace([string]$meResp.userPrincipalName)) {
                $upn = [string]$meResp.userPrincipalName
            }
            $source = 'az+graph'
        }
    } catch {
        # Graph call failed - keep az-only result.
    }
}

# Discard the token from memory ASAP. PowerShell will GC, but make
# intent explicit so a future reader does not start logging it.
$token = $null
Remove-Variable -Name token -ErrorAction SilentlyContinue

# Best-effort displayName fallback: derive from UPN local part.
if ([string]::IsNullOrWhiteSpace($displayName)) {
    $local = $upn.Split('@')[0]
    $cleaned = ($local -replace '[^a-zA-Z]+', ' ').Trim()
    if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
        $info = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
        $displayName = $info.ToTitleCase($cleaned.ToLowerInvariant())
    } else {
        $displayName = $local
    }
}

$nowIso = (Get-Date).ToUniversalTime().ToString('o')
$result = [pscustomobject]@{
    uniqueName  = $upn
    displayName = $displayName
    id          = $graphId
    source      = $source
    resolvedAt  = $nowIso
    cacheAgeMin = $null
}

# Write to cache.
$payload = $result | ConvertTo-Json -Depth 10 -Compress
$writeOut = & dnx Zakira.Exchange --yes -- --db $dbPath edit $cacheCategory $cacheKey `
    --data $payload --author 'resolve-user-identity' --reason 'identity refresh' 2>&1
if ($LASTEXITCODE -ne 0) {
    $writeOut = & dnx Zakira.Exchange --yes -- --db $dbPath create $cacheCategory $cacheKey `
        --data $payload --author 'resolve-user-identity' --reason 'identity seed' 2>&1
    if ($LASTEXITCODE -ne 0) {
        $writeText = if ($writeOut -is [array]) { ($writeOut -join "`n") } else { [string]$writeOut }
        # Cache write failure is non-fatal; still emit the resolved identity.
        [Console]::Error.WriteLine("Warning: identity cache write failed: $writeText")
    }
}

$result | ConvertTo-Json -Depth 10 -Compress
exit 0
