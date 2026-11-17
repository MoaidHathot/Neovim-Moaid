<#
.SYNOPSIS
Builds the dotfiles-owned file-based app into OverShell's machine-local state directory.
Run once on a new machine and after editing/pulling TajAgents.cs. Disable taj.agents
while rebuilding if it is already running, then enable it again in settings.jsonc.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$state = if ($env:OVERSHELL_STATE_DIR) {
    [IO.Path]::GetFullPath($env:OVERSHELL_STATE_DIR)
} elseif ($env:XDG_STATE_HOME -and [IO.Path]::IsPathRooted($env:XDG_STATE_HOME)) {
    Join-Path ([IO.Path]::GetFullPath($env:XDG_STATE_HOME)) 'overshell'
} else {
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OverShell'
}
$destination = Join-Path $state 'extensions/taj-agents'
$artifacts = Join-Path $state 'extensions/build/taj-agents'

# File-based apps publish as Native AOT by default. The SDK/compiler only runs here;
# the resident extension is a small standalone executable, with no SDK runner.
& dotnet publish (Join-Path $PSScriptRoot 'TajAgents.cs') -c Release -r win-x64 `
    --output $destination --artifacts-path $artifacts --disable-build-servers
if ($LASTEXITCODE -ne 0) { throw "TajAgents publish failed (exit $LASTEXITCODE)" }
Write-Output "Built $(Join-Path $destination 'TajAgents.exe')"
