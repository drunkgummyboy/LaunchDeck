Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;

# Self-Elevate to Administrator Privileges
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);
if (-not $IsAdmin) {
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs;
        exit;
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please save this script as a .ps1 file and run it, or run PowerShell as Administrator.", "Admin Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null;
        exit 1;
    }
}

# Main Form Setup
$MainForm = New-Object System.Windows.Forms.Form;
$MainForm.Text = "System Configuration Utility";
$MainForm.Size = New-Object System.Drawing.Size(380, 330);
$MainForm.StartPosition = "CenterScreen";
$MainForm.FormBorderStyle = "FixedDialog";
$MainForm.MaximizeBox = $false;

# --- SECTION 1: Rename Computer ---
$GroupRename = New-Object System.Windows.Forms.GroupBox;
$GroupRename.Text = "Rename Computer";
$GroupRename.Location = New-Object System.Drawing.Point(15, 15);
$GroupRename.Size = New-Object System.Drawing.Size(335, 110);
$MainForm.Controls.Add($GroupRename);

$CurrentNameLabel = New-Object System.Windows.Forms.Label;
$CurrentNameLabel.Text = "Current name: $env:COMPUTERNAME";
$CurrentNameLabel.Location = New-Object System.Drawing.Point(15, 25);
$CurrentNameLabel.AutoSize = $true;
$GroupRename.Controls.Add($CurrentNameLabel);

$NewNameLabel = New-Object System.Windows.Forms.Label;
$NewNameLabel.Text = "New name:";
$NewNameLabel.Location = New-Object System.Drawing.Point(15, 53);
$NewNameLabel.AutoSize = $true;
$GroupRename.Controls.Add($NewNameLabel);

# Generate User-based PC names and enforce 15-character limit
$cleanUserName = $env:USERNAME -replace '[^a-zA-Z0-9-]', '';
$userPC = "$cleanUserName-PC";
if ($userPC.Length -gt 15) { $userPC = $userPC.Substring(0, 15); }
$userLT = "$cleanUserName-LT";
if ($userLT.Length -gt 15) { $userLT = $userLT.Substring(0, 15); }

# ComboBox for predefined or custom PC name
$NewNameCombo = New-Object System.Windows.Forms.ComboBox;
$NewNameCombo.Location = New-Object System.Drawing.Point(90, 50);
$NewNameCombo.Size = New-Object System.Drawing.Size(225, 20);
$NewNameCombo.MaxLength = 15;
$NewNameCombo.Items.AddRange(@($userPC, $userLT, "Workstation-01", "Laptop-01", "Office-PC", "Home-PC"));
$GroupRename.Controls.Add($NewNameCombo);

$ApplyRenameBtn = New-Object System.Windows.Forms.Button;
$ApplyRenameBtn.Text = "Rename PC";
$ApplyRenameBtn.Location = New-Object System.Drawing.Point(215, 75);
$ApplyRenameBtn.Size = New-Object System.Drawing.Size(100, 25);
$GroupRename.Controls.Add($ApplyRenameBtn);

$ApplyRenameBtn.Add_Click({
    $newComputerName = $NewNameCombo.Text.Trim();

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
            [System.Windows.Forms.MessageBox]::Show("Failed to rename computer:`n$($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null;
        }
    }
});

# --- SECTION 2: Set Boot Name ---
$GroupBoot = New-Object System.Windows.Forms.GroupBox;
$GroupBoot.Text = "Boot Manager";
$GroupBoot.Location = New-Object System.Drawing.Point(15, 135);$GroupBoot.Size = New-Object System.Drawing.Size(335, 100);
$MainForm.Controls.Add($GroupBoot);

$culture = Get-Culture;
$monthYear = (Get-Date -Format "MMMM yyyy");
$monthYear = $culture.TextInfo.ToTitleCase($monthYear);
$dynamicBootName = "Windows $monthYear";

$BootDescLabel = New-Object System.Windows.Forms.Label;
$BootDescLabel.Text = "New boot name:";
$BootDescLabel.Location = New-Object System.Drawing.Point(15, 25);
$BootDescLabel.AutoSize =$true;
$GroupBoot.Controls.Add($BootDescLabel);

# ComboBox for predefined or custom boot entry name
$BootNameCombo = New-Object System.Windows.Forms.ComboBox;
$BootNameCombo.Location = New-Object System.Drawing.Point(110, 22);$BootNameCombo.Size = New-Object System.Drawing.Size(205, 20);
$BootNameCombo.Items.AddRange(@($dynamicBootName, "Windows 10", "Windows 11", "Windows (Safe Mode)"));
$BootNameCombo.Text =$dynamicBootName;
$GroupBoot.Controls.Add($BootNameCombo);

$ApplyBootBtn = New-Object System.Windows.Forms.Button;
$ApplyBootBtn.Text = "Update Boot Entry";
$ApplyBootBtn.Location = New-Object System.Drawing.Point(195, 60);$ApplyBootBtn.Size = New-Object System.Drawing.Size(120, 25);
$GroupBoot.Controls.Add($ApplyBootBtn);

$ApplyBootBtn.Add_Click({
    $newDesc =$BootNameCombo.Text.Trim();
    
    if ([string]::IsNullOrWhiteSpace($newDesc)) {
        [System.Windows.Forms.MessageBox]::Show("Enter a boot name first.", "Boot Manager", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null;
        return;
    }

    try {
        $process = Start-Process -FilePath "bcdedit.exe" -ArgumentList "/set {current} description `"$newDesc`"" -Wait -NoNewWindow -PassThru;
        
        if ($process.ExitCode -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Boot entry successfully updated to:`n$newDesc", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null;
        } else {
            [System.Windows.Forms.MessageBox]::Show("bcdedit failed with exit code $($process.ExitCode)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null;
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("An error occurred while updating the boot entry.`n$($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null;
    }
});

# --- Close Button ---
$CloseBtn = New-Object System.Windows.Forms.Button;
$CloseBtn.Text = "Close";
$CloseBtn.Location = New-Object System.Drawing.Point(250, 250);
$CloseBtn.Size = New-Object System.Drawing.Size(100, 25);$CloseBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel;
$MainForm.Controls.Add($CloseBtn);

$MainForm.CancelButton =$CloseBtn;

# Render GUI
[void]$MainForm.ShowDialog();$MainForm.Dispose();