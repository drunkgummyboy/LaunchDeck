$ErrorActionPreference = 'Stop';$ProgressPreference = 'SilentlyContinue';
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;

$ScriptPath = if ($PSCommandPath) { $PSCommandPath; } else {$MyInvocation.MyCommand.Path; };
$ScriptDir = Split-Path -Parent ($ScriptPath);
$JsonFilePath = Join-Path ($ScriptDir) ("apps.json");

$LogPath = "C:\Windows\Temp\FirstLogonApps_$(Get-Date -Format 'yyyyMMdd_HHmmss').log";
$IconCacheDir = Join-Path ($env:TEMP) ("LaunchDeck\Icons");

if (-not (Test-Path -LiteralPath ($IconCacheDir))) {
New-Item -ItemType Directory -Path ($IconCacheDir) -Force | Out-Null;
}

function Write-Info { param([string]$m); Write-Host "[*] $m" -ForegroundColor Cyan; }
function Write-Warn { param([string]$m); Write-Host "[!] $m" -ForegroundColor Yellow; }

function Test-Winget {
try { (Get-Command winget.exe -ErrorAction Stop) | Out-Null; return $true; } catch { return$false; }
}

function Test-WingetPackageInstalled {
param([string]$Id);
try {
$listOutput = cmd.exe /c "winget.exe list --id $Id --exact --accept-source-agreements 2>NUL";
return ($LASTEXITCODE -eq 0) -and ($listOutput -match [regex]::Escape($Id));
} catch { return $false; }
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
if (-not $ScriptPath -or -not (Test-Path -LiteralPath ($ScriptPath))) {
[System.Windows.Forms.MessageBox]::Show("Cannot self-elevate: script was not launched from a file.", "Error", 0, 16) | Out-Null;
return;
}
Write-Info "Requesting administrative privileges...";
Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList ("-NoExit","-NoProfile","-ExecutionPolicy","Bypass","-File","`"$ScriptPath`"");
return;
}

if (-not (Test-Path -LiteralPath ($JsonFilePath))) {
[System.Windows.Forms.MessageBox]::Show("Could not find apps.json. Please ensure it is in the exact same folder as LaunchDeck.ps1.`n`nLooking in: $ScriptDir", "Missing File", 0, 16) | Out-Null;
return;
}

$WingetAppsList = Get-Content -Raw -Path ($JsonFilePath) | ConvertFrom-Json;

$Form = New-Object System.Windows.Forms.Form;
$Form.Text = "System Provisioning Setup";
$Form.Size = New-Object System.Drawing.Size(975, 520);$Form.StartPosition = "CenterScreen";
$Form.FormBorderStyle = "Sizable";
$Form.MaximizeBox =$true;

function New-FormLabel {
param([string]$Text, [int]$X, [int]$Y, [switch]$Bold);$lbl = New-Object System.Windows.Forms.Label;
$lbl.Text =$Text;
$lbl.Location = New-Object System.Drawing.Point($X,$Y);
$lbl.AutoSize =$true;
if ($Bold) {$lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold); }
return $lbl;
}

$TitleLabel = New-FormLabel -Text "Select Applications to Install:" -X 15 -Y 15 -Bold;
$Form.Controls.Add($TitleLabel);

$TotalApps = @($WingetAppsList).Count;
$CounterLabel = New-FormLabel -Text "$TotalApps / $TotalApps Selected" -X 260 -Y 15;
$CounterLabel.ForeColor = [System.Drawing.Color]::Gray;
$Form.Controls.Add($CounterLabel);

$BtnSelectAll = New-Object System.Windows.Forms.Button;
$BtnSelectAll.Text = "Select All";
$BtnSelectAll.Location = New-Object System.Drawing.Point(415, 12);
$BtnSelectAll.Size = New-Object System.Drawing.Size(75, 25);$BtnSelectAll.Cursor = [System.Windows.Forms.Cursors]::Hand;
$Form.Controls.Add($BtnSelectAll);

$BtnDeselectAll = New-Object System.Windows.Forms.Button;
$BtnDeselectAll.Text = "Deselect All";
$BtnDeselectAll.Location = New-Object System.Drawing.Point(495, 12);
$BtnDeselectAll.Size = New-Object System.Drawing.Size(85, 25);$BtnDeselectAll.Cursor = [System.Windows.Forms.Cursors]::Hand;
$Form.Controls.Add($BtnDeselectAll);

$WingetLabel = New-FormLabel -Text "Winget Packages:" -X 15 -Y 45;
$Form.Controls.Add($WingetLabel);

$FlowPanel = New-Object System.Windows.Forms.FlowLayoutPanel;
$FlowPanel.Location = New-Object System.Drawing.Point(15, 65);$FlowPanel.Size = New-Object System.Drawing.Size(700, 340);
$FlowPanel.AutoScroll =$true;
$FlowPanel.Anchor = "Top, Bottom, Left, Right";
$Form.Controls.Add($FlowPanel);

$UpdateCounterAction = {$currentCount = 0;
foreach ($c in ($FlowPanel.Controls)) {
if ($c.GetType().Name -eq "CheckBox" -and $c.Checked) {$currentCount++; }
}
$CounterLabel.Text = "$currentCount / $TotalApps Selected";
};

$BtnSelectAll.Add_Click({$FlowPanel.SuspendLayout();
foreach ($c in ($FlowPanel.Controls)) {
if ($c.GetType().Name -eq "CheckBox") { $c.Checked =$true; }
}
$FlowPanel.ResumeLayout();
& $UpdateCounterAction;
});

$BtnDeselectAll.Add_Click({$FlowPanel.SuspendLayout();
foreach ($c in ($FlowPanel.Controls)) {
if ($c.GetType().Name -eq "CheckBox") { $c.Checked =$false; }
}
$FlowPanel.ResumeLayout();
& $UpdateCounterAction;
});

foreach ($appObj in ($WingetAppsList)) {
$appName =$appObj.Name;
$appId =$appObj.Id;
$appDomain =$appObj.Domain;

$Card = New-Object System.Windows.Forms.CheckBox;
$Card.Appearance = [System.Windows.Forms.Appearance]::Button;
$Card.Text =$appName;
$Card.Tag =$appId;
$Card.Size = New-Object System.Drawing.Size(115, 85);$Card.TextAlign = [System.Drawing.ContentAlignment]::BottomCenter;
$Card.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageAboveText;
$Card.Checked =$true;
$Card.Cursor = [System.Windows.Forms.Cursors]::Hand;
$Card.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat;
$Card.FlatAppearance.BorderColor = [System.Drawing.Color]::LightGray;
$Card.FlatAppearance.CheckedBackColor = [System.Drawing.Color]::LightSkyBlue;
$Card.Add_Click($UpdateCounterAction);

if (-not [string]::IsNullOrWhiteSpace($appDomain)) {
try {
$FaviconUrl = "https://www.google.com/s2/favicons?domain=$($appDomain)&sz=32";
$SafeIconName = ($appName -replace '[^a-zA-Z0-9]', '_') + ".png";
$cacheFile = Join-Path ($IconCacheDir) ($SafeIconName);

if (-not (Test-Path -LiteralPath ($cacheFile))) {
Invoke-WebRequest -Uri ($FaviconUrl) -OutFile ($cacheFile) -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop;
}
$srcImg = [System.Drawing.Image]::FromFile($cacheFile);$CardIconSize = New-Object System.Drawing.Size(32, 32);
$Card.Image = New-Object System.Drawing.Bitmap($srcImg, $CardIconSize);$srcImg.Dispose();
} catch {}
}
$FlowPanel.Controls.Add($Card);
}

$RightPane = New-Object System.Windows.Forms.GroupBox;
$RightPane.Text = "Other Scripts";
$RightPane.Location = New-Object System.Drawing.Point(735, 15);
$RightPane.Size = New-Object System.Drawing.Size(200, 380);$RightPane.Anchor = "Top, Bottom, Right";
$Form.Controls.Add($RightPane);

$SideButtonToolTip = New-Object System.Windows.Forms.ToolTip;
$script:ButtonY = 30;

$GlobalClickAction = {
try {
$btnData =$this.Tag;
$File =$btnData.FileName;
$Url =$btnData.DownloadUrl;

$TempFile = Join-Path ($env:TEMP) ($File);

Invoke-WebRequest -Uri ($Url) -OutFile ($TempFile) -UseBasicParsing -ErrorAction Stop;
Start-Process -FilePath "powershell.exe" -ArgumentList ("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$TempFile`"") -ErrorAction Stop;
} catch {
[System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Launch Error", 0, 16) | Out-Null;
}
};

function Add-SideButton {
param($BtnText, $FileName,$DownloadUrl, $IconUrl,$HoverText);

$NewButton = New-Object System.Windows.Forms.Button;
$NewButton.Text =$BtnText;
$NewButton.Location = New-Object System.Drawing.Point(30, $script:ButtonY);$NewButton.Size = New-Object System.Drawing.Size(140, 35);

$NewButton.Tag = @{ FileName = $FileName; DownloadUrl =$DownloadUrl };

if (-not [string]::IsNullOrWhiteSpace($HoverText)) {$SideButtonToolTip.SetToolTip($NewButton,$HoverText);
}

if (-not [string]::IsNullOrWhiteSpace($IconUrl)) {
try {
$SafeImageName = ($BtnText.Trim() -replace '[^a-zA-Z0-9]', '_') + ".png";
$CacheFile = Join-Path ($IconCacheDir) ($SafeImageName);
if (-not (Test-Path -LiteralPath ($CacheFile))) {
Invoke-WebRequest -Uri ($IconUrl) -OutFile ($CacheFile) -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop;
}
$image = [System.Drawing.Image]::FromFile($CacheFile);
$IconSize = New-Object System.Drawing.Size(20, 20);$bmp = New-Object System.Drawing.Bitmap($image,$IconSize);
$NewButton.Image =$bmp;
$NewButton.ImageAlign = [System.Drawing.ContentAlignment]::MiddleLeft;
$NewButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$NewButton.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageBeforeText;
$image.Dispose();
} catch {}
}

$NewButton.Add_Click($GlobalClickAction);

$RightPane.Controls.Add($NewButton);$script:ButtonY += 45;
}

$GithubOwner = "drunkgummyboy";
$GithubRepo = "LaunchDeck";
$GithubBranch = "main";
$ApiBase = "https://api.github.com/repos/$GithubOwner/$GithubRepo/contents";
$ApiHeaders = @{ "User-Agent" = "PowerShell-LaunchDeck" };

$FaviconMap = @{
"WinUtil" = "christitus.com";
"Office"  = "microsoft.com";
};
$DescriptionMap = @{
"WinUtil" = "Launches the Chris Titus Tech Windows Utility.";
"Office"  = "quickly remove, download, or activate Microsoft Office.";
"SetName"  = "Tool to rename the computer and update its boot menu description.";
"Shortcuts"  = "Generates desktop shortcuts for torrent files.";
"upgrade all"  = "Runs Winget upgrade.";
};

try {
$ScriptFiles = Invoke-RestMethod -Uri ($ApiBase + "/scripts?ref=" + $GithubBranch) -Headers ($ApiHeaders) -UseBasicParsing -ErrorAction Stop;
$SubScripts =$ScriptFiles | Where-Object { $_.type -eq 'file' -and$_.name -like "*.ps1" };

if (-not $SubScripts) {
[System.Windows.Forms.MessageBox]::Show("No .ps1 files found.", "Notice", 0, 64) | Out-Null;
}

foreach ($FileObj in ($SubScripts)) {
$ButtonName = [System.IO.Path]::GetFileNameWithoutExtension($FileObj.name);

$MatchedIconUrl =$null;
if ($FaviconMap.ContainsKey($ButtonName)) {
$MatchedIconUrl = "https://www.google.com/s2/favicons?domain=$($FaviconMap[$ButtonName])&sz=32";
}

$HoverText = if ($DescriptionMap.ContainsKey($ButtonName)) { $DescriptionMap[$ButtonName]; } else { "Download and run $($FileObj.name)"; };

$SafeName = $FileObj.name -replace ' ', '\%20';$RawUrl = "https://raw.githubusercontent.com/$GithubOwner/$GithubRepo/$GithubBranch/scripts/$SafeName";

Add-SideButton -BtnText ($ButtonName) -FileName ($FileObj.name) -DownloadUrl ($RawUrl) -IconUrl ($MatchedIconUrl) -HoverText ($HoverText);
}
} catch {
[System.Windows.Forms.MessageBox]::Show("Failed to load GitHub scripts.`n`n$($_.Exception.Message)", "GitHub API Error", 0, 16) | Out-Null;
}

$OKButton = New-Object System.Windows.Forms.Button;
$OKButton.Text = "Install Selected";
$OKButton.Location = New-Object System.Drawing.Point(510, 420);
$OKButton.Size = New-Object System.Drawing.Size(120, 35);$OKButton.Anchor = "Bottom, Right";
$Form.Controls.Add($OKButton);

$CancelButton = New-Object System.Windows.Forms.Button;
$CancelButton.Text = "Close";
$CancelButton.Location = New-Object System.Drawing.Point(640, 420);
$CancelButton.Size = New-Object System.Drawing.Size(75, 35);$CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel;
$CancelButton.Anchor = "Bottom, Right";
$Form.Controls.Add($CancelButton);

$Form.AcceptButton =$OKButton;
$Form.CancelButton =$CancelButton;

$OKButton.Add_Click({$WingetApps = @();
foreach ($card in ($FlowPanel.Controls)) {
if ($card.GetType().Name -eq "CheckBox" -and $card.Checked) {
$WingetApps +=$card.Tag;
}
}

if ($WingetApps.Count -eq 0) {
[System.Windows.Forms.MessageBox]::Show("No applications selected.", "Notice", 0, 48) | Out-Null;
return;
}

$OKButton.Enabled =$false;
$CancelButton.Enabled =$false;
Clear-Host;
Start-Transcript -Path ($LogPath) -Append -ErrorAction SilentlyContinue;

if (-not (Test-Winget)) {
try {
$VCLibsPath = "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx";
Invoke-WebRequest -Uri ("https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx") -OutFile ($VCLibsPath);
Add-AppxPackage ($VCLibsPath) -ErrorAction SilentlyContinue;

$XamlPath = "$env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx";
Invoke-WebRequest -Uri ("https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx") -OutFile ($XamlPath);
Add-AppxPackage ($XamlPath) -ErrorAction SilentlyContinue;

Invoke-WebRequest -Uri ("https://aka.ms/getwinget") -OutFile ("$env:TEMP\AppInstaller.msixbundle");
Add-AppxPackage ("$env:TEMP\AppInstaller.msixbundle");

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User");
} catch {}
}

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

if (Test-Winget) {
$StatusLabel.Text = "Updating Winget sources...";
[System.Windows.Forms.Application]::DoEvents();
Start-Process -FilePath "winget.exe" -ArgumentList ("source", "update") -Wait -NoNewWindow -ErrorAction SilentlyContinue;

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

$Process = Start-Process -FilePath "winget.exe" -ArgumentList ("install","--exact","--id",$id,"--accept-package-agreements","--accept-source-agreements","--silent") -Wait -NoNewWindow -PassThru;
$InstallProgressBar.Value =$counter;
[System.Windows.Forms.Application]::DoEvents();

if ($Process.ExitCode -eq 0) { $successCount++; } else {$failCount++; }
}
} else {
[System.Windows.Forms.MessageBox]::Show("Winget is unavailable. Skipping installation.", "Error", 0, 16) | Out-Null;
}

Stop-Transcript | Out-Null;
$ProgressForm.Close();$ProgressForm.Dispose();

$SummaryMessage = "Provisioning Complete!`n`nInstalled: $successCount`nAlready Present: $skipCount`nFailed: $failCount`n`nLog saved to: $LogPath";
[System.Windows.Forms.MessageBox]::Show($SummaryMessage, "LaunchDeck", 0, 64) | Out-Null;

$OKButton.Enabled =$true;
$CancelButton.Enabled =$true;
});

$Form.ShowDialog() | Out-Null;
$Form.Dispose();
exit;
