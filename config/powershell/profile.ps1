Set-Alias moaid nvim
Set-Alias lg lazygit
Set-Alias .. cd..

function Test-Config-Path
{
	$repoPath = "$env:Moaid_Config_Path/config/glazewm/glazewm_config.yaml"
	Write-Host "$repoPath"
}

function Start-Glaze
{
	$repoPath = "$env:Moaid_Config_Path/config/glazewm/glazewm_config.yaml"
	glazewm --config="$repoPath"
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

# Invoke-Expression (&starship init powershell)
