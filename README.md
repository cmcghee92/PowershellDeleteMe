# PowershellDeleteMe
This is my first repository
NotherLine

## VS Code Setup Script

Run [VsCodesetup.ps1](VsCodesetup.ps1) from an elevated PowerShell session on Windows.

The script uses winget to install the latest .NET SDK, PowerShell 7, Git for Windows, and Visual Studio Code, creates `C:\Github Repositories`, and then prompts for your Git `user.name` and `user.email` before setting `init.defaultBranch` to `main` and `core.editor` to Visual Studio Code.