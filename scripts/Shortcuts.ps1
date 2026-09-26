$iconUrlMove = "https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/assets/MoveTorrentFiles.ico"
$iconUrlDownloads = "https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/assets/Downloads.ico"

$storageDir = "$env:USERPROFILE\LaunchDeck_Assets"
$iconPathMove = "$storageDir\MoveTorrentFiles.ico"
$iconPathDownloads = "$storageDir\Downloads.ico"
$batchPath = "$storageDir\MoveTorrents.bat"
$desktopPath = [Environment]::GetFolderPath('Desktop')

if (-not (Test-Path -Path:$storageDir)) {
New-Item -ItemType:Directory -Force -Path:$storageDir | Out-Null
}

Write-Host "Downloading icons..." -ForegroundColor:Cyan
Invoke-WebRequest -Uri:$iconUrlMove -OutFile:$iconPathMove
Invoke-WebRequest -Uri:$iconUrlDownloads -OutFile:$iconPathDownloads

Write-Host "Creating batch script..." -ForegroundColor:Cyan
# Changed @" to @' below so PowerShell doesn't eat the backticks!
$batchContent = @'
@ECHO OFF
SETLOCAL

REM Get the current user's Downloads folder path via PowerShell
FOR /F "usebackq tokens=*" %%D IN (`powershell -NoProfile -Command "[Environment]::GetFolderPath('UserProfile') + '\Downloads'"`) DO SET "SRC=%%D"

REM Set the destination folder and file type
SET "DEST=\\SYNNAS-BEAU\Multimedia"
SET "FILETYPE=*.torrent"

REM Run robocopy silently
robocopy "%SRC%" "%DEST%" %FILETYPE% /MOV /NFL /NDL /NJH /NJS /NP /R:1 /W:1 >NUL 2>&1

ENDLOCAL
'@

Set-Content -Path:$batchPath -Value:$batchContent

Write-Host "Creating shortcuts..." -ForegroundColor:Cyan
$WshShell = New-Object -ComObject WScript.Shell

# --- Shortcut 1: Downloads Folder ---
$downloadsShortcutPath = "$desktopPath\Downloads.lnk";
$downloadsShortcut =$WshShell.CreateShortcut($downloadsShortcutPath);$downloadsShortcut.TargetPath = "explorer.exe";
$downloadsShortcut.Arguments = "shell:Downloads";
$downloadsShortcut.IconLocation = "$iconPathDownloads, 0";
$downloadsShortcut.Description = "Open Downloads Folder";
$downloadsShortcut.Save();

# --- Shortcut 2: Move Torrents Batch Script ---
$moveTorrentsShortcutPath = "$desktopPath\Move Torrents.lnk";
$moveTorrentsShortcut =$WshShell.CreateShortcut($moveTorrentsShortcutPath);$moveTorrentsShortcut.TargetPath = "cmd.exe";
$moveTorrentsShortcut.Arguments = "/c `"$batchPath`"";
$moveTorrentsShortcut.IconLocation = "$iconPathMove, 0";
$moveTorrentsShortcut.Description = "Move .torrent files to SYNNAS-BEAU";
$moveTorrentsShortcut.WindowStyle = 7;
$moveTorrentsShortcut.Save();

Write-Host "Done! The batch script is now correctly formatted." -ForegroundColor:Green