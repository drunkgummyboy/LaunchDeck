<# 
 CopyFromUSB-Robo-Visual.ps1
 - Auto-detect USB by volume label (fallback to a fixed drive letter)
 - Multiple robocopy jobs (files or folders)
 - NATIVE Robocopy visual output (shows files and progress on screen)
#>

$ErrorActionPreference = 'Stop'

# ---------- CONFIG ----------
$UsbLabel         = 'USB beau'  # your USB volume label
$FallbackUsbRoot  = 'D:'        # used if label is not found

# Robocopy switches as an ARRAY. 
# REMOVED: /NFL (No File List), /NDL (No Dir List), and /NP (No Progress) so you can see the action!
$RobocopySwitches = @('/E','/COPY:DAT','/R:3','/W:5', '/MT:8')

# Destinations (current user; respects OneDrive redirection if present)
$Roaming   = [Environment]::GetFolderPath('ApplicationData')   # ...\AppData\Roaming
$Documents = [Environment]::GetFolderPath('MyDocuments')
$Desktop   = [Environment]::GetFolderPath('Desktop')

# Jobs: left = path on USB (relative to USB root unless absolute); right = destination
$Jobs = @(
    @{ Source = 'Ventoy\Payload\flashpaste' ; Destination = $Roaming   }
    @{ Source = 'Ventoy\Payload\Shortcuts'  ; Destination = $Documents }
    @{ Source = 'Ventoy\Payload\software'   ; Destination = $Desktop   }
)
# --------------------------------

function Get-UsbRoot {
    $vol = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.FileSystemLabel -eq $UsbLabel }
    if ($vol) { return ($vol.DriveLetter + ':\') }
    return $FallbackUsbRoot + '\'
}

function Ensure-Dir([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

$UsbRoot = Get-UsbRoot
Write-Host "===================================================" -ForegroundColor Magenta
Write-Host " TARGET USB DETECTED: $UsbRoot" -ForegroundColor Magenta
Write-Host "===================================================" -ForegroundColor Magenta
Write-Host ""

$TotalJobs = $Jobs.Count

for ($i = 0; $i -lt $TotalJobs; $i++) {
    $job = $Jobs[$i]
    $srcConfigured = $job.Source
    $dstBase       = $job.Destination

    if ([string]::IsNullOrWhiteSpace($srcConfigured) -or [string]::IsNullOrWhiteSpace($dstBase)) {
        continue
    }

    if ([IO.Path]::IsPathRooted($srcConfigured)) {
        $src = $srcConfigured
    } else {
        $src = Join-Path $UsbRoot $srcConfigured
    }

    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host ("WARN: Source not found: {0} - skipping." -f $src) -ForegroundColor Yellow
        continue
    }

    $itemName  = Split-Path -LiteralPath $src -Leaf
    $srcIsFile = Test-Path -LiteralPath $src -PathType Leaf

    if ($srcIsFile) {
        $actualDst = $dstBase
        Ensure-Dir $actualDst
        $jobTitle = "File: " + $itemName
        $args = @((Split-Path -LiteralPath $src -Parent), $actualDst, $itemName) + $RobocopySwitches
    } else {
        $actualDst = Join-Path $dstBase $itemName
        Ensure-Dir $actualDst
        $jobTitle = "Folder: " + $itemName
        $args = @($src, $actualDst) + $RobocopySwitches
    }

    # Visual Header for each job
    Write-Host ""
    Write-Host ">>> JOB $($i + 1) OF $TotalJobs: Copying $jobTitle" -ForegroundColor Cyan
    Write-Host ">>> FROM: $src" -ForegroundColor Cyan
    Write-Host ">>> TO:   $actualDst" -ForegroundColor Cyan
    Write-Host "---------------------------------------------------" -ForegroundColor Cyan

    # Run Robocopy natively in the foreground so it prints to the console
    & "$env:SystemRoot\System32\robocopy.exe" @args

    # Check the exit code of the native run
    $rc = $LASTEXITCODE
    if ($rc -ge 8) {
        Write-Host "ERROR: Robocopy encountered critical errors (Exit Code $rc)." -ForegroundColor Red
    } else {
        Write-Host "SUCCESS: Job completed cleanly (Exit Code $rc)." -ForegroundColor Green
    }
    Write-Host "---------------------------------------------------" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Magenta
Write-Host " ALL COPY JOBS FINISHED." -ForegroundColor Magenta
Write-Host "===================================================" -ForegroundColor Magenta
# Pause at the end so the window doesn't immediately close if you double-clicked the script
Pause