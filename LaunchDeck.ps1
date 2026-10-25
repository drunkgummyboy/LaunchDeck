<#
    LaunchDeck v2 - set up a Windows PC: pick apps, install them with winget,
    and run helper scripts from github.com/drunkgummyboy/LaunchDeck.

    Run:   irm https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/LaunchDeck.ps1 | iex
    Test:  powershell.exe -NoProfile -File LaunchDeck.ps1 -Practice
#>
param([switch]$Practice)

# Every function is named Verb-LdNoun so the background workers can import them all.

# ============================================================================
#  Data helpers (no side effects)
# ============================================================================

function Get-LdRawUrl {
    param([Parameter(Mandatory)][string]$Path)
    $segments = $Path.Trim('/') -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }
    'https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/' + ($segments -join '/')
}

function Get-LdIconUrl {
    param([string]$Icon)
    if ([string]::IsNullOrWhiteSpace($Icon)) { return $null }
    $Icon = $Icon.Trim()
    if ($Icon -match '^https?://') { return $Icon }
    if ($Icon -match '/' -or $Icon -match '\.(ico|png)$') { return Get-LdRawUrl -Path "scripts/$Icon" }
    "https://www.google.com/s2/favicons?domain=$([uri]::EscapeDataString($Icon))&sz=64"
}

# Reads apps.json. Accepts the v2 object format and the v1 bare array (Name/Id/Domain).
function ConvertTo-LdCatalog {
    param([Parameter(Mandatory)][string]$Json)
    $data = ConvertFrom-Json -InputObject $Json
    $isV2 = ($data -isnot [array]) -and ($null -ne $data.PSObject.Properties['apps'])
    $rawApps = if ($isV2) { @($data.apps) } else { @($data) }
    $declared = if ($isV2 -and $data.categories) { @($data.categories | ForEach-Object { ([string]$_).Trim() }) } else { @() }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $apps = foreach ($a in $rawApps) {
        $id = ([string]$a.id).Trim()
        if (-not $id -or -not $seen.Add($id)) { continue }
        $category = $declared | Where-Object { $_ -eq ([string]$a.category).Trim() } | Select-Object -First 1
        if (-not $category) { $category = 'Other' }
        $name = ([string]$a.name).Trim()
        [pscustomobject]@{
            Name     = if ($name) { $name } else { $id }
            Id       = $id
            Category = $category
            Icon     = if ($a.icon) { [string]$a.icon } else { [string]$a.domain }
            Source   = if ($a.source) { ([string]$a.source).Trim() } else { '' }
        }
    }

    $used = @($apps | ForEach-Object Category | Select-Object -Unique)
    $categories = @($declared | Where-Object { $used -contains $_ })
    if ($used -contains 'Other' -and $categories -notcontains 'Other') { $categories += 'Other' }

    $presets = @()
    if ($isV2 -and $data.presets) {
        $presets = foreach ($p in @($data.presets)) {
            $pName = ([string]$p.name).Trim()
            if (-not $pName) { continue }
            $all = ($p.apps -is [string]) -and ($p.apps -eq '*')
            [pscustomobject]@{
                Name = $pName
                All  = [bool]$all
                Ids  = if ($all) { @() } else { @($p.apps | ForEach-Object { ([string]$_).Trim() }) }
            }
        }
    }

    [pscustomobject]@{ Categories = [string[]]$categories; Presets = @($presets); Apps = @($apps) }
}

# Returns the catalog's own (exact-case) ids for a preset. "Everything" and "None" are built in.
function Resolve-LdPreset {
    param([Parameter(Mandatory)]$Catalog, [Parameter(Mandatory)][string]$Name)
    $allIds = @($Catalog.Apps | ForEach-Object Id)
    if ($Name -eq 'Everything') { return $allIds }
    if ($Name -eq 'None') { return @() }
    $preset = @($Catalog.Presets) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $preset) { return @() }
    if ($preset.All) { return $allIds }
    $wanted = @($preset.Ids)
    @($allIds | Where-Object { $wanted -contains $_ })
}

function New-LdToolEntry {
    param([Parameter(Mandatory)][string]$File, [string]$Name, [string]$Description, [string]$Icon)
    [pscustomobject]@{
        Name        = if ($Name) { $Name.Trim() } else { [IO.Path]::GetFileNameWithoutExtension($File) }
        File        = $File
        Description = if ($Description) { $Description.Trim() } else { "Run $File" }
        Icon        = $Icon
        Url         = Get-LdRawUrl -Path "scripts/$File"
    }
}

# Merges tools.json with the GitHub listing of scripts/. A $null listing means "listing unavailable".
function ConvertTo-LdToolList {
    param([string]$ToolsJson, [object[]]$Listing)
    $defined = @()
    if (-not [string]::IsNullOrWhiteSpace($ToolsJson)) {
        try { $parsed = ConvertFrom-Json -InputObject $ToolsJson; $defined = @($parsed) } catch { $defined = @() }
    }
    $listed = $null
    if ($null -ne $Listing) {
        $listed = @($Listing | Where-Object { $_.type -eq 'file' -and $_.name -like '*.ps1' } | ForEach-Object { [string]$_.name })
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($t in $defined) {
        $file = ([string]$t.file).Trim()
        if (-not $file -or -not $seen.Add($file)) { continue }
        if ($null -ne $listed -and $listed -notcontains $file) { continue }
        New-LdToolEntry -File $file -Name $t.name -Description $t.description -Icon $t.icon
    }
    if ($null -ne $listed) {
        foreach ($f in ($listed | Sort-Object)) {
            if ($seen.Add($f)) { New-LdToolEntry -File $f }
        }
    }
}

# Package ids from `winget export` JSON, as a case-insensitive set.
function ConvertFrom-LdWingetExport {
    param([string]$Json)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if (-not [string]::IsNullOrWhiteSpace($Json)) {
        try {
            $data = ConvertFrom-Json -InputObject $Json
            foreach ($source in @($data.Sources)) {
                foreach ($package in @($source.Packages)) {
                    if ($package.PackageIdentifier) { [void]$set.Add([string]$package.PackageIdentifier) }
                }
            }
        } catch { }
    }
    , $set
}

# Codes from winget's returnCodes.md.
function Get-LdInstallResult {
    param([Parameter(Mandatory)][int]$ExitCode)
    $status, $note = switch ($ExitCode) {
        0             { 'Installed', '' }
        (-1978334967) { 'Installed', 'Restart needed to finish' }        # 0x8A150109 reboot required to finish
        (-1978334965) { 'Installed', 'Restart needed to finish' }        # 0x8A15010B reboot initiated
        (-1978335135) { 'AlreadyInstalled', '' }                         # 0x8A150061 package already installed
        (-1978334963) { 'AlreadyInstalled', '' }                         # 0x8A15010D another version installed
        (-1978335189) { 'AlreadyInstalled', '' }                         # 0x8A15002B no applicable update
        (-1978334966) { 'Failed', 'Restart the PC, then retry' }         # 0x8A15010A reboot required for install
        (-1978335212) { 'Failed', 'Not found in winget' }                # 0x8A150014 no packages found
        (-1978334969) { 'Failed', 'No internet connection' }             # 0x8A150107 no network
        default       { 'Failed', ('winget error 0x{0:X8}' -f $ExitCode) }
    }
    @{ Status = $status; Note = $note }
}

# $Results: id -> @{ Name; Status }. Returns names grouped by outcome.
function Get-LdSummary {
    param([Parameter(Mandatory)][hashtable]$Results)
    $items = @($Results.Values | Sort-Object { $_.Name })
    @{
        Installed = @($items | Where-Object { $_.Status -eq 'Installed' } | ForEach-Object { $_.Name })
        Already   = @($items | Where-Object { $_.Status -eq 'AlreadyInstalled' } | ForEach-Object { $_.Name })
        Failed    = @($items | Where-Object { $_.Status -eq 'Failed' } | ForEach-Object { $_.Name })
    }
}

# ============================================================================
#  Startup, logging, downloads
# ============================================================================

# Run       - open the window in this process
# RelaunchFile / ElevateFile - start this file again in Windows PowerShell (elevated for ElevateFile)
# DownloadThenElevate - no file to relaunch (irm | iex), so save a copy first
function Get-LdLaunchPlan {
    param([bool]$IsAdmin, [string]$SelfPath, [string]$Edition, [bool]$Practice)
    $isDesktop = $Edition -eq 'Desktop'
    if ($isDesktop -and ($Practice -or $IsAdmin)) { return 'Run' }
    if (-not $SelfPath) { return 'DownloadThenElevate' }
    if ($Practice) { return 'RelaunchFile' }
    'ElevateFile'
}

function Test-LdAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LdDataDir {
    param([string]$Child = '')
    $dir = Join-Path $env:LOCALAPPDATA 'LaunchDeck'
    if ($Child) { $dir = Join-Path $dir $Child }
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dir
}

function New-LdLogFile {
    $name = 'LaunchDeck_{0:yyyyMMdd_HHmmss}.log' -f (Get-Date)
    foreach ($dir in @((Join-Path $env:ProgramData 'LaunchDeck\logs'), (Join-Path $env:TEMP 'LaunchDeck'))) {
        try {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $path = Join-Path $dir $name
            [IO.File]::AppendAllText($path, '')
            return $path
        } catch { }
    }
    $null
}

# Shared state between the window and the background workers.
function Initialize-LdSync {
    param([string]$LogFile)
    $script:LdSync = [hashtable]::Synchronized(@{
        Events           = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        Pending          = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        StopAfterCurrent = $false
        LogLock          = New-Object object
        LogFile          = $LogFile
    })
}

function Write-LdLog {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message)
    if (-not $LdSync -or -not $LdSync.LogFile) { return }
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    [Threading.Monitor]::Enter($LdSync.LogLock)
    try { [IO.File]::AppendAllText($LdSync.LogFile, $line + [Environment]::NewLine) } catch { }
    finally { [Threading.Monitor]::Exit($LdSync.LogLock) }
}

function Show-LdError {
    param([Parameter(Mandatory)][string]$Message)
    Write-LdLog "ERROR: $Message"
    try {
        Add-Type -AssemblyName PresentationFramework
        [void][System.Windows.MessageBox]::Show($Message, 'LaunchDeck', 'OK', 'Error')
    } catch { Write-Host $Message -ForegroundColor Red }
}

# Text from a local file (when it exists) or a URL; $null on any failure.
function Get-LdText {
    param([Parameter(Mandatory)][string]$Url, [string]$LocalPath)
    if ($LocalPath -and (Test-Path -LiteralPath $LocalPath)) { return [IO.File]::ReadAllText($LocalPath) }
    $ProgressPreference = 'SilentlyContinue'
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10 -Headers @{ 'User-Agent' = 'LaunchDeck' }
        [Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray()).TrimStart([char]0xFEFF)
    } catch { $null }
}

function Save-LdFile {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Path)
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -TimeoutSec 10 -Headers @{ 'User-Agent' = 'LaunchDeck' }
        $true
    } catch {
        Remove-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        $false
    }
}

# For irm | iex: there is no file to relaunch, so save the latest LaunchDeck.ps1 locally.
function Save-LdSelfCopy {
    $text = Get-LdText -Url (Get-LdRawUrl -Path 'LaunchDeck.ps1')
    if (-not $text) {
        Show-LdError "LaunchDeck couldn't be downloaded from GitHub.`n`nCheck the internet connection and try again."
        return $null
    }
    $path = Join-Path (Get-LdDataDir) 'LaunchDeck.ps1'
    # With a BOM, so Windows PowerShell reads the file as UTF-8.
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $true))
    $path
}

function Start-LdSelf {
    param([Parameter(Mandatory)][string]$Path, [switch]$Practice, [switch]$Elevate)
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$Path`"")
    if ($Practice) { $argList += '-Practice' }
    $params = @{ FilePath = 'powershell.exe'; ArgumentList = $argList; WindowStyle = 'Hidden' }
    if ($Elevate) { $params.Verb = 'RunAs' }
    try { Start-Process @params | Out-Null }
    catch {
        if ($Elevate) { Show-LdError "LaunchDeck needs admin rights to install apps.`n`nStart it again and click Yes when Windows asks." }
        else { Show-LdError "LaunchDeck couldn't restart itself.`n`n$($_.Exception.Message)" }
    }
}

function Start-LaunchDeck {
    param([switch]$Practice, [string]$SelfPath)
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    try {
        $plan = Get-LdLaunchPlan -IsAdmin (Test-LdAdmin) -SelfPath $SelfPath -Edition $PSVersionTable.PSEdition -Practice $Practice.IsPresent
        switch ($plan) {
            'Run'                 { Show-LdWindow -Practice:$Practice -SelfPath $SelfPath }
            'RelaunchFile'        { Start-LdSelf -Path $SelfPath -Practice:$Practice }
            'ElevateFile'         { Start-LdSelf -Path $SelfPath -Practice:$Practice -Elevate }
            'DownloadThenElevate' {
                $copy = Save-LdSelfCopy
                if ($copy) { Start-LdSelf -Path $copy -Practice:$Practice -Elevate }
            }
        }
    } catch {
        Show-LdError "LaunchDeck stopped because of an unexpected error:`n`n$($_.Exception.Message)"
    }
}

# Dot-sourcing (the tests do this) loads the functions without opening the window.
if ($MyInvocation.InvocationName -eq '.') { return }

Start-LaunchDeck -Practice:$Practice -SelfPath $PSCommandPath
