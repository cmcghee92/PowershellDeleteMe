Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DotNetFrameworkRelease {
	$path = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
	if (-not (Test-Path $path)) {
		return $null
	}

	return Get-ItemPropertyValue -LiteralPath $path -Name Release -ErrorAction SilentlyContinue
}

function Get-DotNetFrameworkVersion {
	param(
		[int]$Release
	)

	switch ($Release) {
		{ $_ -ge 533320 } { return '4.8.1 or later' }
		{ $_ -ge 528040 } { return '4.8' }
		{ $_ -ge 461808 } { return '4.7.2' }
		{ $_ -ge 461308 } { return '4.7.1' }
		{ $_ -ge 460798 } { return '4.7' }
		{ $_ -ge 394802 } { return '4.6.2' }
		{ $_ -ge 394254 } { return '4.6.1' }
		{ $_ -ge 393295 } { return '4.6' }
		{ $_ -ge 379893 } { return '4.5.2' }
		{ $_ -ge 378675 } { return '4.5.1' }
		{ $_ -ge 378389 } { return '4.5' }
		default { return $null }
	}
}

function Install-DotNetFramework481 {
	$downloadUrl = 'https://go.microsoft.com/fwlink/?LinkId=2203304'
	$tempDir = Join-Path $env:TEMP 'powershelldelete-me-setup'
	New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

	$installerPath = Join-Path $tempDir 'ndp481-web.exe'
	Write-Host 'Downloading .NET Framework 4.8.1 web installer.'
	Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath

	Write-Host 'Installing .NET Framework 4.8.1.'
	$process = Start-Process -FilePath $installerPath -ArgumentList @('/q', '/norestart') -Wait -NoNewWindow -PassThru
	if ($process.ExitCode -ne 0) {
		throw "The .NET Framework 4.8.1 installer failed with exit code $($process.ExitCode)."
	}
}

function Install-AppInstallerFromMicrosoft {
	$downloadUrl = 'https://aka.ms/getwinget'
	$tempDir = Join-Path $env:TEMP 'powershelldelete-me-setup'
	New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

	$installerPath = Join-Path $tempDir 'Microsoft.AppInstaller.msixbundle'
	Write-Host 'Downloading Microsoft App Installer.'
	Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath

	Write-Host 'Installing Microsoft App Installer.'
	try {
		Add-AppxPackage -Path $installerPath -ErrorAction Stop
		return
	} catch {
		$msg = ($_ | Out-String).Trim()
		Write-Warning "Initial Microsoft App Installer install failed: ${msg}"
	}

	$extractDir = Join-Path $tempDir 'appinstaller_contents'
	if (Test-Path $extractDir) {
		Remove-Item -Recurse -Force $extractDir
	}
	New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

	try {
		Expand-Archive -LiteralPath $installerPath -DestinationPath $extractDir -Force -ErrorAction Stop
	} catch {
		Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
		[System.IO.Compression.ZipFile]::ExtractToDirectory($installerPath, $extractDir)
	}

	$dependencyPackages = Get-ChildItem -Path $extractDir -Recurse -File -Include '*.msix','*.appx' |
		Where-Object { $_.Name -match 'VCLibs|WindowsAppRuntime' } |
		Select-Object -ExpandProperty FullName

	foreach ($dependencyPackage in $dependencyPackages) {
		Write-Host "Installing dependency package $dependencyPackage"
		Add-AppxPackage -Path $dependencyPackage -ErrorAction Stop
	}

	Write-Host 'Retrying Microsoft App Installer installation.'
	Add-AppxPackage -Path $installerPath -ErrorAction Stop
}

function Install-DotNetSdk10 {
	if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
		throw 'winget was not found after installing Microsoft App Installer.'
	}

	Write-Host 'Installing .NET 10 SDK.'
	$rawOutput = & winget install --id Microsoft.DotNet.SDK.10 --exact --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
	$rc = $LASTEXITCODE

	if ($rc -eq 0 -or $rawOutput -match 'already installed' -or $rawOutput -match 'Already installed' -or $rawOutput -match 'No available upgrade' -or $rawOutput -match 'No newer package versions are available' -or $rawOutput -match 'Found an existing package') {
		Write-Host '.NET 10 SDK is installed or up to date.'
		return
	}

	throw ".NET 10 SDK installation failed. Output:`n$rawOutput"
}

$release = Get-DotNetFrameworkRelease
$version = if ($release) { Get-DotNetFrameworkVersion -Release $release } else { $null }

if ($version -eq '4.8.1 or later') {
	Write-Host ".NET Framework $version is already installed."
} else {
	if ($version) {
		Write-Host ".NET Framework $version is installed; upgrading to 4.8.1."
	} else {
		Write-Host '.NET Framework 4.5 or later was not detected; installing 4.8.1.'
	}

	Install-DotNetFramework481
	$release = Get-DotNetFrameworkRelease
	$version = if ($release) { Get-DotNetFrameworkVersion -Release $release } else { $null }
	Write-Host ".NET Framework check complete: $version"
}

Install-AppInstallerFromMicrosoft

Install-DotNetSdk10

Write-Host 'Setup complete.'