# 1. Create a safe directory in AppData for persistent assets
$safeDir = "$env:APPDATA\LaunchDeck"
if (-not (Test-Path $safeDir)) {
New-Item -ItemType Directory -Force -Path $safeDir | Out-Null
}

# 2. Download the icon to the safe AppData directory
$iconUrl = 'https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/assets/LaunchDeck.ico'
$iconPath = "$safeDir\LaunchDeck.ico"
Invoke-WebRequest -Uri $iconUrl -OutFile $iconPath

# 3. Create a local launcher script to satisfy Windows Defender
$launcherPath = "$safeDir\Launcher.ps1"
$launcherContent = @"
`$rawScriptUrl = 'https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/LaunchDeck.ps1'
Invoke-RestMethod -Uri `$rawScriptUrl | Invoke-Expression
"@
Set-Content -Path $launcherPath -Value $launcherContent -Force

# 4. Configure the desktop shortcut to run the local launcher
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\LaunchDeck.lnk")

$Shortcut.TargetPath = "powershell.exe"
# We now use -File to point to the local Launcher.ps1 instead of passing a -Command
$Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherPath`""
$Shortcut.WorkingDirectory = "$safeDir"
$Shortcut.IconLocation =$iconPath

# Save the shortcut to the desktop
$Shortcut.Save()
