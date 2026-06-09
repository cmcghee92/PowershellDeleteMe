# Set execution policy for the current process to allow running the module
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

# Ensure the NuGet Package Provider is installed
if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "Installing NuGet provider..." -ForegroundColor Cyan
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}

# Trust PSGallery to avoid interactive confirmation prompts
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

# Install and import the PSWindowsUpdate module if not already present
if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Host "Installing PSWindowsUpdate module..." -ForegroundColor Cyan
    Install-Module -Name PSWindowsUpdate -Force | Out-Null
}
Import-Module -Name PSWindowsUpdate -Force

# Find and install all updates EXCEPT Feature Updates (FeaturePacks)
Write-Host "Scanning and installing updates (excluding Feature Updates)..." -ForegroundColor Green

Get-WindowsUpdate -NotCategory "FeaturePacks" -AcceptAll -Install -AutoReboot
