<# FirstLogon-Apps.ps1
   - Interactive GUI setup script using Windows Forms
   - Ensures winget + Chocolatey are installed
   - Logs to C:\Windows\Temp\FirstLogonApps.log
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$LogPath = 'C:\Windows\Temp\FirstLogonApps.log'

# --- Helpers ---
function Write-Info { param([string]$m) Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Warn { param([string]$m) Write-Host "[!] $m" -ForegroundColor Yellow }

# --- Elevation Check ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Info "Requesting administrative privileges..."
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# --- Define Default Apps ----------------------------------------------------
$AllWingetApps = @(
  "Microsoft.PowerToys", "7zip.7zip", "Google.Chrome", "Google.Drive",
  "VideoLAN.VLC", "Discord.Discord", "Mozilla.Firefox", "dotPDNLLC.paintdotnet",
  "File-New-Project.EarTrumpet", "PointPlanck.FileBot", "f3d-app.f3d", "UnlimitedBacon.STL-Thumb", "OpenJS.NodeJS"
)

$AllChocoApps = @("bambustudio", "file-converter")

# --- GUI Creation (Windows Forms) -------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "System Provisioning Setup"
$Form.Size = New-Object System.Drawing.Size(420, 520)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $false
$Form.TopMost = $true

# Title Label
$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = "Select Applications to Install:"
$TitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$TitleLabel.Location = New-Object System.Drawing.Point(15, 15)
$TitleLabel.AutoSize = $true
$Form.Controls.Add($TitleLabel)

# Winget Label
$WingetLabel = New-Object System.Windows.Forms.Label
$WingetLabel.Text = "Winget Packages:"
$WingetLabel.Location = New-Object System.Drawing.Point(15, 45)
$WingetLabel.AutoSize = $true
$Form.Controls.Add($WingetLabel)

# Winget CheckedListBox
$WingetList = New-Object System.Windows.Forms.CheckedListBox
$WingetList.Location = New-Object System.Drawing.Point(15, 65)
$WingetList.Size = New-Object System.Drawing.Size(370, 200)
$WingetList.CheckOnClick = $true
foreach ($app in $AllWingetApps) { $null = $WingetList.Items.Add($app, $true) }
$Form.Controls.Add($WingetList)

# Choco Label
$ChocoLabel = New-Object System.Windows.Forms.Label
$ChocoLabel.Text = "Chocolatey Packages:"
$ChocoLabel.Location = New-Object System.Drawing.Point(15, 275)
$ChocoLabel.AutoSize = $true
$Form.Controls.Add($ChocoLabel)

# Choco CheckedListBox
$ChocoList = New-Object System.Windows.Forms.CheckedListBox
$ChocoList.Location = New-Object System.Drawing.Point(15, 295)
$ChocoList.Size = New-Object System.Drawing.Size(370, 100)
$ChocoList.CheckOnClick = $true
foreach ($app in $AllChocoApps) { $null = $ChocoList.Items.Add($app, $true) }
$Form.Controls.Add($ChocoList)

# OK Button
$OKButton = New-Object System.Windows.Forms.Button
$OKButton.Text = "Install Selected"
$OKButton.Location = New-Object System.Drawing.Point(180, 420)
$OKButton.Size = New-Object System.Drawing.Size(120, 35)
$OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$Form.Controls.Add($OKButton)

# Cancel Button
$CancelButton = New-Object System.Windows.Forms.Button
$CancelButton.Text = "Cancel"
$CancelButton.Location = New-Object System.Drawing.Point(310, 420)
$CancelButton.Size = New-Object System.Drawing.Size(75, 35)
$CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$Form.Controls.Add($CancelButton)

$Form.AcceptButton = $OKButton
$Form.CancelButton = $CancelButton

# Show the GUI and capture the result
$Result = $Form.ShowDialog()

if ($Result -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Warn "Installation aborted by user."
    Start-Sleep -Seconds 2
    exit
}

# --- Extract Selected Apps from GUI ---
$WingetApps = @()
foreach ($item in $WingetList.CheckedItems) { $WingetApps += $item }

$ChocoApps = @()
foreach ($item in $ChocoList.CheckedItems) { $ChocoApps += $item }

# Ensure we actually have things to install
if ($WingetApps.Count -eq 0 -and $ChocoApps.Count -eq 0) {
    Write-Warn "No applications selected. Exiting..."
    Start-Sleep -Seconds 2
    exit
}

# --- Begin Installation Process ---------------------------------------------
Clear-Host
Write-Info "Starting deployment based on selection..."
Start-Transcript -Path $LogPath -Append -ErrorAction SilentlyContinue

# --- Winget bootstrap ---
if ($WingetApps.Count -gt 0) {
    function Test-Winget { try { (Get-Command winget.exe -ErrorAction Stop) | Out-Null; return $true } catch { return $false } }
    
    if (-not (Test-Winget)) {
        Write-Info "Bootstrapping Winget and dependencies..."
        try {
            $VCLibsPath = "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx"
            Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile $VCLibsPath
            Add-AppxPackage $VCLibsPath -ErrorAction SilentlyContinue
            
            $XamlPath = "$env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx"
            Invoke-WebRequest -Uri "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -OutFile $XamlPath
            Add-AppxPackage $XamlPath -ErrorAction SilentlyContinue
    
            Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile "$env:TEMP\AppInstaller.msixbundle"
            Add-AppxPackage "$env:TEMP\AppInstaller.msixbundle"
            
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        } catch { Write-Warn "Winget bootstrap failed. Ensure Windows is updated." }
    }
    $Winget = if (Test-Winget) { "winget.exe" } else { $null }
}

# --- Chocolatey bootstrap ---
if ($ChocoApps.Count -gt 0) {
    function Test-Choco { try { (Get-Command choco.exe -ErrorAction Stop) | Out-Null; return $true } catch { return $false } }
    
    if (-not (Test-Choco)) {
        Write-Info "Bootstrapping Chocolatey..."
        try {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        } catch { Write-Warn "Chocolatey install failed." }
    }
    $Choco = if (Test-Choco) { "choco.exe" } else { $null }
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "             INSTALLING APPLICATIONS                   " -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor Cyan

# --- Install Winget Apps ----------------------------------------------------
if ($Winget -and $WingetApps.Count -gt 0) {
    Write-Info "Updating Winget sources..."
    Start-Process $Winget -ArgumentList "source update" -Wait -NoNewWindow -ErrorAction SilentlyContinue

    $counter = 1
    $total = $WingetApps.Count
    foreach ($id in $WingetApps) {
        Write-Host "[$counter/$total] Installing $id via Winget... " -NoNewline
        
        $Process = Start-Process $Winget -ArgumentList @(
            "install","--exact","--id",$id,
            "--accept-package-agreements","--accept-source-agreements","--silent","--force"
        ) -Wait -NoNewWindow -PassThru

        if ($Process.ExitCode -eq 0) {
            Write-Host "[SUCCESS]" -ForegroundColor Green
        } else {
            Write-Host "[FAILED: Code $($Process.ExitCode)]" -ForegroundColor Red
        }
        $counter++
    }
} elseif ($WingetApps.Count -gt 0) {
    Write-Warn "Winget is unavailable. Skipping Winget packages."
}

# --- Install Choco Apps -----------------------------------------------------
if ($Choco -and $ChocoApps.Count -gt 0) {
    $counter = 1
    $total = $ChocoApps.Count
    foreach ($id in $ChocoApps) {
        Write-Host "[$counter/$total] Installing $id via Choco... " -NoNewline
        
        $Process = Start-Process $Choco -ArgumentList @("install",$id,"-y","--no-progress") -Wait -NoNewWindow -PassThru
        
        if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 3010) { 
            Write-Host "[SUCCESS]" -ForegroundColor Green
        } else {
            Write-Host "[FAILED: Code $($Process.ExitCode)]" -ForegroundColor Red
        }
        $counter++
    }
} elseif ($ChocoApps.Count -gt 0) {
    Write-Warn "Chocolatey is unavailable. Skipping Choco packages."
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "             PROVISIONING COMPLETE                     " -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Info "Log saved to: $LogPath"

Stop-Transcript | Out-Null
Write-Host "`nPress any key to close..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')