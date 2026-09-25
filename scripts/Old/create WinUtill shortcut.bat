<# :
@echo off
setlocal
title Chris Titus Tool Shortcut Creator

:: Check for admin rights 
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo Creating Chris Titus Tool environment...

:: Run this file as a PowerShell script
powershell -NoProfile -ExecutionPolicy Bypass -Command "IEX ([System.IO.File]::ReadAllText('%~f0'))"

echo.
echo Process Complete.
pause
exit /b
#>

# --- PowerShell Logic Starts Here ---
$TargetDir = Join-Path $env:ProgramData 'ChrisTitusTool'
$BatFile   = Join-Path $TargetDir 'ChrisTitusToolLauncher.bat'
$VbsFile   = Join-Path $TargetDir 'ChrisTitusToolLauncher.vbs'
$S_Name    = 'Chris Titus Tool.lnk'
$S_Path    = Join-Path ([Environment]::GetFolderPath("Desktop")) $S_Name

# 1) Create target folder 
if (!(Test-Path $TargetDir)) { 
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null 
}

# 2) Write the batch file
$batContent = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://christitus.com/win'))"
"@
Set-Content -Path $BatFile -Value $batContent -Encoding ASCII

# 3) Write the VBS (elevates via UAC)
$vbsContent = @"
Set UAC = CreateObject("Shell.Application")
UAC.ShellExecute "$BatFile", "", "", "runas", 1
"@
Set-Content -Path $VbsFile -Value $vbsContent -Encoding ASCII

# 4) Create the desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($S_Path)
$Shortcut.TargetPath   = $VbsFile
$Shortcut.IconLocation = "powershell.exe,0"
$Shortcut.Save()

Write-Host "------------------------------------------------"
Write-Host "Shortcut created on your desktop: $S_Name"
Write-Host "It will run with administrator rights."