<#
   LaunchDeck.ps1
   - Interactive GUI setup script using Windows Forms
   - Ensures winget is installed, then installs selected apps
   - Logs to C:\Windows\Temp\FirstLogonApps_<timestamp>.log
#>

$ErrorActionPreference = 'Stop';
$ProgressPreference = 'SilentlyContinue';
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

# Timestamped log so it doesn't grow forever
$LogPath = "C:\Windows\Temp\FirstLogonApps_$(Get-Date -Format 'yyyyMMdd_HHmmss').log";

# Local cache for side-button icons so they aren't re-downloaded on every run
$IconCacheDir = Join-Path $env:TEMP 'LaunchDeck\Icons';
if (-not (Test-Path -LiteralPath $IconCacheDir)) {
    New-Item -ItemType Directory -Path $IconCacheDir -Force | Out-Null;
}

# --- Helpers -----------------------------------------------------------------

function Write-Info {
    <#
    .SYNOPSIS
        Writes an informational message to the console in cyan.
    .PARAMETER m
        The message text to display.
    #>
    param([string]$m);
    Write-Host "[*] $m" -ForegroundColor Cyan;
}

function Write-Warn {
    <#
    .SYNOPSIS
        Writes a warning message to the console in yellow.
    .PARAMETER m
        The message text to display.
    #>
    param([string]$m);
    Write-Host "[!] $m" -ForegroundColor Yellow;
}

function Test-Winget {
    <#
    .SYNOPSIS
        Checks whether winget.exe is available on the current PATH.
    .OUTPUTS
        [bool] True if winget is installed and resolvable, otherwise false.
    #>
    try {
        (Get-Command winget.exe -ErrorAction Stop) | Out-Null;
        return $true;
    } catch {
        return $false;
    }
}

function Test-WingetPackageInstalled {
    <#
    .SYNOPSIS
        Checks whether a package ID is already installed, via `winget list`.
    .PARAMETER Id
        The exact winget package ID to check for.
    .PARAMETER WingetPath
        Path or command name of the winget executable to use.
    .OUTPUTS
        [bool] True if the package is already present, otherwise false.
    #>
    param(
        [string]$Id,
        [string]$WingetPath
    );

    $listOutput = & $WingetPath list --id $Id --exact --accept-source-agreements 2>$null;
    return ($LASTEXITCODE -eq 0) -and ($listOutput -match [regex]::Escape($Id));
}

# --- Elevation Check -----------------------------------------------------------

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $ScriptPath = if ($PSCommandPath) { $PSCommandPath; } else { $MyInvocation.MyCommand.Path; };
    if (-not $ScriptPath -or -not (Test-Path -LiteralPath $ScriptPath)) {
        Write-Warn "Cannot self-elevate: script was not launched from a file. Please re-run this script from an elevated prompt.";
        Start-Sleep -Seconds 3;
        exit 1;
    }

    Write-Info "Requesting administrative privileges...";
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @(
        "-NoExit","-NoProfile","-ExecutionPolicy","Bypass","-File","`"$ScriptPath`""
    );
    exit;
}

# --- Define Default Apps -------------------------------------------------------
# NOTE: If any of these IDs fail with "No package found matching input criteria",
#       verify with:  winget search --exact --id <ID>
$WingetAppsMap = [ordered]@{
    "PowerToys"        = "Microsoft.PowerToys";
    "7-Zip"            = "7zip.7zip";
    "Firefox"          = "Mozilla.Firefox";
    "Google Drive"     = "Google.googleDrive";
    "VLC"              = "VideoLAN.VLC";
    "Discord"          = "Discord.Discord";
    "Paint.NET"        = "dotPDN.paintdotnet";
    "FileBot"          = "PointPlanck.FileBot";
    "F3D"              = "f3d-app.f3d";
    "STL-Thumb"        = "UnlimitedBacon.STL-Thumb";
    "Node.js"          = "OpenJS.NodeJS";
    "Python"           = "Python.Python.3";
    "Spotify"          = "Spotify.Spotify";
    "File Converter"   = "AdrienAllard.FileConverter";
    "Bambu Studio"     = "Bambulab.Bambustudio";
    "Windows Terminal" = "Microsoft.WindowsTerminal";
};

# --- GUI Creation (Windows Forms) -----------------------------------------------

Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;

$Form = New-Object System.Windows.Forms.Form;
$Form.Text = "System Provisioning Setup";
$Form.Size = New-Object System.Drawing.Size(650, 520);
$Form.StartPosition = "CenterScreen";
$Form.FormBorderStyle = "FixedDialog";
$Form.MaximizeBox = $false;

function New-FormLabel {
    <#
    .SYNOPSIS
        Creates a positioned, auto-sized Windows Forms label.
    .PARAMETER Text
        The label's display text.
    .PARAMETER X
        Horizontal position in pixels.
    .PARAMETER Y
        Vertical position in pixels.
    .PARAMETER Bold
        Renders the label in bold Segoe UI 10pt when set.
    #>
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

# Winget Label
$WingetLabel = New-FormLabel -Text "Winget Packages:" -X 15 -Y 45;
$Form.Controls.Add($WingetLabel);

# Winget CheckedListBox (taller now that Choco list is gone)
$WingetList = New-Object System.Windows.Forms.CheckedListBox;
$WingetList.Location = New-Object System.Drawing.Point(15, 65);
$WingetList.Size = New-Object System.Drawing.Size(370, 330);
$WingetList.CheckOnClick = $true;
foreach ($appName in $WingetAppsMap.Keys) { $null = $WingetList.Items.Add($appName, $true); }
$Form.Controls.Add($WingetList);

# --- RIGHT PANE (Other Scripts) -------------------------------------------------

$RightPane = New-Object System.Windows.Forms.GroupBox;
$RightPane.Text = "Other Scripts";
$RightPane.Location = New-Object System.Drawing.Point(410, 15);
$RightPane.Size = New-Object System.Drawing.Size(200, 380);
$Form.Controls.Add($RightPane);

$script:ButtonY = 30;

function Add-SideButton {
    <#
    .SYNOPSIS
        Adds a click-to-run button to the "Other Scripts" side panel.
    .PARAMETER Name
        The button's display text.
    .PARAMETER Code
        A scriptblock to run when the button is clicked.
    .PARAMETER IconUrl
        Optional URL of a small icon to show on the button. Downloaded once
        and cached under $IconCacheDir so later runs load it from disk.
    #>
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
            $CacheFile = Join-Path $IconCacheDir ("{0}.png" -f ($Name.Trim() -replace '[^a-zA-Z0-9]', '_'));

            if (-not (Test-Path -LiteralPath $CacheFile)) {
                Invoke-WebRequest -Uri $IconUrl -OutFile $CacheFile;
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
# ADD YOUR CUSTOM BUTTONS HERE
# ================================================================================

# Button 1
Add-SideButton -Name " WinUtil" -IconUrl "https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/refs/heads/main/LaunchDeck/CTTtools.ico" -Code {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm christitus.com/win | iex`"" -Verb RunAs;
};

# Button 2
Add-SideButton -Name "Office" -IconUrl "https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/refs/heads/main/LaunchDeck/microsoft-logo.png" -Code {
    $SubForm = New-Object System.Windows.Forms.Form;
    $SubForm.Text = "Office Scripts";
    $SubForm.Size = New-Object System.Drawing.Size(300, 250);
    $SubForm.StartPosition = "CenterParent";
    $SubForm.FormBorderStyle = "FixedDialog";
    $SubForm.MaximizeBox = $false;

    $SubRemoveButton = New-Object System.Windows.Forms.Button;
    $SubRemoveButton.Text = "Office Removal";
    $SubRemoveButton.Location = New-Object System.Drawing.Point(50, 30);
    $SubRemoveButton.Size = New-Object System.Drawing.Size(180, 40);
    $SubRemoveButton.Add_Click({
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iwr https://get.admon.me/remove-msoffice -OutFile msoffice-removal-tool.ps1; .\msoffice-removal-tool.ps1 -Force -SuppressReboot`"" -Verb RunAs;
        $SubForm.Close();
    });
    $SubForm.Controls.Add($SubRemoveButton);

    $SubDownloadButton = New-Object System.Windows.Forms.Button;
    $SubDownloadButton.Text = "Office Download";
    $SubDownloadButton.Location = New-Object System.Drawing.Point(50, 80);
    $SubDownloadButton.Size = New-Object System.Drawing.Size(180, 40);
    $SubDownloadButton.Add_Click({
        Start-Process -FilePath "https://massgrave.dev/genuine-installation-media";
        $SubForm.Close();
    });
    $SubForm.Controls.Add($SubDownloadButton);

    $SubActivateButton = New-Object System.Windows.Forms.Button;
    $SubActivateButton.Text = "Office Activate";
    $SubActivateButton.Location = New-Object System.Drawing.Point(50, 130);
    $SubActivateButton.Size = New-Object System.Drawing.Size(180, 40);
    $SubActivateButton.Add_Click({
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://get.activated.win | iex`"" -Verb RunAs;
        $SubForm.Close();
    });
    $SubForm.Controls.Add($SubActivateButton);

    $SubForm.ShowDialog() | Out-Null;
    $SubForm.Dispose();
};

# Button 3
Add-SideButton -Name "Set Boot Name" -Code {
    $BootForm = New-Object System.Windows.Forms.Form;
    $BootForm.Text = "Set Boot Name";
    $BootForm.Size = New-Object System.Drawing.Size(350, 200);
    $BootForm.StartPosition = "CenterParent";
    $BootForm.FormBorderStyle = "FixedDialog";
    $BootForm.MaximizeBox = $false;

    $culture = Get-Culture;
    $monthYear = (Get-Date -Format "MMMM yyyy");
    $monthYear = $culture.TextInfo.ToTitleCase($monthYear);
    $defaultName = "Windows $monthYear";

    # Radio: Default Month/Year
    $RadioDefault = New-Object System.Windows.Forms.RadioButton;
    $RadioDefault.Text = "Default ($defaultName)";
    $RadioDefault.Location = New-Object System.Drawing.Point(20, 20);
    $RadioDefault.Size = New-Object System.Drawing.Size(300, 20);
    $RadioDefault.Checked = $true;
    $BootForm.Controls.Add($RadioDefault);

    # Radio: Custom
    $RadioCustom = New-Object System.Windows.Forms.RadioButton;
    $RadioCustom.Text = "Custom:";
    $RadioCustom.Location = New-Object System.Drawing.Point(20, 50);
    $RadioCustom.Size = New-Object System.Drawing.Size(70, 20);
    $BootForm.Controls.Add($RadioCustom);

    # TextBox: Custom Name
    $TextBoxCustom = New-Object System.Windows.Forms.TextBox;
    $TextBoxCustom.Location = New-Object System.Drawing.Point(90, 50);
    $TextBoxCustom.Size = New-Object System.Drawing.Size(210, 20);
    $TextBoxCustom.Enabled = $false;
    $BootForm.Controls.Add($TextBoxCustom);

    # Event to toggle TextBox
    $RadioCustom.Add_CheckedChanged({
        $TextBoxCustom.Enabled = $RadioCustom.Checked;
    });

    # Apply Button
    $ApplyBtn = New-Object System.Windows.Forms.Button;
    $ApplyBtn.Text = "Apply";
    $ApplyBtn.Location = New-Object System.Drawing.Point(80, 110);
    $ApplyBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK;
    $BootForm.Controls.Add($ApplyBtn);

    # Cancel Button
    $CancelBtn = New-Object System.Windows.Forms.Button;
    $CancelBtn.Text = "Cancel";
    $CancelBtn.Location = New-Object System.Drawing.Point(180, 110);
    $CancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel;
    $BootForm.Controls.Add($CancelBtn);

    $BootForm.AcceptButton = $ApplyBtn;
    $BootForm.CancelButton = $CancelBtn;

    $result = $BootForm.ShowDialog();

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $newName = if ($RadioCustom.Checked -and -not [string]::IsNullOrWhiteSpace($TextBoxCustom.Text)) {
            $TextBoxCustom.Text;
        } else {
            $defaultName;
        };

        # Build the script string to run in the elevated prompt
        $ScriptString = @"
            `$newDesc = "$newName";
            `$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);
            if (-not `$IsAdmin) {
                Write-Error "Please run this script in PowerShell **as Administrator**.";
                Start-Sleep -Seconds 3;
                exit 1;
            }

            Write-Host "Setting boot entry description to: `$newDesc";
            & bcdedit /set '{current}' description "`$newDesc";

            if (`$LASTEXITCODE -eq 0) {
                Write-Host "`nUpdated. Current entries:";
                & bcdedit /enum;
            } else {
                Write-Error "bcdedit failed with exit code `$LASTEXITCODE";
            }

            Write-Host "`nPress any key to close...";
            `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
            exit `$LASTEXITCODE;
"@;

        $Bytes = [System.Text.Encoding]::Unicode.GetBytes($ScriptString);
        $Encoded = [Convert]::ToBase64String($Bytes);
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $Encoded" -Verb RunAs;
    }

    $BootForm.Dispose();
};

# Button 4
Add-SideButton -Name "Rename Computer" -Code {
    $RenameForm = New-Object System.Windows.Forms.Form;
    $RenameForm.Text = "Rename Computer";
    $RenameForm.Size = New-Object System.Drawing.Size(340, 170);
    $RenameForm.StartPosition = "CenterParent";
    $RenameForm.FormBorderStyle = "FixedDialog";
    $RenameForm.MaximizeBox = $false;

    $CurrentNameLabel = New-FormLabel -Text "Current name: $env:COMPUTERNAME" -X 20 -Y 20;
    $RenameForm.Controls.Add($CurrentNameLabel);

    $NewNameLabel = New-FormLabel -Text "New name:" -X 20 -Y 55;
    $RenameForm.Controls.Add($NewNameLabel);

    $NewNameBox = New-Object System.Windows.Forms.TextBox;
    $NewNameBox.Location = New-Object System.Drawing.Point(100, 52);
    $NewNameBox.Size = New-Object System.Drawing.Size(200, 20);
    $NewNameBox.MaxLength = 15;
    $RenameForm.Controls.Add($NewNameBox);

    $ApplyBtn = New-Object System.Windows.Forms.Button;
    $ApplyBtn.Text = "Apply";
    $ApplyBtn.Location = New-Object System.Drawing.Point(80, 105);
    $ApplyBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK;
    $RenameForm.Controls.Add($ApplyBtn);

    $CancelBtn = New-Object System.Windows.Forms.Button;
    $CancelBtn.Text = "Cancel";
    $CancelBtn.Location = New-Object System.Drawing.Point(180, 105);
    $CancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel;
    $RenameForm.Controls.Add($CancelBtn);

    $RenameForm.AcceptButton = $ApplyBtn;
    $RenameForm.CancelButton = $CancelBtn;

    $result = $RenameForm.ShowDialog();

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $newComputerName = $NewNameBox.Text.Trim();

        if ([string]::IsNullOrWhiteSpace($newComputerName)) {
            [System.Windows.Forms.MessageBox]::Show("Enter a computer name first.", "Rename Computer", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null;
        } elseif ($newComputerName -notmatch '^[a-zA-Z0-9-]{1,15}$') {
            [System.Windows.Forms.MessageBox]::Show("Names can only use letters, numbers, and hyphens (max 15 characters).", "Rename Computer", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null;
        } elseif ($newComputerName -eq $env:COMPUTERNAME) {
            [System.Windows.Forms.MessageBox]::Show("That's already the current name.", "Rename Computer", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null;
        } else {
            try {
                Rename-Computer -NewName $newComputerName -Force -ErrorAction Stop;
                $confirmRestart = [System.Windows.Forms.MessageBox]::Show("Renamed to '$newComputerName'. This needs a restart to take effect. Restart now?", "Rename Computer", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question);
                if ($confirmRestart -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Restart-Computer -Force;
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Rename failed: $($_.Exception.Message)", "Rename Computer", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null;
            }
        }
    }

    $RenameForm.Dispose();
};

# Button 5
Add-SideButton -Name "Upgrade All" -Code {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"winget upgrade --all --accept-package-agreements --accept-source-agreements`"" -Verb RunAs;
};

# ================================================================================

# OK Button
$OKButton = New-Object System.Windows.Forms.Button;
$OKButton.Text = "Install Selected";
$OKButton.Location = New-Object System.Drawing.Point(180, 420);
$OKButton.Size = New-Object System.Drawing.Size(120, 35);
$OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK;
$Form.Controls.Add($OKButton);

# Cancel Button
$CancelButton = New-Object System.Windows.Forms.Button;
$CancelButton.Text = "Cancel";
$CancelButton.Location = New-Object System.Drawing.Point(310, 420);
$CancelButton.Size = New-Object System.Drawing.Size(75, 35);
$CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel;
$Form.Controls.Add($CancelButton);

$Form.AcceptButton = $OKButton;
$Form.CancelButton = $CancelButton;

# Show the GUI and capture the result
$Result = $Form.ShowDialog();
$Form.Dispose();

if ($Result -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Warn "Installation aborted by user.";
    Start-Sleep -Seconds 2;
    exit;
}

# --- Extract Selected Apps from GUI ---------------------------------------------
$WingetApps = @();
foreach ($item in $WingetList.CheckedItems) { $WingetApps += $WingetAppsMap[$item]; }

if ($WingetApps.Count -eq 0) {
    Write-Warn "No applications selected. Exiting...";
    Start-Sleep -Seconds 2;
    exit;
}

# --- Begin Installation Process --------------------------------------------------
Clear-Host;
Write-Info "Starting deployment based on selection...";
Start-Transcript -Path $LogPath -Append -ErrorAction SilentlyContinue;

# --- Winget bootstrap ---
if (-not (Test-Winget)) {
    Write-Info "Bootstrapping Winget and dependencies...";
    try {
        $VCLibsPath = "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx";
        Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile $VCLibsPath;
        Add-AppxPackage $VCLibsPath -ErrorAction SilentlyContinue;

        $XamlPath = "$env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx";
        Invoke-WebRequest -Uri "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -OutFile $XamlPath;
        Add-AppxPackage $XamlPath -ErrorAction SilentlyContinue;

        Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile "$env:TEMP\AppInstaller.msixbundle";
        Add-AppxPackage "$env:TEMP\AppInstaller.msixbundle";

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User");
    } catch {
        Write-Warn "Winget bootstrap failed. Ensure Windows is updated.";
    }
}

$Winget = if (Test-Winget) { "winget.exe"; } else { $null; };

Write-Host "`n=======================================================" -ForegroundColor Cyan;
Write-Host "             INSTALLING APPLICATIONS                   " -ForegroundColor White;
Write-Host "=======================================================" -ForegroundColor Cyan;

# --- Install Winget Apps ---------------------------------------------------------
if ($Winget) {
    Write-Info "Updating Winget sources...";
    Start-Process $Winget -ArgumentList "source update" -Wait -NoNewWindow -ErrorAction SilentlyContinue;

    $total = $WingetApps.Count;
    $counter = 0;
    $successCount = 0;
    $skipCount = 0;
    $failCount = 0;

    $ProgressForm = New-Object System.Windows.Forms.Form;
    $ProgressForm.Text = "Installing Applications";
    $ProgressForm.Size = New-Object System.Drawing.Size(420, 150);
    $ProgressForm.StartPosition = "CenterScreen";
    $ProgressForm.FormBorderStyle = "FixedDialog";
    $ProgressForm.MaximizeBox = $false;
    $ProgressForm.ControlBox = $false;
    $ProgressForm.TopMost = $true;

    $StatusLabel = New-FormLabel -Text "Starting..." -X 15 -Y 15;
    $StatusLabel.AutoSize = $false;
    $StatusLabel.Size = New-Object System.Drawing.Size(380, 20);
    $ProgressForm.Controls.Add($StatusLabel);

    $InstallProgressBar = New-Object System.Windows.Forms.ProgressBar;
    $InstallProgressBar.Location = New-Object System.Drawing.Point(15, 45);
    $InstallProgressBar.Size = New-Object System.Drawing.Size(380, 25);
    $InstallProgressBar.Minimum = 0;
    $InstallProgressBar.Maximum = $total;
    $InstallProgressBar.Value = 0;
    $ProgressForm.Controls.Add($InstallProgressBar);

    $CountLabel = New-FormLabel -Text "0 of $total" -X 15 -Y 80;
    $ProgressForm.Controls.Add($CountLabel);

    $ProgressForm.Show();
    $ProgressForm.Refresh();

    foreach ($id in $WingetApps) {
        $counter++;
        $CountLabel.Text = "$counter of $total";

        if (Test-WingetPackageInstalled -Id $id -WingetPath $Winget) {
            $skipCount++;
            $StatusLabel.Text = "Already installed: $id";
            $InstallProgressBar.Value = $counter;
            [System.Windows.Forms.Application]::DoEvents();
            Write-Host "[$counter/$total] $id already installed - skipping" -ForegroundColor DarkGray;
            continue;
        }

        $StatusLabel.Text = "Installing: $id";
        [System.Windows.Forms.Application]::DoEvents();

        $Process = Start-Process $Winget -ArgumentList @(
            "install","--exact","--id",$id,
            "--accept-package-agreements","--accept-source-agreements","--silent"
        ) -Wait -NoNewWindow -PassThru;

        $InstallProgressBar.Value = $counter;
        [System.Windows.Forms.Application]::DoEvents();

        if ($Process.ExitCode -eq 0) {
            $successCount++;
            Write-Host "[$counter/$total] $id " -NoNewline;
            Write-Host "[SUCCESS]" -ForegroundColor Green;
        } else {
            $failCount++;
            Write-Host "[$counter/$total] $id " -NoNewline;
            Write-Host "[FAILED: Code $($Process.ExitCode)]" -ForegroundColor Red;
        }
    }

    $StatusLabel.Text = "Done.";
    [System.Windows.Forms.Application]::DoEvents();
    Start-Sleep -Milliseconds 500;
    $ProgressForm.Close();
    $ProgressForm.Dispose();

    Write-Info "Installed: $successCount, Already present: $skipCount, Failed: $failCount";
} else {
    Write-Warn "Winget is unavailable. Skipping installation.";
}

Write-Host "`n=======================================================" -ForegroundColor Cyan;
Write-Host "             PROVISIONING COMPLETE                     " -ForegroundColor White;
Write-Host "=======================================================" -ForegroundColor Cyan;
Write-Info "Log saved to: $LogPath";

Stop-Transcript | Out-Null;
Write-Host "`nPress any key to close..." -ForegroundColor Cyan;
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
