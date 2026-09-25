<#
   LaunchDeck.ps1
   - Interactive GUI setup script using Windows Forms
   - Ensures winget is installed, then installs selected apps with icons
   - Logs to C:\Windows\Temp\FirstLogonApps_<timestamp>.log
#>

$ErrorActionPreference = 'Stop';
$ProgressPreference = 'SilentlyContinue';
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;

# Timestamped log so it doesn't grow forever
$LogPath = "C:\Windows\Temp\FirstLogonApps_$(Get-Date -Format 'yyyyMMdd_HHmmss').log";

# Local cache for side-button and app icons so they aren't re-downloaded on every run
$IconCacheDir = Join-Path ($env:TEMP) 'LaunchDeck\Icons';
if (-not (Test-Path -LiteralPath ($IconCacheDir))) {
    New-Item -ItemType Directory -Path ($IconCacheDir) -Force | Out-Null;
}

# --- Helpers -----------------------------------------------------------------

function Write-Info {
    param([string]$m);
    Write-Host "[*] $($m)" -ForegroundColor Cyan;
}

function Write-Warn {
    param([string]$m);
    Write-Host "[!] $($m)" -ForegroundColor Yellow;
}

function Test-Winget {
    try {
        (Get-Command winget.exe -ErrorAction Stop) | Out-Null;
        return $true;
    } catch {
        return $false;
    }
}

function Test-WingetPackageInstalled {
    param([string]$Id)
    try {
        # Using cmd.exe bypasses PowerShell's command cache which can fail right after an AppX package installs
        $listOutput = cmd.exe /c "winget.exe list --id $($Id) --exact --accept-source-agreements 2>NUL";
        return ($LASTEXITCODE -eq 0) -and ($listOutput -match [regex]::Escape($Id));
    } catch {
        return $false;
    }
}

# --- Elevation Check -----------------------------------------------------------

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $ScriptPath = if ($PSCommandPath) { $PSCommandPath; } else { $MyInvocation.MyCommand.Path; };
    if (-not $ScriptPath -or -not (Test-Path -LiteralPath ($ScriptPath))) {
        [System.Windows.Forms.MessageBox]::Show("Cannot self-elevate: script was not launched from a file.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null;
        return;
    }

    Write-Info "Requesting administrative privileges...";
    # -NoExit keeps the window open ONLY if there is a parsing error, otherwise the exit command at the bottom closes it.
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @(
        "-NoExit","-NoProfile","-ExecutionPolicy","Bypass","-File","`"$ScriptPath`""
    );
    # This return stops the un-elevated VS Code script without killing your editor
    return;
}

# --- Define Default Apps -------------------------------------------------------
$WingetAppsMap = [ordered]@{
    "PowerToys" = @{
        Id   = "Microsoft.PowerToys"
        Icon = "https://upload.wikimedia.org/wikipedia/commons/1/19/2020_PowerToys_Icon.png?utm_source=commons.wikimedia.org&utm_campaign=index&utm_content=thumbnail_unscaled&_=20211006185044"
    }
    "7-Zip" = @{
        Id   = "7zip.7zip"
        Icon = "https://www.7-zip.org/favicon.ico"
    }
    "Firefox" = @{
        Id   = "Mozilla.Firefox"
        Icon = "https://www.firefox.com/media/img/favicons/firefox/browser/favicon.f093404c0135.ico"
    }
    "Google Drive" = @{
        Id   = "Google.googleDrive"
        Icon = "https://ssl.gstatic.com/images/branding/product/1x/drive_2020q4_32dp.png"
    }
    "VLC" = @{
        Id   = "VideoLAN.VLC"
        Icon = "https://www.videolan.org/favicon.ico"
    }
    "Discord" = @{
        Id   = "Discord.Discord"
        Icon = "https://assets-global.website-files.com/6257adef93867e50d84d30e2/636e0a6a49cf127bf92de1e2_icon_clyde_blurple_RGB.png"
    }
    "Paint.NET" = @{
        Id   = "dotPDN.paintdotnet"
        Icon = "https://paint.net/favicon.ico"
    }
    "FileBot" = @{
        Id   = "PointPlanck.FileBot"
        Icon = "https://www.filebot.net/favicon.ico"
    }
    "F3D" = @{
        Id   = "f3d-app.f3d"
        Icon = "https://f3d.app/logos/favicon.ico"
    }
    "STL-Thumb" = @{
        Id   = "UnlimitedBacon.STL-Thumb"
        Icon = "https://user-images.githubusercontent.com/3131268/170938020-5c2495ca-f7ab-44c1-9d76-d994bff277f6.png"
    }
    "Node.js" = @{
        Id   = "OpenJS.NodeJS"
        Icon = "https://nodejs.org/static/images/favicons/favicon.png"
    }
    "Python" = @{
        Id   = "Python.Python.3"
        Icon = "https://www.python.org/static/favicon.ico"
    }
    "Spotify" = @{
        Id   = "Spotify.Spotify"
        Icon = "https://open.spotifycdn.com/cdn/images/favicon32.b64ecc03.png"
    }
    "File Converter" = @{
        Id   = "AdrienAllard.FileConverter"
        Icon = "https://file-converter.io/images/application-icon.png"
    }
    "Bambu Studio" = @{
        Id   = "Bambulab.Bambustudio"
        Icon = "https://bambulab.com/favicon.ico"
    }
    "Windows Terminal" = @{
        Id   = "Microsoft.WindowsTerminal"
        Icon = "https://raw.githubusercontent.com/microsoft/terminal/main/res/terminal.ico"
    }
    "Visual Studio Code" = @{
        Id   = "Microsoft.VisualStudioCode"
        Icon = "https://code.visualstudio.com/favicon.ico"
    }
}

# --- GUI Creation (Windows Forms) -----------------------------------------------

$Form = New-Object System.Windows.Forms.Form;
$Form.Text = "System Provisioning Setup";
$Form.Size = New-Object System.Drawing.Size(975, 520);
$Form.StartPosition = "CenterScreen";
$Form.FormBorderStyle = "Sizable";
$Form.MaximizeBox = $true;

function New-FormLabel {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [switch]$Bold
    );

    $lbl = New-Object System.Windows.Forms.Label;
    $lbl.Text = $Text;
    $lbl.Location = New-Object System.Drawing.Point($X, $Y);
    $lbl.AutoSize = $true;
    if ($Bold) {
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold);
    }
    return $lbl;
}

# Title Label
$TitleLabel = New-FormLabel -Text "Select Applications to Install:" -X 15 -Y 15 -Bold;
$Form.Controls.Add($TitleLabel);

$TotalApps = $WingetAppsMap.Count;

# Selection Counter
$CounterLabel = New-FormLabel -Text "$TotalApps / $TotalApps Selected" -X 260 -Y 15;
$CounterLabel.ForeColor = [System.Drawing.Color]::Gray;
$Form.Controls.Add($CounterLabel);

# Select All Button
$BtnSelectAll = New-Object System.Windows.Forms.Button;
$BtnSelectAll.Text = "Select All";
$BtnSelectAll.Location = New-Object System.Drawing.Point(415, 12);
$BtnSelectAll.Size = New-Object System.Drawing.Size(75, 25);
$BtnSelectAll.Cursor = [System.Windows.Forms.Cursors]::Hand;
$Form.Controls.Add($BtnSelectAll);

# Deselect All Button
$BtnDeselectAll = New-Object System.Windows.Forms.Button;
$BtnDeselectAll.Text = "Deselect All";
$BtnDeselectAll.Location = New-Object System.Drawing.Point(495, 12);
$BtnDeselectAll.Size = New-Object System.Drawing.Size(85, 25);
$BtnDeselectAll.Cursor = [System.Windows.Forms.Cursors]::Hand;
$Form.Controls.Add($BtnDeselectAll);

# Winget Label
$WingetLabel = New-FormLabel -Text "Winget Packages:" -X 15 -Y 45;
$Form.Controls.Add($WingetLabel);

# Create a FlowLayoutPanel for the cards
$FlowPanel = New-Object System.Windows.Forms.FlowLayoutPanel;
$FlowPanel.Location = New-Object System.Drawing.Point(15, 65);
$FlowPanel.Size = New-Object System.Drawing.Size(700, 340);
$FlowPanel.AutoScroll = $true;
$FlowPanel.Anchor = "Top, Bottom, Left, Right";
$Form.Controls.Add($FlowPanel);

# Scriptblock to update the counter
$UpdateCounterAction = {
    $currentCount = 0;
    foreach ($c in ($FlowPanel.Controls)) {
        if ($c.GetType().Name -eq "CheckBox" -and $c.Checked) {
            $currentCount++;
        }
    }
    $CounterLabel.Text = "$currentCount / $TotalApps Selected";
}

# Actions for the Toggle Buttons
$BtnSelectAll.Add_Click({
    $FlowPanel.SuspendLayout();
    foreach ($c in ($FlowPanel.Controls)) {
        if ($c.GetType().Name -eq "CheckBox") { $c.Checked = $true; }
    }
    $FlowPanel.ResumeLayout();
    & $UpdateCounterAction;
})

$BtnDeselectAll.Add_Click({
    $FlowPanel.SuspendLayout();
    foreach ($c in ($FlowPanel.Controls)) {
        if ($c.GetType().Name -eq "CheckBox") { $c.Checked = $false; }
    }
    $FlowPanel.ResumeLayout();
    & $UpdateCounterAction;
})

# Populate items and resolve/cache icons
foreach ($appName in ($WingetAppsMap.Keys)) {
    $entry = $WingetAppsMap[$appName];

    # Create a CheckBox styled as a flat Card/Button
    $Card = New-Object System.Windows.Forms.CheckBox;
    $Card.Appearance = [System.Windows.Forms.Appearance]::Button;
    $Card.Text = $appName;
    $Card.Tag = $entry.Id;
    $Card.Size = New-Object System.Drawing.Size(115, 85);
    $Card.TextAlign = [System.Drawing.ContentAlignment]::BottomCenter;
    $Card.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageAboveText;
    $Card.Checked = $true;
    $Card.Cursor = [System.Windows.Forms.Cursors]::Hand;
    
    # Styling for selected/unselected states
    $Card.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat;
    $Card.FlatAppearance.BorderColor = [System.Drawing.Color]::LightGray;
    $Card.FlatAppearance.CheckedBackColor = [System.Drawing.Color]::LightSkyBlue;

    # Update counter when a card is manually clicked
    $Card.Add_Click($UpdateCounterAction);

    if (-not [string]::IsNullOrWhiteSpace($entry.Icon)) {
        try {
            $ext = [System.IO.Path]::GetExtension($entry.Icon.Split('?')[0]);
            if (-not $ext -or $ext.Length -gt 5) { $ext = ".ico"; }
            $cacheFile = Join-Path ($IconCacheDir) ("{0}{1}" -f ($appName -replace '[^a-zA-Z0-9]', '_'), $ext);

            if (-not (Test-Path -LiteralPath ($cacheFile))) {
                Invoke-WebRequest -Uri ($entry.Icon) -OutFile ($cacheFile) -TimeoutSec 5 -ErrorAction Stop;
            }

            $srcImg = [System.Drawing.Image]::FromFile($cacheFile);
            $CardIconSize = New-Object System.Drawing.Size(32, 32);
            $Card.Image = New-Object System.Drawing.Bitmap($srcImg, $CardIconSize);
            $srcImg.Dispose(); 
        } catch {
            Write-Warn "Could not load icon for $($appName). Using default.";
        }
    }

    $FlowPanel.Controls.Add($Card);
}

# --- RIGHT PANE (Other Scripts) -------------------------------------------------

$RightPane = New-Object System.Windows.Forms.GroupBox;
$RightPane.Text = "Other Scripts";
$RightPane.Location = New-Object System.Drawing.Point(735, 15);
$RightPane.Size = New-Object System.Drawing.Size(200, 380);
$RightPane.Anchor = "Top, Bottom, Right";
$Form.Controls.Add($RightPane);

$script:ButtonY = 30;

function Add-SideButton {
    param(
        [string]$Name,
        [scriptblock]$Code,
        [string]$IconUrl = $null
    );

    $NewButton = New-Object System.Windows.Forms.Button;
    $NewButton.Text = $Name;
    $NewButton.Location = New-Object System.Drawing.Point(30, $script:ButtonY);
    $NewButton.Size = New-Object System.Drawing.Size(140, 35);

    if (-not [string]::IsNullOrWhiteSpace($IconUrl)) {
        try {
            $CacheFile = Join-Path ($IconCacheDir) ("{0}.png" -f ($Name.Trim() -replace '[^a-zA-Z0-9]', '_'));

            if (-not (Test-Path -LiteralPath ($CacheFile))) {
                Invoke-WebRequest -Uri ($IconUrl) -OutFile ($CacheFile);
            }

            $image = [System.Drawing.Image]::FromFile($CacheFile);
            $IconSize = New-Object System.Drawing.Size(20, 20);
            $bmp = New-Object System.Drawing.Bitmap($image, $IconSize);
            $NewButton.Image = $bmp;

            $NewButton.ImageAlign = [System.Drawing.ContentAlignment]::MiddleLeft;
            $NewButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
            $NewButton.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageBeforeText;

            $image.Dispose();
        } catch {
            Write-Warn "Failed to load icon for $($Name). The button will still work without it.";
        }
    }

    $NewButton.Add_Click($Code);
    $RightPane.Controls.Add($NewButton);

    $script:ButtonY += 45;
}

# ================================================================================
# CUSTOM BUTTONS (Fetching scripts from GitHub)
# ================================================================================

# Base URL to your scripts on GitHub
$GithubBase = "https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/refs/heads/main"

Add-SideButton -Name "Create WinUtil shortcut" -IconUrl "$GithubBase/LaunchDeck/CTTtools.ico" -Code {
    Invoke-RestMethod -Uri "$GithubBase/scripts/WinUtil.ps1" | Invoke-Expression
}

Add-SideButton -Name "Office" -IconUrl "$GithubBase/LaunchDeck/microsoft-logo.png" -Code {
    Invoke-RestMethod -Uri "$GithubBase/scripts/Office.ps1" | Invoke-Expression
}

Add-SideButton -Name "Set Name" -Code {
    Invoke-RestMethod -Uri "$GithubBase/scripts/SetName.ps1" | Invoke-Expression
}

Add-SideButton -Name "xxxxxxxx" -Code {
    Invoke-RestMethod -Uri "$GithubBase/scripts/xxxxxxxxxx" | Invoke-Expression
}

Add-SideButton -Name "Upgrade All" -Code {
    Invoke-RestMethod -Uri "$GithubBase/scripts/UpgradeAll.ps1" | Invoke-Expression
}

# ================================================================================

# OK Button
$OKButton = New-Object System.Windows.Forms.Button;
$OKButton.Text = "Install Selected";
$OKButton.Location = New-Object System.Drawing.Point(510, 420);
$OKButton.Size = New-Object System.Drawing.Size(120, 35);$OKButton.Anchor = "Bottom, Right";
$Form.Controls.Add($OKButton);

# Cancel Button
$CancelButton = New-Object System.Windows.Forms.Button;
$CancelButton.Text = "Close";
$CancelButton.Location = New-Object System.Drawing.Point(640, 420);
$CancelButton.Size = New-Object System.Drawing.Size(75, 35);$CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; # This WILL close the form
$CancelButton.Anchor = "Bottom, Right";
$Form.Controls.Add($CancelButton);

$Form.AcceptButton =$OKButton;
$Form.CancelButton =$CancelButton;

# --- Main Installation Logic (Runs inside the button click) ---
$OKButton.Add_Click({$WingetApps = @();
    foreach ($card in ($FlowPanel.Controls)) { 
        if ($card.GetType().Name -eq "CheckBox" -and $card.Checked) {
            $WingetApps +=$card.Tag;
        }
    }

    if ($WingetApps.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No applications selected.", "Notice", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null;
        return;
    }

    # Disable buttons during install to prevent double-clicking
    $OKButton.Enabled =$false;
    $CancelButton.Enabled =$false;

    Clear-Host;
    Start-Transcript -Path ($LogPath) -Append -ErrorAction SilentlyContinue;

    # Winget bootstrap
    if (-not (Test-Winget)) {
        try {
            $VCLibsPath = "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx";
            Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile ($VCLibsPath);
            Add-AppxPackage ($VCLibsPath) -ErrorAction SilentlyContinue;

            $XamlPath = "$env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx";
            Invoke-WebRequest -Uri "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -OutFile ($XamlPath);
            Add-AppxPackage ($XamlPath) -ErrorAction SilentlyContinue;

            Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile ("$env:TEMP\AppInstaller.msixbundle");
            Add-AppxPackage ("$env:TEMP\AppInstaller.msixbundle");

            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User");
        } catch {}
    }

    # GUI Progress Bar Form
    $ProgressForm = New-Object System.Windows.Forms.Form;
    $ProgressForm.Text = "Installing Applications";
    $ProgressForm.Size = New-Object System.Drawing.Size(420, 150);$ProgressForm.StartPosition = "CenterScreen";
    $ProgressForm.FormBorderStyle = "FixedDialog";
    $ProgressForm.MaximizeBox =$false;
    $ProgressForm.ControlBox =$false;
    $ProgressForm.TopMost =$true;

    $StatusLabel = New-FormLabel -Text "Starting..." -X 15 -Y 15;
    $StatusLabel.AutoSize =$false;
    $StatusLabel.Size = New-Object System.Drawing.Size(380, 20);
    $ProgressForm.Controls.Add($StatusLabel);

    $total =$WingetApps.Count;
    $InstallProgressBar = New-Object System.Windows.Forms.ProgressBar;
    $InstallProgressBar.Location = New-Object System.Drawing.Point(15, 45);
    $InstallProgressBar.Size = New-Object System.Drawing.Size(380, 25);$InstallProgressBar.Minimum = 0;
    $InstallProgressBar.Maximum =$total;
    $InstallProgressBar.Value = 0;
    $ProgressForm.Controls.Add($InstallProgressBar);

    $CountLabel = New-FormLabel -Text "0 of $total" -X 15 -Y 80;
    $ProgressForm.Controls.Add($CountLabel);

    $ProgressForm.Show();$ProgressForm.Refresh();

    $successCount = 0;
    $skipCount = 0;
    $failCount = 0;

    # Install Winget Apps
    if (Test-Winget) {
        $StatusLabel.Text = "Updating Winget sources...";
        [System.Windows.Forms.Application]::DoEvents();
        Start-Process -FilePath "winget.exe" -ArgumentList "source update" -Wait -NoNewWindow -ErrorAction SilentlyContinue;

        $counter = 0;

        foreach ($id in ($WingetApps)) {
            $counter++;$CountLabel.Text = "$counter of$total";

            if (Test-WingetPackageInstalled -Id ($id)) {
                $skipCount++;$StatusLabel.Text = "Already installed: $id";
                $InstallProgressBar.Value =$counter;
                [System.Windows.Forms.Application]::DoEvents();
                continue;
            }

            $StatusLabel.Text = "Installing: $id";
            [System.Windows.Forms.Application]::DoEvents();

            $Process = Start-Process -FilePath "winget.exe" -ArgumentList @(
                "install","--exact","--id",($id),
                "--accept-package-agreements","--accept-source-agreements","--silent"
            ) -Wait -NoNewWindow -PassThru;

            $InstallProgressBar.Value =$counter;
            [System.Windows.Forms.Application]::DoEvents();

            if ($Process.ExitCode -eq 0) {$successCount++;
            } else {
                $failCount++;
            }
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Winget is unavailable. Skipping installation.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null;
    }

    Stop-Transcript | Out-Null;

    $ProgressForm.Close();$ProgressForm.Dispose();

    # Final Alert Box
    $SummaryMessage = "Provisioning Complete!`n`nInstalled: $successCount`nAlready Present: $skipCount`nFailed: $failCount`n`nLog saved to: $LogPath";
    [System.Windows.Forms.MessageBox]::Show($SummaryMessage, "LaunchDeck", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null;

    # Re-enable buttons so user can continue using the app
    $OKButton.Enabled =$true;
    $CancelButton.Enabled =$true;
})

# Show the GUI and keep it open until the user clicks "Close" or the X button
$Form.ShowDialog() | Out-Null;
$Form.Dispose();

# Explicit exit so the elevated background shell properly closes when done
exit;
