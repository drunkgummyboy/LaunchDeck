# 1. Download the main LaunchDeck script to your personal desktop
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/refs/heads/main/LaunchDeck.ps1' -OutFile "$env:USERPROFILE\Desktop\LaunchDeck.ps1"

# 2. Download the icon using the raw GitHub URL
$iconUrl = 'https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/assets/LaunchDeck.ico'
$iconPath = "$env:USERPROFILE\Desktop\LaunchDeck.ico"
Invoke-WebRequest -Uri $iconUrl -OutFile $iconPath

# 3. Create the desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\LaunchDeck.lnk")

# Point the shortcut to PowerShell and pass the script as an argument
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$env:USERPROFILE\Desktop\LaunchDeck.ps1`""
$Shortcut.WorkingDirectory = "$env:USERPROFILE\Desktop"
$Shortcut.IconLocation =$iconPath

# Save the shortcut to the desktop
$Shortcut.Save()