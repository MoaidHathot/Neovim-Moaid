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
	$zebarConfigPath="$env:Moaid_Config_Path/config/zebar"
	zebar startup --config-dir="$zebarConfigPath"
}

function Stop-Zebar
{
	Get-Process | Where-Object { $_.ProcessName -eq "zebar" } | Foreach-Object { Stop-Process -id $_.id -Force }
}

function Restart-Zebar($overrideConfigs = $true)
{
	Stop-Zebar
	Start-Zebar
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

	Set-PSReadLineOption -Colors @{ "Selection" = "`e[7m" }
	Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete
	carapace _carapace | Out-String | Invoke-Expression
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

function Get-ProjectDll {

	$path = Get-Location

	$projectName = Split-Path -Leaf $Path
	$binPath = Join-Path -Path $Path -ChildPath "bin"

	if (-not (Test-Path -Path $binPath -PathType Container)) {
		return
	}

	$debugPath = Join-Path -Path $binPath -ChildPath "Debug"
	$releasePath = Join-Path -Path $binPath -ChildPath "Release"

	if (Test-Path -Path $debugPath -PathType Container) {
		return Get-ChildItem -Path $debugPath -Recurse -Include "$projectName.dll"
	}

	if (Test-Path -Path $releasePath -PathType Container) {
		return Get-ChildItem -Path $releasePath -Recurse -Include "$projectName.dll"
	}
}

set-alias ilspyprev "C:\Users\moaid\Downloads\ILSpy_binaries_9.0.0.7833-preview3-x64\ILSpy.exe"

function Decompile {
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string]$Path,
		[string]$langVer = $null
    )

	if (-not $path -or -not (Test-Path -Path $Path)) {
		$path = Get-ProjectDll
		Write-Host "Extracted path: $path" -ForegroundColor Green
	}

	Write-Host "Language version: $langVer" -ForegroundColor Green

	if ((Test-Path -Path $path) -and (Test-Path -Path $Path -PathType Leaf) -and ($Path -match '\.(dll|exe)$')) {
		if($null -eq $langVer -or $langVer -lt 1) {
			IlSpycmd $Path | Bat --language C#
			return
		}

		Write-Host "Decompiling $Path with language version $langVer" -ForegroundColor Green
		(IlSpycmd $Path -lv $langVer) | Bat --language C#
		return
	}
}

function Show-ILSpy {
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string]$Path
    )

	if (-not (Test-Path -Path $Path)) {
		$path = Get-ProjectDll
	}

	# ILSpy (Get-ProjectDll)
	& ILSpyPrev (Get-ProjectDll)
}

function Demo {
	param (
        [Parameter(ValueFromPipeline = $true)]
        [string]$filePath,
		[Parameter(ValueFromRemainingArguments=$true)]
		[string[]]$Extras
	)

	$project = (Join-Path (Get-Location) "Host.csproj")
	dotnet-exec $filePath --project $project -- $Extras
}

function Remove-Shada
{
	$localData  = Get-LocalAppData
	$shadaPath = "$localData/nvim-data/shada/"
	Remove-Item $shadaPath -Recurse
}

function Remove-NvimData
{
	$localData  = Get-LocalAppData
	$nvimDataPath = "$localData/nvim-data/"
	Remove-Item $nvimDataPath -Recurse
}

function moaid2 {
    $env:XDG_CONFIG_HOME = "P:\Github\Neovim-Moaid\configurations/../config2/"
    nvim @args
    $env:XDG_CONFIG_HOME = "P:\Github\Neovim-Moaid\configurations/../config/"
}

# Invoke-Expression (&starship init powershell)

