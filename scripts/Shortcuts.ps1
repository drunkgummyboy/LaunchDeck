Write-Host "--- MoveTorrents Configuration ---" -ForegroundColor:Cyan;
Add-Type -AssemblyName System.Windows.Forms;

$browser = New-Object System.Windows.Forms.FolderBrowserDialog;

Write-Host "Waiting for SOURCE directory selection..." -ForegroundColor:Yellow;
$browser.Description = "Select the SOURCE directory (where .torrent files are downloaded)";
$browser.SelectedPath = "$env:USERPROFILE\Downloads";
$resultSrc =$browser.ShowDialog();
if ($resultSrc -eq [System.Windows.Forms.DialogResult]::OK) { $srcDir =$browser.SelectedPath } else { $srcDir = "$env:USERPROFILE\Downloads" };

Write-Host "Waiting for DESTINATION directory selection..." -ForegroundColor:Yellow;
$browser.Description = "Select the DESTINATION directory (where .torrent files should move)";
$browser.SelectedPath = "\\SYNNAS-BEAU\Multimedia";
$resultDest =$browser.ShowDialog();
if ($resultDest -eq [System.Windows.Forms.DialogResult]::OK) {$destDir = $browser.SelectedPath } else {$destDir = "\\SYNNAS-BEAU\Multimedia" };

Write-Host "`nUsing Source: $srcDir" -ForegroundColor:Cyan;
Write-Host "Using Destination: $destDir" -ForegroundColor:Cyan;

$urlMove = "https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/assets/MoveTorrentFiles.ico";
$urlDL = "https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/assets/Downloads.ico";
$urlAGIcon = "https://raw.githubusercontent.com/drunkgummyboy/AirGrabber/main/airgrabber.ico";
$urlAGPy = "https://raw.githubusercontent.com/drunkgummyboy/AirGrabber/main/airgrabber.py";
$urlCTT = "https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/assets/CTTtools.ico";

$dir = "$env:USERPROFILE\LaunchDeck_Assets";
$dt = [Environment]::GetFolderPath('Desktop');
$bat = "$dir\MoveTorrents.bat";

if (-not (Test-Path -Path:$dir)) { [void](New-Item -ItemType:Directory -Force -Path:$dir) };

Write-Host "`nDownloading latest assets to safe location ($dir)..." -ForegroundColor:Cyan;
Invoke-WebRequest -Uri:$urlMove -OutFile:"$dir\MoveTorrentFiles.ico";
Invoke-WebRequest -Uri:$urlDL -OutFile:"$dir\Downloads.ico";
Invoke-WebRequest -Uri:$urlAGIcon -OutFile:"$dir\airgrabber.ico";
Invoke-WebRequest -Uri:$urlAGPy -OutFile:"$dir\airgrabber.py";
Invoke-WebRequest -Uri:$urlCTT -OutFile:"$dir\CTTtools.ico";

Write-Host "Creating batch script with your chosen locations..." -ForegroundColor:Cyan;

$batchPart1 = @"
@ECHO OFF
SETLOCAL
SET "SRC=$srcDir"
SET "DEST=$destDir"
SET "FILETYPE=*.torrent"

REM Count the number of files to be moved
SET "MOVED_COUNT=0"
FOR /F %%A IN ('DIR /B /A-D "%SRC%\%FILETYPE%" 2^>NUL ^| FIND /C /V ""') DO SET "MOVED_COUNT=%%A"

REM Run robocopy silently
robocopy "%SRC%" "%DEST%" %FILETYPE% /MOV /NFL /NDL /NJH /NJS /NP /R:1 /W:1 >NUL 2>&1
"@;

$batchPart2 = @'
ECHO                                                                                                                        
ECHO 88888888888  88  88                                                                                                88  
ECHO 88           ""  88                                                                                                88  
ECHO 88               88                                                                                                88  
ECHO 88aaaaa      88  88   ,adPPYba,  ,adPPYba,      88,dPYba,,adPYba,    ,adPPYba,   8b       d8   ,adPPYba,   ,adPPYb,88  
ECHO 88"""""      88  88  a8P_____88  I8[    ""      88P'   "88"    "8a  a8"     "8a  `8b     d8'  a8P_____88  a8"    `Y88  
ECHO 88           88  88  8PP"""""""   `"Y8ba,       88      88      88  8b       d8   `8b   d8'   8PP"""""""  8b       88  
ECHO 88           88  88  "8b,   ,aa  aa    ]8I      88      88      88  "8a,   ,a8"    `8b,d8'    "8b,   ,aa  "8a,   ,d88  
ECHO 88           88  88   `"Ybbd8"'  `"YbbdP"'      88      88      88   `"YbbdP"'       "8"       `"Ybbd8"'   `"8bbdP"Y8  
ECHO.
ECHO   Moved %MOVED_COUNT% .torrent file(s).
ECHO.
timeout /t 2 >nul
ENDLOCAL
'@;

$batchContent =$batchPart1 + "`r`n" + $batchPart2;
[System.IO.File]::WriteAllText($bat,$batchContent);

Write-Host "Creating shortcuts on the Desktop..." -ForegroundColor:Cyan;
$WS = New-Object -ComObject WScript.Shell;

$s1 = $WS.CreateShortcut("$dt\Downloads.lnk");
$s1.TargetPath = "explorer.exe";
$s1.Arguments = "shell:Downloads";
$s1.IconLocation = "$dir\Downloads.ico, 0";
$s1.Description = "Open Downloads Folder";
$s1.Save();

$s2 = $WS.CreateShortcut("$dt\Move Torrents.lnk");
$s2.TargetPath = "cmd.exe";
$s2.Arguments = "/c `"$bat`"";
$s2.IconLocation = "$dir\MoveTorrentFiles.ico, 0";
$s2.Description = "Move .torrent files";
$s2.Save();

$s3 = $WS.CreateShortcut("$dt\AirGrabber.lnk");
$s3.TargetPath = "pythonw.exe";
$s3.Arguments = "`"$dir\airgrabber.py`"";
$s3.IconLocation = "$dir\airgrabber.ico, 0";
$s3.Description = "Launch AirGrabber safely";
$s3.Save();

$s4 = $WS.CreateShortcut("$dt\CTT WinUtill.lnk");
$s4.TargetPath = "powershell.exe";
$s4.Arguments = "-NoProfile -Command `"iex (irm 'https://christitus.com/win')`"";
$s4.IconLocation = "$dir\CTTtools.ico, 0";
$s4.Description = "Launch Chris Titus Windows Utility";
$s4.Save();

Write-Host "Done! You can now right-click any of these desktop shortcuts and select 'Pin to taskbar'." -ForegroundColor:Green;
