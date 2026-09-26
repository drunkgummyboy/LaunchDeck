# Elevation Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
exit
}

Write-Host "Creating Chris Titus Tool environment..."

# --- PowerShell Logic Starts Here ---
$TargetDir = Join-Path $env:ProgramData 'ChrisTitusTool'
$BatFile   = Join-Path $TargetDir 'ChrisTitusToolLauncher.bat'
$VbsFile   = Join-Path $TargetDir 'ChrisTitusToolLauncher.vbs'
$IconFile  = Join-Path $TargetDir 'CTTtools.ico'
$S_Name    = 'Chris Titus Tool.lnk'
$S_Path    = Join-Path ([Environment]::GetFolderPath("Desktop")) $S_Name

# 1) Create target folder 
if (!(Test-Path $TargetDir)) { 
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null 
}

# 2) Download the custom icon
Write-Host "Downloading custom icon..."
try {
# Force TLS 1.2 to prevent download errors
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$IconUrl = "https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/assets/CTTtools.ico"
Invoke-WebRequest -Uri $IconUrl -OutFile $IconFile -UseBasicParsing
} catch {
Write-Host "ICON DOWNLOAD ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# 3) Write the batch file 
$batContent = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://christitus.com/win'))"
"@ 
Set-Content -Path $BatFile -Value $batContent -Encoding ASCII 

# 4) Write the VBS (elevates via UAC) 
$vbsContent = @"
Set UAC = CreateObject("Shell.Application")
UAC.ShellExecute "$BatFile", "", "", "runas", 1
"@ 
Set-Content -Path $VbsFile -Value $vbsContent -Encoding ASCII 

# 5) Create the desktop shortcut using the downloaded icon
$WshShell = New-Object -ComObject WScript.Shell;
$Shortcut = $WshShell.CreateShortcut($S_Path);
$Shortcut.TargetPath   = $VbsFile;
if (Test-Path $IconFile) {
$Shortcut.IconLocation = $IconFile;
} else {
$Shortcut.IconLocation = "powershell.exe,0";
}
$Shortcut.Save();

Write-Host "------------------------------------------------" 
Write-Host "Shortcut created on your desktop: $S_Name" 
Write-Host "It will run with administrator rights." 

# 6) Open the newly created shortcut
Write-Host "Opening the shortcut..."
Start-Sleep -Seconds 1

try {
Invoke-Item -Path $S_Path
} catch {
Write-Host "SHORTCUT ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nProcess Complete. The window will now stay open."
Read-Host "Press Enter to exit..."