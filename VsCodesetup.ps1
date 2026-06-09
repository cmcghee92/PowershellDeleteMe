Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Refresh-MicrosoftStore {
	$wsreset = Get-Command wsreset.exe -ErrorAction SilentlyContinue
	if (-not $wsreset) {
		Write-Warning 'wsreset.exe was not found, so the Microsoft Store cannot be refreshed automatically.'
		return
	}

	Write-Host 'Refreshing Microsoft Store.'
	$proc = Start-Process -FilePath $wsreset.Source -ArgumentList '-i' -Wait -NoNewWindow -PassThru
	if ($proc.ExitCode -ne 0) {
		Write-Warning "Microsoft Store refresh exited with code $($proc.ExitCode)."
	}
}

function Install-AppInstallerFromMicrosoft {
	$tempDir = Join-Path $env:TEMP 'powershelldelete-me-setup'
	New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

	$installerPath = Join-Path $tempDir 'Microsoft.AppInstaller.msixbundle'
	Invoke-InstallerDownload -Url 'https://aka.ms/getwinget' -DestinationPath $installerPath

	Write-Host 'Installing Microsoft App Installer.'
	Add-AppxPackage -Path $installerPath
}

function Ensure-WingetAvailable {
	if (Get-Command winget -ErrorAction SilentlyContinue) {
		return
	}

	Write-Host 'winget was not found. Installing Microsoft App Installer.'
	Install-AppInstallerFromMicrosoft

	if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
		throw 'winget is still not installed or available on PATH after installing Microsoft App Installer.'
	}
}

function Update-AppInstaller {
	if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
		return
	}

	Write-Host 'Updating Microsoft App Installer.'
	$rawOutput = & winget upgrade --id Microsoft.AppInstaller --exact --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
	$rc = $LASTEXITCODE

	if ($rc -eq 0 -or $rawOutput -match 'No available upgrade' -or $rawOutput -match 'No newer package versions are available' -or $rawOutput -match 'already installed' -or $rawOutput -match 'Already installed' -or $rawOutput -match 'Found an existing package') {
		Write-Host 'Microsoft App Installer is installed or up to date.'
		return
	}

	Write-Warning "Microsoft App Installer update did not complete successfully. Output:`n$rawOutput"
}

function Get-LatestGitHubAssetUrl {
	param(
		[Parameter(Mandatory)]
		[string]$Repository,

		[Parameter(Mandatory)]
		[string]$AssetPattern
	)

	$headers = @{ 'User-Agent' = 'PowershellDeleteMe-Setup' }
	$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers $headers
	$asset = $release.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1

	if (-not $asset) {
		throw "Unable to find an asset matching '$AssetPattern' in the latest release for $Repository."
	}

	return $asset.browser_download_url
}

function Invoke-InstallerDownload {
	param(
		[Parameter(Mandatory)]
		[string]$Url,

		[Parameter(Mandatory)]
		[string]$DestinationPath
	)

	Write-Host "Downloading $Url"
	Invoke-WebRequest -Uri $Url -OutFile $DestinationPath
}

function Install-WingetPackage {
	param(
		[Parameter(Mandatory)]
		[string[]]$PackageIds,

		[Parameter(Mandatory)]
		[string]$DisplayName
	)

	foreach ($packageId in $PackageIds) {
		Write-Host "Installing $DisplayName using winget package $packageId."
		$rawOutput = & winget install --id $packageId --exact --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
		$rc = $LASTEXITCODE

		if ($rc -eq 0 -or $rawOutput -match 'already installed' -or $rawOutput -match 'Already installed' -or $rawOutput -match 'No available upgrade' -or $rawOutput -match 'No newer package versions are available' -or $rawOutput -match 'Found an existing package') {
			Write-Host "${DisplayName}: package $packageId installed or up-to-date."
			return
		}

		Write-Warning "$DisplayName package $packageId was not installed successfully. Output:`n$rawOutput`nTrying the next candidate if one exists."
	}

	throw "Unable to install $DisplayName with winget."
}

function Install-DotNetSdk {
	Install-WingetPackage -PackageIds @(
		'Microsoft.DotNet.SDK.10',
		'Microsoft.DotNet.SDK.9',
		'Microsoft.DotNet.SDK.8',
		'Microsoft.DotNet.SDK.7'
	) -DisplayName '.NET SDK'
}

function Install-PowerShell7 {
	Install-WingetPackage -PackageIds @(
		'Microsoft.PowerShell'
	) -DisplayName 'PowerShell 7'
}

function Install-GitForWindows {
	try {
		Install-WingetPackage -PackageIds @(
			'Git.Git'
		) -DisplayName 'Git for Windows'
		return
	} catch {
		Write-Warning "winget Git install failed, falling back to GitHub installer: $_"
	}

	# Fallback: download Git for Windows from GitHub releases and run the EXE installer silently
	$tempDir = Join-Path $env:TEMP 'powershelldelete-me-setup'
	New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

	$downloadUrl = Get-LatestGitHubAssetUrl -Repository 'git-for-windows/git' -AssetPattern '64-bit\.exe$'
	$installerPath = Join-Path $tempDir 'GitForWindows.exe'
	Invoke-InstallerDownload -Url $downloadUrl -DestinationPath $installerPath

	Write-Host 'Installing Git for Windows (fallback installer).'
	$arguments = @(
		'/VERYSILENT',
		'/NORESTART',
		'/SP-'
	)
	$proc = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -NoNewWindow -PassThru
	if ($proc.ExitCode -ne 0) {
		throw "Git installer failed with exit code $($proc.ExitCode)."
	}
}

function Install-VSCode {
	Install-WingetPackage -PackageIds @(
		'Microsoft.VisualStudioCode'
	) -DisplayName 'Visual Studio Code'
}

function Get-GitExecutablePath {
	$candidates = @(
		'C:\Program Files\Git\cmd\git.exe',
		(Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
	)

	foreach ($candidate in $candidates) {
		if (Test-Path $candidate) {
			return $candidate
		}
	}

	$command = Get-Command git -ErrorAction SilentlyContinue
	if ($command) {
		return $command.Source
	}

	throw 'Git was installed, but git.exe could not be found.'
}

function Get-VSCodeCommandPath {
	$candidates = @(
		'C:\Program Files\Microsoft VS Code\bin\code.cmd',
		(Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd')
	)

	foreach ($candidate in $candidates) {
		if (Test-Path $candidate) {
			return $candidate
		}
	}

	throw 'Visual Studio Code was installed, but code.cmd could not be found.'
}

function Set-GitDefaults {
	$gitUserName = Read-Host 'Enter your Git global user.name'
	$gitUserEmail = Read-Host 'Enter your Git global user.email'
	$gitExecutable = Get-GitExecutablePath
	$codeCommand = Get-VSCodeCommandPath

	& $gitExecutable config --global user.name $gitUserName
	& $gitExecutable config --global user.email $gitUserEmail
	& $gitExecutable config --global init.defaultBranch main

	& $gitExecutable config --global core.editor "$codeCommand --wait"
}

function Ensure-RepositoryFolder {
	$repositoryFolder = 'C:\Github Repositories'
	New-Item -ItemType Directory -Path $repositoryFolder -Force | Out-Null
}

Refresh-MicrosoftStore
Ensure-WingetAvailable
Update-AppInstaller

Write-Host 'Preparing GitHub repositories folder.'
Ensure-RepositoryFolder

Write-Host 'Installing .NET SDK.'
Install-DotNetSdk

Write-Host 'Installing PowerShell 7.'
Install-PowerShell7

Write-Host 'Installing Git for Windows.'
Install-GitForWindows

Write-Host 'Installing Visual Studio Code.'
Install-VSCode

Write-Host 'Configuring Git defaults.'
Set-GitDefaults

Write-Host 'Setup complete.'
