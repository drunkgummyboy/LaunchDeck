<# :
@echo off
setlocal
pushd "%~dp0"
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    popd
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$scriptPath='%~dp0'; IEX ([System.IO.File]::ReadAllText('%~f0'))"
popd
exit /b
#>

# --- LaunchDeck PowerShell Logic ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Updated Path Logic  ---
$basePath = $scriptPath                             
$parentDir = Split-Path $basePath -Parent        
$scriptsDir = Join-Path $parentDir "scripts"  
$logoPath = Join-Path $basePath "logo.png"          
$Global:CurrentProcess = $null
$Global:RunningScriptPath = $null

# --- Theme ---
$colBack    = [System.Drawing.Color]::FromArgb(32, 32, 32)
$colSide    = [System.Drawing.Color]::FromArgb(45, 45, 45)
$colAccent  = [System.Drawing.Color]::FromArgb(0, 120, 212)
$colHover   = [System.Drawing.Color]::FromArgb(65, 65, 65)
$colSelected = [System.Drawing.Color]::FromArgb(55, 55, 55)
$colText    = [System.Drawing.Color]::FromArgb(245, 245, 245)
$colSubText = [System.Drawing.Color]::FromArgb(160, 160, 160)

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "LaunchDeck"
$Form.Size = New-Object System.Drawing.Size(1000, 700)
$Form.StartPosition = "CenterScreen"
$Form.BackColor = $colBack
$Form.Font = New-Object System.Drawing.Font("Segoe UI Variable Display", 10)

# --- Sidebar ---
$Sidebar = New-Object System.Windows.Forms.Panel
$Sidebar.Dock = "Left"
$Sidebar.Width = 280
$Sidebar.BackColor = $colSide
$Form.Controls.Add($Sidebar)

$LogoBox = New-Object System.Windows.Forms.PictureBox
$LogoBox.Size = New-Object System.Drawing.Size(120, 120)
$LogoBox.Location = New-Object System.Drawing.Point(80, 25)
$LogoBox.SizeMode = "Zoom"
if (Test-Path $logoPath) { $LogoBox.Image = [System.Drawing.Image]::FromFile($logoPath) }
else { $LogoBox.Visible = $false }
$Sidebar.Controls.Add($LogoBox)

$DynamicTitle = New-Object System.Windows.Forms.Label
$DynamicTitle.Text = "LAUNCHDECK"
$DynamicTitle.Font = New-Object System.Drawing.Font("Segoe UI Variable Display", 9, [System.Drawing.FontStyle]::Bold)
$DynamicTitle.ForeColor = $colSubText
$DynamicTitle.TextAlign = "MiddleCenter"
$DynamicTitle.Location = New-Object System.Drawing.Point(20, 160)
$DynamicTitle.Size = New-Object System.Drawing.Size(240, 40)
$Sidebar.Controls.Add($DynamicTitle)

$ScriptList = New-Object System.Windows.Forms.ListBox
$ScriptList.Location = New-Object System.Drawing.Point(0, 200)
$ScriptList.Size = New-Object System.Drawing.Size(280, 450)
$ScriptList.BackColor = $colSide
$ScriptList.BorderStyle = "None"
$ScriptList.DrawMode = "OwnerDrawFixed"
$ScriptList.ItemHeight = 45
$Sidebar.Controls.Add($ScriptList)

# --- Context Menu ---
$ContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$itemEdit = $ContextMenu.Items.Add("Edit in Notepad")
$itemLocation = $ContextMenu.Items.Add("Open File Location")
$itemRunAdmin = $ContextMenu.Items.Add("Run as Administrator")

$itemEdit.Add_Click({
    if ($ScriptList.SelectedItem) { Start-Process "notepad.exe" $ScriptList.SelectedItem.FullName }
})
$itemLocation.Add_Click({
    if ($ScriptList.SelectedItem) { Start-Process "explorer.exe" "/select,`"$($ScriptList.SelectedItem.FullName)`"" }
})
$itemRunAdmin.Add_Click({
    if ($ScriptList.SelectedItem) {
        $fileObj = $ScriptList.SelectedItem
        Log "Starting Administrator elevated script..."
        
        # Detect if it's a Batch file or a PowerShell file
        if ($fileObj.Extension -match "(?i)\.(bat|cmd)$") {
            Start-Process "cmd.exe" -ArgumentList "/k `"$($fileObj.FullName)`"" -Verb RunAs -WorkingDirectory $scriptsDir
        } else {
            Start-Process "powershell.exe" -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$($fileObj.FullName)`"" -Verb RunAs -WorkingDirectory $scriptsDir
        }
    }
})

$ScriptList.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $idx = $ScriptList.IndexFromPoint($e.Location)
        if ($idx -ge 0) {
            $ScriptList.SelectedIndex = $idx
            $ContextMenu.Show($ScriptList, $e.Location)
        }
    }
})

# --- Console Area ---
$Console = New-Object System.Windows.Forms.TextBox
$Console.Location = New-Object System.Drawing.Point(310, 80)
$Console.Size = New-Object System.Drawing.Size(640, 550)
$Console.Multiline = $true
$Console.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$Console.ForeColor = [System.Drawing.Color]::FromArgb(166, 227, 161)
$Console.Font = New-Object System.Drawing.Font("Cascadia Code", 10)
$Console.BorderStyle = "None"
$Console.ReadOnly = $true
$Console.ScrollBars = "Vertical"
$Form.Controls.Add($Console)

# --- Action Buttons ---
function Create-Btn($txt, $x, $clr) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $txt
    $b.Location = New-Object System.Drawing.Point($x, 25)
    $b.Size = New-Object System.Drawing.Size(100, 35)
    $b.FlatStyle = "Flat"
    $b.BackColor = $clr
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatAppearance.BorderSize = 0
    $Form.Controls.Add($b)
    return $b
}
$btnRefresh = Create-Btn "Refresh" 310 ($colAccent)
$btnClear   = Create-Btn "Clear" 420 ($colSide)
$btnStop    = Create-Btn "Stop" 850 ([System.Drawing.Color]::FromArgb(196, 43, 28))

# --- Core Logic ---
function Log($m) { $Form.Invoke([Action]{ $Console.AppendText(" > $m`r`n"); $Console.ScrollToCaret() }) }

function Refresh-Scripts {
    $ScriptList.Items.Clear()
    $DynamicTitle.Text = "LAUNCHDECK"
    if (!(Test-Path -LiteralPath $scriptsDir)) { New-Item -ItemType Directory -Path $scriptsDir | Out-Null }
    Get-ChildItem -LiteralPath $scriptsDir -File | ForEach-Object { $ScriptList.Items.Add($_) | Out-Null }
    Log "System Ready. Found $($ScriptList.Items.Count) scripts."
}

$btnRefresh.Add_Click({ Refresh-Scripts })
$btnClear.Add_Click({ $Console.Clear() })

# Update the Stop button to also clear the visual status
$btnStop.Add_Click({ 
    if ($Global:CurrentProcess -and !$Global:CurrentProcess.HasExited) { 
        $Global:CurrentProcess.Kill()
        Log "Process force-stopped." 
        $Global:RunningScriptPath = $null
        $ScriptList.Invalidate()
    } else {
        Log "No background process is currently running."
    }
})

$ScriptList.Add_SelectedIndexChanged({
    if ($ScriptList.SelectedItem) { $DynamicTitle.Text = $ScriptList.SelectedItem.BaseName.ToUpper() }
})

# --- Execution Logic ---
$ScriptList.Add_MouseDoubleClick({
    if ($ScriptList.SelectedItem) {
        $fileObj = $ScriptList.SelectedItem
        Log "Starting $($fileObj.Name)..."
        
        # Detect if it's a Batch file or a PowerShell file
        if ($fileObj.Extension -match "(?i)\.(bat|cmd)$") {
            $Global:CurrentProcess = Start-Process "cmd.exe" -ArgumentList "/k `"$($fileObj.FullName)`"" -WorkingDirectory $scriptsDir -PassThru
        } else {
            $Global:CurrentProcess = Start-Process "powershell.exe" -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$($fileObj.FullName)`"" -WorkingDirectory $scriptsDir -PassThru
        }
        
        $Global:RunningScriptPath = $fileObj.FullName
        $ScriptList.Invalidate()
        
        $Global:CurrentProcess.EnableRaisingEvents = $true
        Register-ObjectEvent -InputObject $Global:CurrentProcess -EventName Exited -Action {
            $Global:RunningScriptPath = $null
            $Global:CurrentProcess = $null
            $Form.Invoke([Action]{ 
                $ScriptList.Invalidate() 
                $Console.AppendText(" > Process Finished.`r`n")
                $Console.ScrollToCaret()
            })
        } | Out-Null
    }
})

# --- Styling & Hover Logic ---
$Global:HoverIndex = -1
$ScriptList.Add_MouseMove({ 
    $idx = $ScriptList.IndexFromPoint($($args[1]).Location)
    if ($idx -ne $Global:HoverIndex) { $Global:HoverIndex = $idx; $ScriptList.Invalidate() } 
})
$ScriptList.Add_MouseLeave({ $Global:HoverIndex = -1; $ScriptList.Invalidate() })

$ScriptList.Add_DrawItem({
    param($s, $e)
    
    if ($e.Index -lt 0) { return }
    
    $rect = $e.Bounds
    [float]$rX = $rect.X
    [float]$rY = $rect.Y
    [float]$rW = $rect.Width
    [float]$rH = $rect.Height
    
    $g = $e.Graphics
    $g.SmoothingMode = "AntiAlias"
    $isSelected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected)
    
    if ($isSelected) {
        $accentBrush = New-Object System.Drawing.SolidBrush($colAccent)
        $bgSelectedBrush = New-Object System.Drawing.SolidBrush($colSelected)
        $g.FillRectangle($accentBrush, $rX+5, $rY+10, 4, $rH-20)
        $g.FillRectangle($bgSelectedBrush, $rX+12, $rY+2, $rW-20, $rH-4)
    } elseif ($e.Index -eq $Global:HoverIndex) {
        $bgHoverBrush = New-Object System.Drawing.SolidBrush($colHover)
        $g.FillRectangle($bgHoverBrush, $rX+12, $rY+2, $rW-20, $rH-4)
    }
    
    $iconFont = New-Object System.Drawing.Font("Segoe MDL2 Assets", 12)
    $iconBrush = New-Object System.Drawing.SolidBrush($colAccent)
    $g.DrawString([char]0xE8C6, $iconFont, $iconBrush, [float]($rX+22), [float]($rY+13))
    
    # --- Safe Layout Math ---
    $itemObj = $s.Items[$e.Index]
    $isRunning = ($itemObj.FullName -eq $Global:RunningScriptPath)
    
    [float]$availW = 200
    if ($isRunning) { $availW = 145 }
    
    $textFormat = New-Object System.Drawing.StringFormat
    $textFormat.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $textFormat.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
    
    [float]$tX = $rX + 55
    [float]$tY = $rY + 11
    
    $textRect = New-Object System.Drawing.RectangleF -ArgumentList $tX, $tY, $availW, $rH
    $textBrush = New-Object System.Drawing.SolidBrush($colText)
    
    $g.DrawString($itemObj.BaseName, $e.Font, $textBrush, $textRect, $textFormat)

    # --- Status Indicator Drawing ---
    if ($isRunning) {
        $statusFont = New-Object System.Drawing.Font("Segoe UI Variable Display", 8, [System.Drawing.FontStyle]::Bold)
        $statusBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::MediumSeaGreen)
        $g.DrawString("RUNNING", $statusFont, $statusBrush, [float]($rX+205), [float]($rY+14))
    }
})

$Form.Add_Shown({ Refresh-Scripts })
$Form.ShowDialog() | Out-Null