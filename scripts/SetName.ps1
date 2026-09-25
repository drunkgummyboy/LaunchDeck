Add-Type -AssemblyName System.Windows.Forms

$SubForm = New-Object System.Windows.Forms.Form
$SubForm.Text = "Office Scripts"
$SubForm.Size = New-Object System.Drawing.Size(300, 250)
$SubForm.StartPosition = "CenterParent"
$SubForm.FormBorderStyle = "FixedDialog"
$SubForm.MaximizeBox = $false

$SubRemoveButton = New-Object System.Windows.Forms.Button
$SubRemoveButton.Text = "Office Removal"
$SubRemoveButton.Location = New-Object System.Drawing.Point(50, 30)
$SubRemoveButton.Size = New-Object System.Drawing.Size(180, 40)
$SubRemoveButton.Add_Click({
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iwr https://get.admon.me/remove-msoffice -OutFile msoffice-removal-tool.ps1; .\msoffice-removal-tool.ps1 -Force -SuppressReboot`"" -Verb RunAs
    $SubForm.Close()
})
$SubForm.Controls.Add($SubRemoveButton)

$SubDownloadButton = New-Object System.Windows.Forms.Button
$SubDownloadButton.Text = "Office Download"
$SubDownloadButton.Location = New-Object System.Drawing.Point(50, 80)
$SubDownloadButton.Size = New-Object System.Drawing.Size(180, 40)
$SubDownloadButton.Add_Click({
    Start-Process -FilePath "https://massgrave.dev/genuine-installation-media"
    $SubForm.Close()
})
$SubForm.Controls.Add($SubDownloadButton)

$SubActivateButton = New-Object System.Windows.Forms.Button
$SubActivateButton.Text = "Office Activate"
$SubActivateButton.Location = New-Object System.Drawing.Point(50, 130)
$SubActivateButton.Size = New-Object System.Drawing.Size(180, 40)
$SubActivateButton.Add_Click({
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://get.activated.win | iex`"" -Verb RunAs
    $SubForm.Close()
})
$SubForm.Controls.Add($SubActivateButton)

$SubForm.ShowDialog() | Out-Null
$SubForm.Dispose()