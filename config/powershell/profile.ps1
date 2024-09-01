Set-Alias moaid nvim
Set-Alias lg lazygit
# Set-Alias .. cd..

function ..
{
	[CmdletBinding()]
	param
	( 
		[int]$times = 1
	)

	for ($i = 0; $i -lt $times; $i++)
	{
		Set-Location ..
	}
}

function Get-LocalAppData
{
	return ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData))
}

function Start-Glaze
{
	$glazeConfigPath = "$env:Moaid_Config_Path/config/glazewm/glazewm_config.yaml"
	write-host $glazeConfigPath
	glazewm start --config="$glazeConfigPath"
}

function Start-Zebar
{
	$monitors = zebar monitors
	foreach ($monitor in $monitors) {
	 Start-Process -WindowStyle Hidden -FilePath "zebar" -ArgumentList "open bar --args $monitor"
	};
}

function Stop-Zebar
{
	Get-Process | Where-Object { $_.ProcessName -eq "zebar" } | Foreach-Object { Stop-Process -id $_.id -Force }
}

function Restart-Zebar($overrideConfigs = $true)
{
	if ($overrideConfigs)
	{
		Update-Zebar-Config
	}

	Stop-Zebar
	Start-Zebar
}

function Update-Zebar-Config
{
	$zebarConfigPath = "$env:Moaid_Config_Path/config/glazewm/zebar_config.yaml"
	$zebarDefaultConfigPath = "$env:USERPROFILE/.glzr/zebar/config.yaml"

	Copy-Item -Path $zebarConfigPath -Destination $zebarDefaultConfigPath -Force
}

function Update-Path
{
	$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") 
}

if ($host.Name -eq 'ConsoleHost')
{
    Import-Module PSReadLine

	Set-PSReadLineOption -EditMode Windows
	Set-PSReadLineOption -PredictionViewStyle ListView
	Set-PSReadLineOption -PredictionSource HistoryAndPlugin
}

function Show-Jwt($jwt)
{
	$jwt | jq -R 'split(".") | .[0],.[1] | @base64d | fromjson'
}

function fzfc
{
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline)]
		$text
	)

	if ($text)
	{
		$text | fzf --preview 'bat --style=numbers --color=always {}' --preview-window '~3'
		return
	}

	fzf --preview 'bat --style=numbers --color=always {}' --preview-window '~3'
}

function Open-FileSearch
{
	$selectedFile = fzfc
	moaid $selectedFile
} 

function New-Notification($title, $descritpion)
{
	New-BurntToastNotification -Text $title, $descritpion
}

function Copy-Location
{
	Get-Location | Set-Clipboard
}

function Show-IL
{
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline)]
		$path
	)

	if ($path)
	{
		IlSpycmd $path | Bat --language C#
		return
	}
}

function Remove-Shada
{
	$localData  = Get-LocalAppData
	$shadaPath = "$localData/nvim-data/shada/"
	Remove-Item $shadaPath -Recurse
}

# Invoke-Expression (&starship init powershell)

