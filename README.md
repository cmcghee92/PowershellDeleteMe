# PowershellDeleteMe
This script is used to setup VS Code

## VS Code Setup Script

Run [VsCodesetup.ps1](VsCodesetup.ps1) from an elevated PowerShell session on Windows.

The script refreshes the Microsoft Store when `wsreset.exe` is available, updates Microsoft App Installer when winget is present, installs Microsoft App Installer if winget is missing, then uses winget to install the latest .NET SDK, PowerShell 7, Git for Windows, and Visual Studio Code. It also creates `C:\Github Repositories` and prompts for your Git `user.name` and `user.email` before setting `init.defaultBranch` to `main` and `core.editor` to Visual Studio Code.