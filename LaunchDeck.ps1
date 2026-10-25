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

# ============================================================================
#  Background workers (a runspace pool; workers talk to the window via events)
# ============================================================================

function Send-LdEvent {
    param([Parameter(Mandatory)][string]$Type, $Data)
    $LdSync.Events.Enqueue([pscustomobject]@{ Type = $Type; Data = $Data })
}

function New-LdWorkerPool {
    $iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($f in Get-ChildItem -Path function: | Where-Object { $_.Name -like '*-Ld*' }) {
        $iss.Commands.Add((New-Object Management.Automation.Runspaces.SessionStateFunctionEntry($f.Name, $f.Definition)))
    }
    $iss.Variables.Add((New-Object Management.Automation.Runspaces.SessionStateVariableEntry('LdSync', $LdSync, 'Shared LaunchDeck state')))
    $pool = [runspacefactory]::CreateRunspacePool(1, 4, $iss, $Host)
    $pool.ApartmentState = 'STA'
    $pool.Open()
    $script:LdPool = $pool
    $script:LdWorkers = New-Object Collections.ArrayList
}

function Start-LdWorker {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock, [object[]]$ArgumentList = @())
    $ps = [powershell]::Create()
    $ps.RunspacePool = $script:LdPool
    [void]$ps.AddScript($ScriptBlock.ToString())
    foreach ($arg in $ArgumentList) { [void]$ps.AddArgument($arg) }
    [void]$script:LdWorkers.Add([pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke() })
}

function Complete-LdWorkers {
    foreach ($w in @($script:LdWorkers)) {
        if (-not $w.Handle.IsCompleted) { continue }
        try { [void]$w.PowerShell.EndInvoke($w.Handle) } catch { Write-LdLog "Worker failed: $($_.Exception.Message)" }
        foreach ($err in $w.PowerShell.Streams.Error) { Write-LdLog "Worker error: $err" }
        $w.PowerShell.Dispose()
        $script:LdWorkers.Remove($w)
    }
}

function Stop-LdBackground {
    if ($script:Ui -and $script:Ui.Timer) { $script:Ui.Timer.Stop() }
    foreach ($w in @($script:LdWorkers)) {
        try { $w.PowerShell.Stop() } catch { }
        $w.PowerShell.Dispose()
    }
    if ($script:LdPool) { $script:LdPool.Close(); $script:LdPool.Dispose(); $script:LdPool = $null }
}

# Is winget there, which version, and which packages are installed (one `winget export`).
function Get-LdWingetState {
    $state = @{ Present = $false; Version = ''; Installed = (ConvertFrom-LdWingetExport -Json '') }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { return $state }
    $state.Present = $true
    $state.Version = ((& winget.exe --version 2>$null) | Out-String).Trim()
    $tmp = Join-Path $env:TEMP ('LaunchDeck-export-{0}.json' -f [guid]::NewGuid())
    try {
        & winget.exe export -o $tmp --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
        if (Test-Path -LiteralPath $tmp) { $state.Installed = ConvertFrom-LdWingetExport -Json ([IO.File]::ReadAllText($tmp)) }
    } catch {
        Write-LdLog "winget export failed: $($_.Exception.Message)"
    } finally {
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    }
    $state
}

$script:LdLoadWorker = {
    param($LocalDir)
    try {
        $appsLocal = if ($LocalDir) { Join-Path $LocalDir 'apps.json' } else { '' }
        $toolsLocal = if ($LocalDir) { Join-Path $LocalDir 'tools.json' } else { '' }
        $appsText = Get-LdText -Url (Get-LdRawUrl -Path 'apps.json') -LocalPath $appsLocal
        if (-not $appsText) {
            Send-LdEvent -Type 'LoadFailed' -Data "The app list couldn't be downloaded from GitHub.`n`nCheck the internet connection and start LaunchDeck again."
            return
        }
        $catalog = ConvertTo-LdCatalog -Json $appsText
        $toolsText = Get-LdText -Url (Get-LdRawUrl -Path 'tools.json') -LocalPath $toolsLocal
        $listing = $null
        $listingText = Get-LdText -Url 'https://api.github.com/repos/drunkgummyboy/LaunchDeck/contents/scripts?ref=main'
        if ($listingText) { try { $parsed = ConvertFrom-Json -InputObject $listingText; $listing = @($parsed) } catch { } }
        $tools = @(ConvertTo-LdToolList -ToolsJson $toolsText -Listing $listing)
        Write-LdLog "Loaded $(@($catalog.Apps).Count) apps and $($tools.Count) tools"
        Send-LdEvent -Type 'Catalog' -Data @{ Catalog = $catalog; Tools = $tools }
        $state = Get-LdWingetState
        Write-LdLog "winget present: $($state.Present) $($state.Version); installed packages: $($state.Installed.Count)"
        Send-LdEvent -Type 'Winget' -Data $state
    } catch {
        Send-LdEvent -Type 'LoadFailed' -Data "The app list couldn't be read.`n`n$($_.Exception.Message)"
    }
}

$script:LdIconWorker = {
    param([string[]]$Icons)
    $dir = Get-LdDataDir -Child 'icons'
    foreach ($icon in $Icons) {
        $url = Get-LdIconUrl -Icon $icon
        if (-not $url) { continue }
        $file = Join-Path $dir (($icon -replace '[^A-Za-z0-9._-]', '_') + '.img')
        $ok = (Test-Path -LiteralPath $file) -and (Test-LdImageFile -Path $file)
        if (-not $ok) { $ok = (Save-LdFile -Url $url -Path $file) -and (Test-LdImageFile -Path $file) }
        if ($ok) { Send-LdEvent -Type 'Icon' -Data @{ Icon = $icon; Path = $file } }
    }
}

$script:LdToolWorker = {
    param($Tool)
    $path = Join-Path (Get-LdDataDir -Child 'scripts') $Tool.File
    if (Save-LdFile -Url $Tool.Url -Path $path) { Send-LdEvent -Type 'ToolReady' -Data @{ Name = $Tool.Name; Path = $path } }
    else { Send-LdEvent -Type 'ToolFailed' -Data "$($Tool.Name) couldn't be downloaded from GitHub.`n`nCheck the internet connection and try again." }
}

# ============================================================================
#  Window helpers
# ============================================================================

function Get-LdVisibleIds {
    param([Parameter(Mandatory)]$Catalog, [string]$Category = 'All', [string]$Search = '')
    $text = "$Search".Trim()
    $apps = @($Catalog.Apps)
    if ($text) { $apps = $apps | Where-Object { $_.Name.IndexOf($text, [StringComparison]::OrdinalIgnoreCase) -ge 0 } }
    elseif ($Category -and $Category -ne 'All') { $apps = $apps | Where-Object { $_.Category -eq $Category } }
    @($apps | ForEach-Object Id)
}

# A downloaded icon is only kept when WPF can decode it.
function Test-LdImageFile {
    param([Parameter(Mandatory)][string]$Path)
    $ok = $false
    try { $ok = $null -ne (New-LdBitmap -Path $Path) } catch { }
    if (-not $ok) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
    $ok
}

# The largest frame, so .ico files with several sizes stay sharp. Reads through our own
# stream: a failed decode from a Uri keeps the file locked until garbage collection.
function New-LdBitmap {
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName PresentationCore
    $stream = [IO.File]::OpenRead($Path)
    try {
        $decoder = [Windows.Media.Imaging.BitmapDecoder]::Create($stream, 'None', 'OnLoad')
        $frame = $decoder.Frames | Sort-Object { $_.PixelWidth } -Descending | Select-Object -First 1
        if ($frame -and $frame.PixelWidth -gt 0) { $frame.Freeze(); $frame }
    } finally { $stream.Dispose() }
}

function Get-LdThemeIsDark {
    try { (Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop) -eq 0 }
    catch { $false }
}

function Get-LdPalette {
    param([bool]$Dark)
    if ($Dark) {
        @{ Bg = '#202020'; Panel = '#1C1C1C'; Surface = '#2B2B2B'; Line = '#3A3A3A'; Hover = '#2F2F2F'; Input = '#2B2B2B'
           Text = '#F3F3F3'; SubText = '#9A9A9A'; Accent = '#4CC2FF'; AccentText = '#00273A'; CardSel = '#1D3442'
           Good = '#6CCB5F'; GoodBg = '#2C4A2C'; GoodText = '#A6E3A6'; Bad = '#FF8A80'; Warn = '#FCE100' }
    } else {
        @{ Bg = '#F3F3F3'; Panel = '#EBEBEB'; Surface = '#FFFFFF'; Line = '#D5D5D5'; Hover = '#E3E3E3'; Input = '#FFFFFF'
           Text = '#1B1B1B'; SubText = '#5F5F5F'; Accent = '#0067C0'; AccentText = '#FFFFFF'; CardSel = '#DCEBFA'
           Good = '#0F7B0F'; GoodBg = '#DFF6DD'; GoodText = '#0E700E'; Bad = '#C42B1C'; Warn = '#9D5D00' }
    }
}

function Set-LdDarkTitleBar {
    param($Window)
    try {
        if (-not ('LaunchDeckNative.Dwm' -as [type])) {
            Add-Type -Namespace 'LaunchDeckNative' -Name 'Dwm' -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);'
        }
        $hwnd = (New-Object Windows.Interop.WindowInteropHelper $Window).Handle
        $on = 1
        [void][LaunchDeckNative.Dwm]::DwmSetWindowAttribute($hwnd, 20, [ref]$on, 4)   # DWMWA_USE_IMMERSIVE_DARK_MODE
    } catch { }
}

function Get-LdBrush {
    param([Parameter(Mandatory)][string]$Key)
    $script:Ui.Window.Resources[$Key]
}

function Get-LdXaml {
    @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="LaunchDeck" Width="1080" Height="700" MinWidth="860" MinHeight="540"
        WindowStartupLocation="CenterScreen" Background="{{Bg}}" Foreground="{{Text}}"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Bg" Color="{{Bg}}"/>
    <SolidColorBrush x:Key="Panel" Color="{{Panel}}"/>
    <SolidColorBrush x:Key="Surface" Color="{{Surface}}"/>
    <SolidColorBrush x:Key="Line" Color="{{Line}}"/>
    <SolidColorBrush x:Key="Hover" Color="{{Hover}}"/>
    <SolidColorBrush x:Key="Input" Color="{{Input}}"/>
    <SolidColorBrush x:Key="Text" Color="{{Text}}"/>
    <SolidColorBrush x:Key="SubText" Color="{{SubText}}"/>
    <SolidColorBrush x:Key="Accent" Color="{{Accent}}"/>
    <SolidColorBrush x:Key="AccentText" Color="{{AccentText}}"/>
    <SolidColorBrush x:Key="CardSel" Color="{{CardSel}}"/>
    <SolidColorBrush x:Key="Good" Color="{{Good}}"/>
    <SolidColorBrush x:Key="GoodBg" Color="{{GoodBg}}"/>
    <SolidColorBrush x:Key="GoodText" Color="{{GoodText}}"/>
    <SolidColorBrush x:Key="Bad" Color="{{Bad}}"/>
    <SolidColorBrush x:Key="Warn" Color="{{Warn}}"/>

    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/>
      <Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Border CornerRadius="3" Background="{StaticResource Line}" Margin="2,2,2,2"/>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Background" Value="{StaticResource Surface}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" CornerRadius="6" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource SubText}"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="AccentBtn" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
      <Setter Property="Foreground" Value="{StaticResource AccentText}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="16,7"/>
    </Style>
    <Style x:Key="SmallBtn" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Padding" Value="9,3"/>
      <Setter Property="FontSize" Value="11.5"/>
    </Style>
    <Style x:Key="Chip" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Background" Value="{StaticResource Surface}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" CornerRadius="13" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="12,4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource SubText}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Tool" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Padding" Value="9,8"/>
      <Setter Property="Margin" Value="0,0,0,6"/>
    </Style>
    <Style x:Key="Card" TargetType="ToggleButton">
      <Setter Property="Width" Value="108"/>
      <Setter Property="Height" Value="104"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Grid>
              <Border x:Name="Bd" CornerRadius="8" Background="{StaticResource Surface}" BorderBrush="{StaticResource Line}" BorderThickness="1">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="4"/>
              </Border>
              <TextBlock x:Name="Tick" Text="&#x2713;" FontWeight="Bold" FontSize="12" Foreground="{StaticResource Accent}"
                         HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,5,8,0" Visibility="Collapsed"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource SubText}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource CardSel}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter TargetName="Tick" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.6"/>
                <Setter Property="Cursor" Value="Arrow"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Nav" TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" CornerRadius="6" Padding="12,7" Margin="0,0,0,2" Background="Transparent">
              <Grid>
                <Border x:Name="Bar" Width="3" CornerRadius="1.5" HorizontalAlignment="Left" Margin="-12,2,0,2" Background="{StaticResource Accent}" Visibility="Collapsed"/>
                <ContentPresenter HorizontalAlignment="Stretch"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{StaticResource Hover}"/></Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Hover}"/>
                <Setter TargetName="Bar" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid x:Name="Root" Background="{StaticResource Bg}">
    <Grid x:Name="MainView">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <DockPanel Grid.Row="0" Margin="16,14,16,12">
        <StackPanel x:Name="PresetPanel" DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center" Margin="14,0,0,0">
          <TextBlock Text="Presets:" Foreground="{StaticResource SubText}" VerticalAlignment="Center" Margin="0,0,8,0"/>
        </StackPanel>
        <Border x:Name="SearchBorder" Background="{StaticResource Input}" BorderBrush="{StaticResource Line}" BorderThickness="1,1,1,2" CornerRadius="6" Height="34">
          <Grid Margin="10,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" Foreground="{StaticResource SubText}" VerticalAlignment="Center" Margin="0,0,8,0"/>
            <TextBlock x:Name="SearchHint" Grid.Column="1" Text="Search apps..." Foreground="{StaticResource SubText}" VerticalAlignment="Center" IsHitTestVisible="False" Margin="2,0,0,0"/>
            <TextBox x:Name="SearchBox" Grid.Column="1" Background="Transparent" BorderThickness="0" Foreground="{StaticResource Text}"
                     CaretBrush="{StaticResource Text}" VerticalContentAlignment="Center"/>
          </Grid>
        </Border>
      </DockPanel>

      <Grid Grid.Row="1">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="180"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="240"/>
        </Grid.ColumnDefinitions>
        <Border Grid.Column="0" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="0,1,1,0" Padding="8,10">
          <ListBox x:Name="CategoryList" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Nav}"
                   ScrollViewer.HorizontalScrollBarVisibility="Disabled" HorizontalContentAlignment="Stretch"/>
        </Border>
        <Grid Grid.Column="1" Margin="16,10,6,0">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <DockPanel Grid.Row="0" Margin="0,0,10,6">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
              <Button x:Name="SelectAllButton" Content="Select all" Style="{StaticResource SmallBtn}" Margin="0,0,6,0"/>
              <Button x:Name="SelectNoneButton" Content="Select none" Style="{StaticResource SmallBtn}"/>
            </StackPanel>
            <TextBlock x:Name="CounterText" VerticalAlignment="Center" Foreground="{StaticResource SubText}"/>
          </DockPanel>
          <ScrollViewer x:Name="CardScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" FocusVisualStyle="{x:Null}">
            <StackPanel x:Name="CardHost" Margin="0,0,6,12"/>
          </ScrollViewer>
          <TextBlock x:Name="LoadingText" Grid.Row="1" Text="Loading apps..." Foreground="{StaticResource SubText}" FontSize="14"
                     HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/>
        </Grid>
        <Border Grid.Column="2" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="1,1,0,0" Padding="12">
          <DockPanel>
            <TextBlock DockPanel.Dock="Top" Text="TOOLS FROM GITHUB" FontSize="11" Foreground="{StaticResource SubText}" Margin="2,0,0,8"/>
            <TextBlock x:Name="ToolStatus" DockPanel.Dock="Bottom" Foreground="{StaticResource SubText}" FontSize="11" TextWrapping="Wrap" Margin="2,6,0,0"/>
            <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
              <StackPanel x:Name="ToolHost"/>
            </ScrollViewer>
          </DockPanel>
        </Border>
      </Grid>

      <Border Grid.Row="2" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0" Padding="16,10">
        <DockPanel>
          <Button x:Name="ShortcutButton" DockPanel.Dock="Left" Style="{StaticResource Btn}" Content="Add to desktop"/>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
            <Button x:Name="CloseButton" Content="Close" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
            <Button x:Name="InstallButton" Content="Install" Style="{StaticResource AccentBtn}" IsEnabled="False"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="14,0,0,0">
            <Ellipse x:Name="WingetDot" Width="9" Height="9" Fill="{StaticResource SubText}" Margin="0,0,8,0"/>
            <TextBlock x:Name="WingetText" Text="Checking winget..." Foreground="{StaticResource SubText}"/>
          </StackPanel>
        </DockPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@
}

function New-LdText {
    param([string]$Text, [double]$Size = 13, [string]$Brush = 'Text', [string]$Weight = 'Normal')
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text
    $t.FontSize = $Size
    $t.Foreground = Get-LdBrush $Brush
    $t.FontWeight = $Weight
    $t
}

# Icon slot: a letter (or glyph) placeholder until the real icon arrives.
function New-LdIconSlot {
    param([string]$Icon, [string]$Letter, [double]$Size, [switch]$Glyph)
    $grid = New-Object Windows.Controls.Grid
    $grid.Width = $Size; $grid.Height = $Size
    $placeholder = New-Object Windows.Controls.Border
    $placeholder.CornerRadius = 5
    $placeholder.Background = Get-LdBrush 'Hover'
    $label = New-LdText -Text $Letter -Size ($Size * 0.5) -Brush 'SubText' -Weight 'SemiBold'
    if ($Glyph) { $label.FontFamily = 'Segoe MDL2 Assets'; $label.FontWeight = 'Normal' }
    $label.HorizontalAlignment = 'Center'; $label.VerticalAlignment = 'Center'
    $placeholder.Child = $label
    $image = New-Object Windows.Controls.Image
    $image.Width = $Size; $image.Height = $Size
    [Windows.Media.RenderOptions]::SetBitmapScalingMode($image, 'HighQuality')
    [void]$grid.Children.Add($placeholder)
    [void]$grid.Children.Add($image)
    if ($Icon) {
        if (-not $script:Ui.IconTargets.ContainsKey($Icon)) { $script:Ui.IconTargets[$Icon] = New-Object Collections.ArrayList }
        [void]$script:Ui.IconTargets[$Icon].Add(@{ Image = $image; Placeholder = $placeholder })
    }
    $grid
}

function New-LdCard {
    param([Parameter(Mandatory)]$App)
    $button = New-Object Windows.Controls.Primitives.ToggleButton
    $button.Style = $script:Ui.Window.Resources['Card']
    $button.Tag = $App.Id
    $button.ToolTip = $App.Id

    $stack = New-Object Windows.Controls.StackPanel
    $slot = New-LdIconSlot -Icon $App.Icon -Letter $App.Name.Substring(0, 1).ToUpper() -Size 28
    $slot.Margin = New-Object Windows.Thickness(0, 2, 0, 6)
    [void]$stack.Children.Add($slot)
    $name = New-LdText -Text $App.Name -Size 12
    $name.TextAlignment = 'Center'; $name.TextWrapping = 'Wrap'; $name.MaxWidth = 96
    [void]$stack.Children.Add($name)
    $badge = New-Object Windows.Controls.Border
    $badge.CornerRadius = 8
    $badge.Background = Get-LdBrush 'GoodBg'
    $badge.Padding = New-Object Windows.Thickness(7, 1, 7, 1)
    $badge.Margin = New-Object Windows.Thickness(0, 4, 0, 0)
    $badge.HorizontalAlignment = 'Center'
    $badge.Visibility = 'Collapsed'
    $badge.Child = New-LdText -Text 'Installed' -Size 10 -Brush 'GoodText'
    [void]$stack.Children.Add($badge)
    $button.Content = $stack

    $button.Add_Click({ $script:Ui.ActivePreset = $null; Update-LdPresetChips })
    $button.Add_Checked({ if (-not $script:Ui.Muted) { Update-LdCounter } })
    $button.Add_Unchecked({ if (-not $script:Ui.Muted) { Update-LdCounter } })
    @{ App = $App; Button = $button; Badge = $badge }
}

function New-LdNavItem {
    param([string]$Name, [int]$Count)
    $item = New-Object Windows.Controls.ListBoxItem
    $item.Tag = $Name
    $grid = New-Object Windows.Controls.DockPanel
    $countText = New-LdText -Text "$Count" -Size 12 -Brush 'SubText'
    [Windows.Controls.DockPanel]::SetDock($countText, 'Right')
    [void]$grid.Children.Add($countText)
    [void]$grid.Children.Add((New-LdText -Text $Name))
    $item.Content = $grid
    $item
}

function New-LdToolButton {
    param([Parameter(Mandatory)]$Tool)
    $button = New-Object Windows.Controls.Button
    $button.Style = $script:Ui.Window.Resources['Tool']
    $button.Tag = $Tool
    $grid = New-Object Windows.Controls.DockPanel
    $slot = New-LdIconSlot -Icon $Tool.Icon -Letter ([string][char]0xE756) -Size 20 -Glyph
    $slot.VerticalAlignment = 'Top'
    $slot.Margin = New-Object Windows.Thickness(0, 1, 9, 0)
    [void]$grid.Children.Add($slot)
    $text = New-Object Windows.Controls.StackPanel
    [void]$text.Children.Add((New-LdText -Text $Tool.Name -Size 12.5 -Weight 'SemiBold'))
    $description = New-LdText -Text $Tool.Description -Size 11 -Brush 'SubText'
    $description.TextWrapping = 'Wrap'
    [void]$text.Children.Add($description)
    [void]$grid.Children.Add($text)
    $button.Content = $grid
    $button.Add_Click({ param($sender, $e) Start-LdTool -Tool $sender.Tag })
    $button
}

function Start-LdTool {
    param([Parameter(Mandatory)]$Tool)
    $script:Ui.ToolStatus.Text = "Opening $($Tool.Name)..."
    Start-LdWorker -ScriptBlock $script:LdToolWorker -ArgumentList @(, $Tool)
}

function Open-LdTool {
    param($Data)
    $script:Ui.ToolStatus.Text = ''
    Write-LdLog "Opening tool $($Data.Name): $($Data.Path)"
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($Data.Path)`"")
}

function Initialize-LdCatalog {
    param($Data)
    $ui = $script:Ui
    $ui.Catalog = $Data.Catalog
    $apps = @($ui.Catalog.Apps)

    $ui.Muted = $true
    $ui.CategoryList.Items.Clear()
    [void]$ui.CategoryList.Items.Add((New-LdNavItem -Name 'All' -Count $apps.Count))
    foreach ($category in $ui.Catalog.Categories) {
        [void]$ui.CategoryList.Items.Add((New-LdNavItem -Name $category -Count @($apps | Where-Object { $_.Category -eq $category }).Count))
    }
    $ui.CategoryList.SelectedIndex = if (@($ui.Catalog.Categories).Count -gt 0) { 1 } else { 0 }

    $ui.CardHost.Children.Clear()
    $ui.Cards = @{}
    $ui.Sections = [ordered]@{}
    foreach ($category in $ui.Catalog.Categories) {
        $header = New-LdText -Text $category.ToUpper() -Size 11 -Brush 'SubText'
        $header.Margin = New-Object Windows.Thickness(0, 10, 0, 8)
        $panel = New-Object Windows.Controls.WrapPanel
        $ids = @()
        foreach ($app in ($apps | Where-Object { $_.Category -eq $category })) {
            $card = New-LdCard -App $app
            [void]$panel.Children.Add($card.Button)
            $ui.Cards[$app.Id] = $card
            $ids += $app.Id
        }
        [void]$ui.CardHost.Children.Add($header)
        [void]$ui.CardHost.Children.Add($panel)
        $ui.Sections[$category] = @{ Header = $header; Panel = $panel; Ids = $ids }
    }
    $ui.Muted = $false

    while ($ui.PresetPanel.Children.Count -gt 1) { $ui.PresetPanel.Children.RemoveAt(1) }
    $presetNames = @($ui.Catalog.Presets | ForEach-Object Name) + @('Everything', 'None')
    foreach ($name in $presetNames) {
        $chip = New-Object Windows.Controls.Button
        $chip.Style = $ui.Window.Resources['Chip']
        $chip.Content = $name
        $chip.Tag = $name
        $chip.Add_Click({ param($sender, $e) Set-LdPreset -Name $sender.Tag })
        [void]$ui.PresetPanel.Children.Add($chip)
    }

    $ui.ToolHost.Children.Clear()
    foreach ($tool in @($Data.Tools)) { [void]$ui.ToolHost.Children.Add((New-LdToolButton -Tool $tool)) }
    if (@($Data.Tools).Count -eq 0) { $ui.ToolStatus.Text = "No tools found on GitHub." }

    Set-LdPreset -Name $presetNames[0]
    Update-LdView

    $icons = @(@($apps | ForEach-Object Icon) + @($Data.Tools | ForEach-Object Icon) + 'assets/LaunchDeck.ico' |
        Where-Object { $_ } | Select-Object -Unique)
    Start-LdWorker -ScriptBlock $script:LdIconWorker -ArgumentList @(, [string[]]$icons)
}

function Set-LdWingetState {
    param($State)
    $ui = $script:Ui
    $ui.Winget = $State
    $ui.Installed = $State.Installed
    $ui.WingetChecked = $true
    $ui.Muted = $true
    foreach ($card in $ui.Cards.Values) {
        $isInstalled = $ui.Installed.Contains($card.App.Id)
        $card.Badge.Visibility = if ($isInstalled) { 'Visible' } else { 'Collapsed' }
        if ($isInstalled) { $card.Button.IsChecked = $false }
        $card.Button.IsEnabled = -not $isInstalled
    }
    $ui.Muted = $false
    if ($State.Present) {
        $ui.WingetDot.Fill = Get-LdBrush 'Good'
        $ui.WingetText.Text = "Winget ready ($($State.Version))"
    } else {
        $ui.WingetDot.Fill = Get-LdBrush 'Warn'
        $ui.WingetText.Text = 'Winget not found - it will be installed first'
    }
    Update-LdCounter
}

function Set-LdIcon {
    param($Data)
    $ui = $script:Ui
    $bitmap = New-LdBitmap -Path $Data.Path
    if ($Data.Icon -eq 'assets/LaunchDeck.ico') { $ui.Window.Icon = $bitmap }
    if ($ui.IconTargets.ContainsKey($Data.Icon)) {
        foreach ($target in $ui.IconTargets[$Data.Icon]) {
            $target.Image.Source = $bitmap
            $target.Placeholder.Visibility = 'Collapsed'
        }
    }
}

function Set-LdPreset {
    param([Parameter(Mandatory)][string]$Name)
    $ui = $script:Ui
    $wanted = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in (Resolve-LdPreset -Catalog $ui.Catalog -Name $Name)) { [void]$wanted.Add($id) }
    $ui.Muted = $true
    foreach ($card in $ui.Cards.Values) {
        $card.Button.IsChecked = $wanted.Contains($card.App.Id) -and -not $ui.Installed.Contains($card.App.Id)
    }
    $ui.Muted = $false
    $ui.ActivePreset = $Name
    Update-LdPresetChips
    Update-LdCounter
}

function Update-LdPresetChips {
    $ui = $script:Ui
    foreach ($chip in @($ui.PresetPanel.Children | Where-Object { $_ -is [Windows.Controls.Button] })) {
        $active = $chip.Tag -eq $ui.ActivePreset
        $chip.Background = Get-LdBrush $(if ($active) { 'Accent' } else { 'Surface' })
        $chip.BorderBrush = Get-LdBrush $(if ($active) { 'Accent' } else { 'Line' })
        $chip.Foreground = Get-LdBrush $(if ($active) { 'AccentText' } else { 'Text' })
        $chip.FontWeight = if ($active) { 'SemiBold' } else { 'Normal' }
    }
}

# Select all / none: only the cards currently shown, and never installed apps.
function Set-LdVisibleChecked {
    param([bool]$Value)
    $ui = $script:Ui
    $ui.Muted = $true
    foreach ($card in $ui.Cards.Values) {
        if ($card.Button.Visibility -eq 'Visible' -and $card.Button.IsEnabled) { $card.Button.IsChecked = $Value }
    }
    $ui.Muted = $false
    $ui.ActivePreset = $null
    Update-LdPresetChips
    Update-LdCounter
}

function Get-LdSelectedApps {
    @($script:Ui.Catalog.Apps | Where-Object { $script:Ui.Cards[$_.Id].Button.IsChecked })
}

function Update-LdCounter {
    $ui = $script:Ui
    if (-not $ui.Catalog) { return }
    $selected = @(Get-LdSelectedApps).Count
    $dot = [char]0x00B7
    $installedText = if ($ui.WingetChecked) {
        $count = @($ui.Catalog.Apps | Where-Object { $ui.Installed.Contains($_.Id) }).Count
        "$count already installed"
    } else { 'checking which apps are installed...' }
    $ui.CounterText.Text = "$selected of $($ui.Cards.Count) selected  $dot  $installedText"
    $ui.InstallButton.Content = if ($selected -eq 1) { 'Install 1 app' } else { "Install $selected apps" }
    $ui.InstallButton.IsEnabled = ($selected -gt 0) -and $ui.WingetChecked
}

function Update-LdView {
    $ui = $script:Ui
    if (-not $ui.Catalog) { return }
    $category = if ($ui.CategoryList.SelectedItem) { $ui.CategoryList.SelectedItem.Tag } else { 'All' }
    $visible = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in (Get-LdVisibleIds -Catalog $ui.Catalog -Category $category -Search $ui.SearchBox.Text)) { [void]$visible.Add($id) }
    foreach ($card in $ui.Cards.Values) {
        $card.Button.Visibility = if ($visible.Contains($card.App.Id)) { 'Visible' } else { 'Collapsed' }
    }
    foreach ($section in $ui.Sections.Values) {
        $shown = @($section.Ids | Where-Object { $visible.Contains($_) }).Count -gt 0
        $section.Header.Visibility = if ($shown) { 'Visible' } else { 'Collapsed' }
        $section.Panel.Visibility = if ($shown) { 'Visible' } else { 'Collapsed' }
    }
    if ($visible.Count -eq 0) {
        $ui.LoadingText.Text = "No apps match `"$($ui.SearchBox.Text.Trim())`""
        $ui.LoadingText.Visibility = 'Visible'
    } else {
        $ui.LoadingText.Visibility = 'Collapsed'
    }
    $ui.CardScroll.ScrollToTop()
}

# Typing jumps to "All"; clearing the box goes back to the category you were on.
function Update-LdSearch {
    $ui = $script:Ui
    $text = $ui.SearchBox.Text
    $ui.SearchHint.Visibility = if ($text) { 'Collapsed' } else { 'Visible' }
    $ui.Muted = $true
    if ($text.Trim()) {
        if ($null -eq $ui.PrevCategory) { $ui.PrevCategory = $ui.CategoryList.SelectedIndex }
        $ui.CategoryList.SelectedIndex = 0
    } elseif ($null -ne $ui.PrevCategory) {
        $ui.CategoryList.SelectedIndex = $ui.PrevCategory
        $ui.PrevCategory = $null
    }
    $ui.Muted = $false
    Update-LdView
}

function Invoke-LdEvents {
    $evt = $null
    while ($LdSync.Events.TryDequeue([ref]$evt)) {
        try {
            switch ($evt.Type) {
                'Catalog'    { Initialize-LdCatalog -Data $evt.Data }
                'Winget'     { Set-LdWingetState -State $evt.Data }
                'LoadFailed' { Show-LdError -Message $evt.Data; $script:Ui.Window.Close() }
                'Icon'       { Set-LdIcon -Data $evt.Data }
                'ToolReady'  { Open-LdTool -Data $evt.Data }
                'ToolFailed' { $script:Ui.ToolStatus.Text = ''; Show-LdError -Message $evt.Data }
                default      { Write-LdLog "Unknown event: $($evt.Type)" }
            }
        } catch {
            Write-LdLog "Handling '$($evt.Type)' failed: $($_.Exception.Message)"
        }
    }
    Complete-LdWorkers
}

function Start-LdLoad {
    if (-not $script:LdPool) { New-LdWorkerPool }
    Start-LdWorker -ScriptBlock $script:LdLoadWorker -ArgumentList @($script:Ui.LocalDir)
}

# Builds the window and wires it up; Show-LdWindow shows it.
function New-LdWindow {
    param([switch]$Practice, [string]$LocalDir = '', [Nullable[bool]]$Dark = $null)
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    if (-not $LdSync) { Initialize-LdSync -LogFile (New-LdLogFile) }
    if ($null -eq $Dark) { $Dark = Get-LdThemeIsDark }
    $palette = Get-LdPalette -Dark $Dark
    $xaml = Get-LdXaml
    foreach ($key in $palette.Keys) { $xaml = $xaml.Replace("{{$key}}", $palette[$key]) }
    $window = [Windows.Markup.XamlReader]::Parse($xaml)

    $script:Ui = @{
        Window = $window; Practice = [bool]$Practice; LocalDir = $LocalDir; Dark = [bool]$Dark
        Catalog = $null; Cards = @{}; Sections = @{}; IconTargets = @{}
        Installed = (ConvertFrom-LdWingetExport -Json ''); WingetChecked = $false; Winget = $null
        Muted = $false; ActivePreset = $null; PrevCategory = $null
    }
    foreach ($name in 'MainView', 'SearchBorder', 'SearchBox', 'SearchHint', 'PresetPanel', 'CategoryList', 'CounterText',
                      'SelectAllButton', 'SelectNoneButton', 'CardScroll', 'CardHost', 'LoadingText', 'ToolHost', 'ToolStatus',
                      'ShortcutButton', 'WingetDot', 'WingetText', 'CloseButton', 'InstallButton') {
        $script:Ui[$name] = $window.FindName($name)
    }
    if ($Practice) { $window.Title = "LaunchDeck $([char]0x2014) Practice mode" }

    $script:Ui.SearchBox.Add_TextChanged({ Update-LdSearch })
    $script:Ui.SearchBox.Add_GotKeyboardFocus({ $script:Ui.SearchBorder.BorderBrush = Get-LdBrush 'Accent' })
    $script:Ui.SearchBox.Add_LostKeyboardFocus({ $script:Ui.SearchBorder.BorderBrush = Get-LdBrush 'Line' })
    $script:Ui.CategoryList.Add_SelectionChanged({
        if ($script:Ui.Muted) { return }
        if ($script:Ui.SearchBox.Text) { $script:Ui.PrevCategory = $null; $script:Ui.SearchBox.Text = '' }
        Update-LdView
    })
    $script:Ui.SelectAllButton.Add_Click({ Set-LdVisibleChecked -Value $true })
    $script:Ui.SelectNoneButton.Add_Click({ Set-LdVisibleChecked -Value $false })
    $script:Ui.CloseButton.Add_Click({ $script:Ui.Window.Close() })

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(80)
    $timer.Add_Tick({ Invoke-LdEvents })
    $script:Ui.Timer = $timer

    $window.Add_SourceInitialized({ if ($script:Ui.Dark) { Set-LdDarkTitleBar -Window $script:Ui.Window } })
    $window.Add_Loaded({ $script:Ui.Timer.Start(); Start-LdLoad })
    $window.Add_Closed({ Stop-LdBackground })
    $window
}

function Show-LdWindow {
    param([switch]$Practice, [string]$SelfPath)
    Initialize-LdSync -LogFile (New-LdLogFile)
    Write-LdLog "LaunchDeck started (practice: $([bool]$Practice), admin: $(Test-LdAdmin), file: $SelfPath)"
    $localDir = if ($SelfPath) { Split-Path -Parent $SelfPath } else { '' }
    $window = New-LdWindow -Practice:$Practice -LocalDir $localDir
    [void]$window.ShowDialog()
}

# Dot-sourcing (the tests do this) loads the functions without opening the window.
if ($MyInvocation.InvocationName -eq '.') { return }

Start-LaunchDeck -Practice:$Practice -SelfPath $PSCommandPath
