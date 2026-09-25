@echo off
:: Auto-elevate to Admin
>nul 2>&1 net session
if %errorLevel% neq 0 (
    echo Requesting administrative privileges...
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

setlocal
set "BASE=%~dp0"
set "DRIVERFOLDER=%BASE%drivers"

:: (Re)create destination
if exist "%DRIVERFOLDER%" (
    echo Clearing %DRIVERFOLDER% ...
    del /s /q "%DRIVERFOLDER%\*" >nul 2>&1
    for /d %%p in ("%DRIVERFOLDER%\*") do rmdir "%%p" /s /q >nul 2>&1
) else (
    mkdir "%DRIVERFOLDER%"
)

echo Exporting only setup-critical drivers (Storage, USB, Network) ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$classes = @('SCSIAdapter','HDC','USB','Net');" ^
  "$dest = '%DRIVERFOLDER%';" ^
  "$drv = Get-WindowsDriver -Online | Where-Object { $classes -contains $_.ClassName };" ^
  "if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null };" ^
  "if ($drv.Count -eq 0) { Write-Host 'No third-party drivers found for the selected classes.'; exit 0 }" ^
  "foreach ($d in $drv) {" ^
  "  Write-Host (' - ' + $d.Driver + '  [' + $d.ClassName + ']');" ^
  "  pnputil /export-driver $($d.Driver) $dest | Out-Null" ^
  "};" ^
  "Write-Host ('Done. Exported ' + $drv.Count + ' driver package(s).')"

echo.
echo ✅ Minimal set exported to %DRIVERFOLDER%
pause
