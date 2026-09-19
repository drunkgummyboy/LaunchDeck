# SetBootName.ps1
# Rename current boot entry to "Windows <Month Year>"

# 1) Require Administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
  Write-Error "Please run this script in PowerShell **as Administrator**."
  exit 1
}

# 2) Build "Month Year" in Title Case (e.g., "September 2025")
$culture   = Get-Culture
$monthYear = (Get-Date -Format "MMMM yyyy")
$monthYear = $culture.TextInfo.ToTitleCase($monthYear)

$newDesc = "Windows $monthYear"
Write-Host "Setting boot entry description to: $newDesc"

# 3) Call bcdedit with quoted {current} so PS doesn't eat the braces
& bcdedit /set '{current}' description "$newDesc"

# 4) Optional: show the result and exit with bcdedit's code
if ($LASTEXITCODE -eq 0) {
  Write-Host "`nUpdated. Current entries:"
  & bcdedit /enum
} else {
  Write-Error "bcdedit failed with exit code $LASTEXITCODE"
}
exit $LASTEXITCODE
