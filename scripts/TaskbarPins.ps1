<# 
.SYNOPSIS
Export and import the current user's pinned taskbar icons, optimized for Windows 11.

.EXAMPLES
# Export pins to a zip (creates pins.zip next to the script by default)
.\TaskbarPins.ps1 -Export -OutPath .\pins.zip

# Import pins from a zip on a new machine / profile
.\TaskbarPins.ps1 -Import -ZipPath .\pins.zip
#>

[CmdletBinding(DefaultParameterSetName='Export')]
param(
    [Parameter(ParameterSetName='Export')]
    [switch] $Export,

    [Parameter(ParameterSetName='Export')]
    [string] $OutPath = "$(Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath 'pins.zip')",

    [Parameter(ParameterSetName='Import', Mandatory=$true)]
    [switch] $Import,

    [Parameter(ParameterSetName='Import', Mandatory=$true)]
    [string] $ZipPath
)

function Get-PinFolders {
    $base = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned'
    [pscustomobject]@{
        Base                  = $base
        TaskBar               = Join-Path $base 'TaskBar'
        ImplicitAppShortcuts  = Join-Path $base 'ImplicitAppShortcuts'
    }
}

function Resolve-Lnk {
    param([string] $LnkPath)
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $sc  = $wsh.CreateShortcut($LnkPath)
        [pscustomobject]@{
            Name         = [IO.Path]::GetFileNameWithoutExtension($LnkPath)
            LnkPath      = $LnkPath
            TargetPath   = $sc.TargetPath
            IsUWP        = ($sc.TargetPath -like 'shell:Appsfolder*')
        }
    } catch {
        [pscustomobject]@{
            Name         = [IO.Path]::GetFileNameWithoutExtension($LnkPath)
            TargetPath   = $null
            IsUWP        = $false
        }
    }
}

function Export-TaskbarPins {
    param([string] $OutZip)

    Write-Host "Starting export process..." -ForegroundColor Cyan
    $folders = Get-PinFolders
    $temp    = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("PinsExport_" + [guid]::NewGuid())) -Force
    $copyRoot = New-Item -ItemType Directory -Path (Join-Path $temp.FullName 'UserPinned') -Force

    # 1. Copy the physical .lnk files
    foreach ($p in @($folders.TaskBar, $folders.ImplicitAppShortcuts)) {
        if (Test-Path $p) {
            Copy-Item -Path $p -Destination $copyRoot -Recurse -Force | Out-Null
        }
    }

    # 2. Build a manifest of all .lnk files
    $lnks = Get-ChildItem -Path $copyRoot -Filter *.lnk -Recurse -Force -ErrorAction SilentlyContinue
    $manifest = foreach ($lnk in $lnks) { Resolve-Lnk -LnkPath $lnk.FullName }
    $manifestPath = Join-Path $temp.FullName 'manifest.json'
    $manifest | ConvertTo-Json -Depth 4 | Out-File -Encoding UTF8 -FilePath $manifestPath

    # 3. Export the Taskband Registry Key (Crucial for Win 11)
    $regPath = Join-Path $temp.FullName 'taskband.reg'
    $regKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
    & reg.exe export $regKey $regPath /y | Out-Null

    # 4. Create the zip
    if (Test-Path $OutZip) { Remove-Item $OutZip -Force }
    Compress-Archive -Path (Join-Path $temp.FullName '*') -DestinationPath $OutZip -Force

    # Cleanup temp folder
    Remove-Item -Path $temp.FullName -Recurse -Force

    Write-Host "Successfully exported $(($lnks | Measure-Object).Count) taskbar shortcut(s) and registry data." -ForegroundColor Green
    Write-Host "Zip saved to: $OutZip"
}

function Import-TaskbarPins {
    param([string] $Zip)

    if (-not (Test-Path $Zip)) { throw "Zip file not found: $Zip" }

    Write-Host "Starting import process..." -ForegroundColor Cyan
    $folders = Get-PinFolders
    
    $temp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("PinsImport_" + [guid]::NewGuid())) -Force
    Expand-Archive -Path $Zip -DestinationPath $temp.FullName -Force

    $srcUserPinned = Join-Path $temp.FullName 'UserPinned'
    $srcReg = Join-Path $temp.FullName 'taskband.reg'

    if (-not (Test-Path $srcUserPinned) -or -not (Test-Path $srcReg)) {
        Remove-Item -Path $temp.FullName -Recurse -Force
        throw "Zip is missing required files ('UserPinned' or 'taskband.reg'). Ensure it was created with this updated script."
    }

    # 1. Stop Explorer to release file locks and prevent auto-overwriting of the registry
    Write-Host "Stopping Windows Explorer..."
    $explorers = Get-Process explorer -ErrorAction SilentlyContinue
    if ($explorers) { $explorers | Stop-Process -Force }
    Start-Sleep -Seconds 2

    # 2. Replace pinned shortcut folders
    Write-Host "Restoring shortcut files..."
    foreach ($name in @('TaskBar','ImplicitAppShortcuts')) {
        $dst = $folders.$name
        $srcSub = Join-Path $srcUserPinned $name
        
        if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }

        if (Test-Path $srcSub) {
            # Clean destination then copy
            Get-ChildItem $dst -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item -Path "$srcSub\*" -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 3. Import the Registry Key
    Write-Host "Restoring Taskband registry keys..."
    & reg.exe import $srcReg | Out-Null

    # 4. Start Explorer again
    Write-Host "Restarting Windows Explorer..."
    Start-Process explorer.exe | Out-Null
    Start-Sleep -Seconds 2

    # Cleanup temp folder
    Remove-Item -Path $temp.FullName -Recurse -Force

    $lnkCount = (Get-ChildItem -Path $folders.TaskBar -Filter *.lnk -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "Successfully restored $lnkCount taskbar shortcut(s)!" -ForegroundColor Green
}

# ---- main ----
switch ($PSCmdlet.ParameterSetName) {
    'Export' { Export-TaskbarPins -OutZip $OutPath }
    'Import' { Import-TaskbarPins -Zip $ZipPath }
    default  { Write-Error "Use -Export or -Import. Run Get-Help .\TaskbarPins.ps1 -Full for details." }
}