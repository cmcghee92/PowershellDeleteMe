Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Require administrator privileges — most operations below need elevation.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator.'
}

$script:TempDir = Join-Path $env:TEMP 'vscode-setup'

# 1. Check if the Windows App Runtime 1.8 framework is already installed
$FrameworkName = "Microsoft.WindowsAppRuntime.1.8"
$MinRuntimeVersion = [version]"8000.616.304.0"
$IsInstalled = Get-AppxPackage -AllUsers -Name $FrameworkName -ErrorAction SilentlyContinue |
    Where-Object { [version]$_.Version -ge $MinRuntimeVersion }

if (-not $IsInstalled) {
    Write-Host "[INFO] Missing required framework: $FrameworkName. Installing now..." -ForegroundColor Yellow

    # Define download details for Windows App SDK 1.8
    $RuntimeUrl = "https://aka.ms/windowsappsdk/1.8/1.8.260508005/windowsappruntimeinstall-x64.exe"
    $OutputPath = "$env:TEMP\WindowsAppRuntimeInstall-x64.exe"

    # Download the web installer bootstrapper
    Write-Host "[INFO] Downloading runtime installer from Microsoft..."
    Invoke-WebRequest -Uri $RuntimeUrl -OutFile $OutputPath -UseBasicParsing

    # Silently execute the installation system-wide
    Write-Host "[INFO] Running silent installation..."
    $InstallProcess = Start-Process -FilePath $OutputPath -ArgumentList "--quiet", "--force" -Wait -PassThru

    if ($InstallProcess.ExitCode -eq 0) {
        Write-Host "[SUCCESS] Windows App Runtime 1.8 installed successfully." -ForegroundColor Green
    } else {
        Write-Warning "[ERROR] Runtime installer exited with code $($InstallProcess.ExitCode). Script might fail."
    }

    # Cleanup installer file
    Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "[INFO] $FrameworkName is already present. Proceeding..." -ForegroundColor Green
}

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
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

    $installerPath = Join-Path $script:TempDir 'ndp481-web.exe'
    Write-Host 'Downloading .NET Framework 4.8.1 web installer.'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

    Write-Host 'Installing .NET Framework 4.8.1.'
    $process = Start-Process -FilePath $installerPath -ArgumentList @('/q', '/norestart') -Wait -NoNewWindow -PassThru

    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    if ($process.ExitCode -eq 3010) {
        Write-Warning '.NET Framework 4.8.1 installed successfully, but a reboot is required.'
        return
    }

    if ($process.ExitCode -ne 0) {
        throw "The .NET Framework 4.8.1 installer failed with exit code $($process.ExitCode)."
    }
}

function Install-AppInstallerFromMicrosoft {
    $downloadUrl = 'https://aka.ms/getwinget'
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

    $installerPath = Join-Path $script:TempDir 'Microsoft.AppInstaller.msixbundle'
    Write-Host 'Downloading Microsoft App Installer.'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

    Write-Host 'Installing Microsoft App Installer.'
    try {
        Add-AppxPackage -Path $installerPath -ForceUpdateFromAnyVersion -ErrorAction Stop
        return
    } catch {
        $msg = ($_ | Out-String).Trim()
        Write-Warning "Initial Microsoft App Installer install failed: ${msg}"
    }

    $extractDir = Join-Path $script:TempDir 'appinstaller_contents'
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

    $dependencyPackages = Get-ChildItem -Path $extractDir -Recurse -File -Include '*.msix', '*.appx' |
        Where-Object { $_.Name -match 'VCLibs|WindowsAppRuntime|UI.Xaml' } |
        Select-Object -ExpandProperty FullName

    foreach ($dependencyPackage in $dependencyPackages) {
        Write-Host "Installing dependency package: $dependencyPackage"
        Add-AppxPackage -Path $dependencyPackage -ForceUpdateFromAnyVersion -ErrorAction Stop
    }

    Write-Host 'Retrying Microsoft App Installer installation after installing dependencies.'
    Add-AppxPackage -Path $installerPath -ForceUpdateFromAnyVersion -ErrorAction Stop
}

function Install-CppDesktopBridgeRuntime {
    param(
        [string]$MinimumVersion = '14.0.33519.0'
    )

    $installedRuntime = Get-AppxPackage -AllUsers -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($installedRuntime) {
        if ([version]$installedRuntime.Version -ge [version]$MinimumVersion) {
            Write-Host "Microsoft.VCLibs.140.00.UWPDesktop is already installed with sufficient version: $($installedRuntime.Version)"
            return
        }

		Write-Host "Microsoft.VCLibs.140.00.UWPDesktop $($installedRuntime.Version) is older than required $MinimumVersion. Reinstalling."
		try {
			Remove-AppxPackage -Package $installedRuntime.PackageFullName -ErrorAction Stop
			# Wait for the package to be fully removed
			Write-Host 'Waiting for package removal to complete...'
			Start-Sleep -Seconds 5
			
			# Verify removal
			$stillInstalled = Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -ErrorAction SilentlyContinue
			if ($stillInstalled) {
				Write-Warning "Package removal verification failed. Attempting forced removal..."
				Remove-AppxPackage -Package $installedRuntime.PackageFullName -AllUsers -ErrorAction Stop
				Start-Sleep -Seconds 5
			}
		} catch {
			$msg = ($_ | Out-String).Trim()
			Write-Warning "Removing older Microsoft.VCLibs.140.00.UWPDesktop failed: ${msg}"
		}
	}

    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

    $runtimeUrl = if ([Environment]::Is64BitOperatingSystem) {
        'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'
    } else {
        'https://aka.ms/Microsoft.VCLibs.x86.14.00.Desktop.appx'
    }

    $runtimePath = Join-Path $script:TempDir 'Microsoft.VCLibs.140.00.UWPDesktop.appx'
    Write-Host 'Downloading Microsoft C++ Runtime framework for Desktop Bridge.'
    Invoke-WebRequest -Uri $runtimeUrl -OutFile $runtimePath -UseBasicParsing

    Write-Host 'Installing Microsoft C++ Runtime framework for Desktop Bridge.'
    Add-AppxPackage -Path $runtimePath -ErrorAction Stop

    # Verify installation
    $verifyRuntime = Get-AppxPackage -AllUsers -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($verifyRuntime) {
        Write-Host "VCLibs installation verified: $($verifyRuntime.Version)"
    }
}

function Install-UIXaml28 {
    $minVersion = [version]'2.8.0.0'
    $installed = Get-AppxPackage -AllUsers -Name 'Microsoft.UI.Xaml.2.8' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($installed -and [version]$installed.Version -ge $minVersion) {
        Write-Host "Microsoft.UI.Xaml.2.8 is already installed: $($installed.Version)"
        return
    }

    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

    # Microsoft.UI.Xaml 2.8.6 NuGet package is zip-compatible and contains the appx for each arch.
    $nugetUrl = 'https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6'
    $nugetPath = Join-Path $script:TempDir 'Microsoft.UI.Xaml.2.8.nupkg'
    Write-Host 'Downloading Microsoft.UI.Xaml 2.8 package.'
    Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetPath -UseBasicParsing

    $extractDir = Join-Path $script:TempDir 'uixaml28'
    if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
    Expand-Archive -LiteralPath $nugetPath -DestinationPath $extractDir -Force

    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $appxPath = Join-Path $extractDir "tools\AppX\$arch\Release\Microsoft.UI.Xaml.2.8.appx"
    if (-not (Test-Path $appxPath)) {
        throw "Could not locate Microsoft.UI.Xaml.2.8.appx in extracted package at: $appxPath"
    }

    Write-Host 'Installing Microsoft.UI.Xaml 2.8.'
    Add-AppxPackage -Path $appxPath -ForceUpdateFromAnyVersion -ErrorAction Stop

    $verify = Get-AppxPackage -AllUsers -Name 'Microsoft.UI.Xaml.2.8' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($verify) {
        Write-Host "Microsoft.UI.Xaml.2.8 installation verified: $($verify.Version)"
    } else {
        throw 'Microsoft.UI.Xaml.2.8 installation could not be verified.'
    }
}

function Install-DotNetSdk10 {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget was not found after installing Microsoft App Installer.'
    }

    Write-Host 'Installing .NET 10 SDK.'
    $rawOutput = & winget install --id Microsoft.DotNet.SDK.10 --exact --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
    $rc = $LASTEXITCODE

	if ($rc -eq 0 -or $rawOutput -match 'already installed' -or $rawOutput -match 'Already installed' -or $rawOutput -match 'No available upgrade' -or $rawOutput -match 'No newer package versions availab[...]') {
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

Install-CppDesktopBridgeRuntime
Install-UIXaml28
Install-AppInstallerFromMicrosoft

Install-DotNetSdk10

Write-Host 'Setup complete.'
