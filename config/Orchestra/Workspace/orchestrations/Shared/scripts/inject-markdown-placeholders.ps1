# inject-markdown-placeholders.ps1
#
# Generalizes the `<<FULL_MARKDOWN:<id>>>` substitution pattern first
# introduced in meeting-action-items-extractor + meeting-prep-brief.
#
# Inputs (positional args):
#   $args[0]   ActionView entry JSON (string)
#   $args[1]   id -> markdown lookup JSON (string; object of "<id>": "<md>")
#
# Behaviour:
#   - Parses both inputs as JSON.
#   - Walks the entire entry tree.
#   - For every node that has type=='markdown' and a `body` matching the
#     pattern ^<<FULL_MARKDOWN:(<id>)>>$, replaces the body with the
#     verbatim markdown from the lookup map.
#   - Unsubstituted placeholders are logged to stderr (Write-Warning) but
#     do NOT fail the script - they remain in the entry as a visible
#     diagnostic the user can act on.
#
# Output:
#   - The mutated entry JSON, compact, on stdout.
#
# IMPORTANT: This script is invoked via positional `$args` (both by
# Orchestra `scriptFile:` steps and by direct `pwsh -File` callers).
# Do NOT add a `[CmdletBinding()] param()` block; PowerShell rejects
# untyped positional arguments when an empty param block is declared,
# which breaks the natural `$args[0..N]` contract.

$ErrorActionPreference = 'Stop'

$entryJsonRaw = $args[0]
$lookupRaw    = $args[1]

if ([string]::IsNullOrWhiteSpace($entryJsonRaw)) {
    throw 'inject-markdown-placeholders: entry JSON input is empty.'
}
if ([string]::IsNullOrWhiteSpace($lookupRaw)) {
    $lookupRaw = '{}'
}

$entry  = ConvertFrom-Json -InputObject $entryJsonRaw -Depth 100 -ErrorAction Stop
$lookup = ConvertFrom-Json -InputObject $lookupRaw    -Depth 5   -ErrorAction Stop

$lookupMap = @{}
if ($null -ne $lookup) {
    foreach ($prop in $lookup.PSObject.Properties) {
        $lookupMap[[string]$prop.Name] = [string]$prop.Value
    }
}

$script:substituted   = 0
$script:unsubstituted = New-Object System.Collections.Generic.List[string]
$placeholderRegex     = '^<<FULL_MARKDOWN:([^>]+)>>$'

function Invoke-FullMarkdownWalk {
    param($Node)
    if ($null -eq $Node) { return }
    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        foreach ($item in $Node) { Invoke-FullMarkdownWalk -Node $item }
        return
    }
    if ($Node -isnot [pscustomobject]) { return }

    $typeProp = $Node.PSObject.Properties['type']
    $bodyProp = $Node.PSObject.Properties['body']
    if ($typeProp -and $bodyProp -and ([string]$typeProp.Value) -eq 'markdown') {
        $body = [string]$bodyProp.Value
        if ($body -match $placeholderRegex) {
            $id = $Matches[1].Trim()
            if ($lookupMap.ContainsKey($id)) {
                $Node.body = $lookupMap[$id]
                $script:substituted++
            } else {
                [void]$script:unsubstituted.Add($id)
            }
        }
    }

    foreach ($prop in $Node.PSObject.Properties) {
        $val = $prop.Value
        if ($null -eq $val) { continue }
        if ($val -is [string]) { continue }
        if ($val -is [System.Collections.IEnumerable] -or $val -is [pscustomobject]) {
            Invoke-FullMarkdownWalk -Node $val
        }
    }
}

Invoke-FullMarkdownWalk -Node $entry

if ($script:unsubstituted.Count -gt 0) {
    $missing = ($script:unsubstituted | Select-Object -Unique) -join ', '
    Write-Warning ("inject-markdown-placeholders: {0} placeholder(s) had no matching id: {1}" -f $script:unsubstituted.Count, $missing)
}
Write-Information ("inject-markdown-placeholders: substituted {0} placeholder(s)." -f $script:substituted)

$entry | ConvertTo-Json -Depth 100 -Compress
