# Plain-PowerShell tests for LaunchDeck.ps1. Run with:
#   powershell.exe -NoProfile -File tests\LaunchDeck.Tests.ps1 [-Only <name filter>]
param([string]$Only = '')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\LaunchDeck.ps1')

$script:Passed = 0
$script:Failed = 0

function Test-It {
    param([string]$Name, [scriptblock]$Body)
    if ($Only -and $Name -notlike "*$Only*") { return }
    try {
        & $Body
        $script:Passed++
        Write-Host "PASS  $Name" -ForegroundColor Green
    } catch {
        $script:Failed++
        Write-Host "FAIL  $Name" -ForegroundColor Red
        Write-Host "      $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Because = '')
    $e = @($Expected); $a = @($Actual)
    if ($e.Count -ne $a.Count -or (($e -join '|') -cne ($a -join '|'))) {
        throw "Expected [$($e -join ', ')] but got [$($a -join ', ')] $Because"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Because = 'condition was false')
    if (-not $Condition) { throw $Because }
}

$CatalogJson = @'
{
  "categories": ["Essentials", "Media"],
  "presets": [
    { "name": "My PC",  "apps": "*" },
    { "name": "Family", "apps": ["google.googledrive", "VideoLAN.VLC", "Not.InCatalog"] }
  ],
  "apps": [
    { "name": "Google Drive", "id": "Google.GoogleDrive",    "category": "Essentials", "icon": "drive.google.com" },
    { "name": "VLC",          "id": "VideoLAN.VLC",          "category": "Media",      "icon": "videolan.org" },
    { "name": "PowerShell 7", "id": "Microsoft.PowerShell ", "category": "Mystery",    "icon": "microsoft.com", "source": "winget" }
  ]
}
'@

# ---------------- Task 1: data helpers ----------------

Test-It 'ConvertTo-LdCatalog v2 reads apps, trims ids, adds Other only when used' {
    $c = ConvertTo-LdCatalog -Json $CatalogJson
    Assert-Equal @('Essentials', 'Media', 'Other') $c.Categories
    Assert-Equal 'Microsoft.PowerShell' $c.Apps[2].Id
    Assert-Equal 'Other' $c.Apps[2].Category
    Assert-Equal 'winget' $c.Apps[2].Source
    Assert-Equal '' $c.Apps[0].Source
    Assert-Equal 2 $c.Presets.Count
    Assert-True $c.Presets[0].All 'My PC preset should be All'

    $noOther = ConvertTo-LdCatalog -Json '{"categories":["Media"],"apps":[{"name":"VLC","id":"VideoLAN.VLC","category":"Media"}]}'
    Assert-Equal @('Media') $noOther.Categories
}

Test-It 'ConvertTo-LdCatalog v1 bare array maps to Other' {
    $c = ConvertTo-LdCatalog -Json '[{"Name":"VLC","Id":"VideoLAN.VLC","Domain":"videolan.org"}]'
    Assert-Equal 'Other' $c.Apps[0].Category
    Assert-Equal 'videolan.org' $c.Apps[0].Icon
    Assert-Equal 'VLC' $c.Apps[0].Name
    Assert-Equal @('Other') $c.Categories
    Assert-Equal 0 $c.Presets.Count
}

Test-It 'Resolve-LdPreset matches ids case-insensitively and knows the built-ins' {
    $c = ConvertTo-LdCatalog -Json $CatalogJson
    Assert-Equal @('Google.GoogleDrive', 'VideoLAN.VLC') (Resolve-LdPreset -Catalog $c -Name 'Family')
    Assert-Equal 3 @(Resolve-LdPreset -Catalog $c -Name 'My PC').Count
    Assert-Equal 3 @(Resolve-LdPreset -Catalog $c -Name 'Everything').Count
    Assert-Equal 0 @(Resolve-LdPreset -Catalog $c -Name 'None').Count
    Assert-Equal 0 @(Resolve-LdPreset -Catalog $c -Name 'No such preset').Count
}

Test-It 'Get-LdRawUrl encodes spaces' {
    Assert-Equal 'https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/upgrade%20all.ps1' (Get-LdRawUrl -Path 'scripts/upgrade all.ps1')
    Assert-Equal 'https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/a%23b.ps1' (Get-LdRawUrl -Path 'scripts/a#b.ps1')
}

Test-It 'Get-LdIconUrl handles domains, repo paths, urls and empty' {
    Assert-Equal 'https://www.google.com/s2/favicons?domain=firefox.com&sz=64' (Get-LdIconUrl -Icon 'firefox.com')
    Assert-Equal 'https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/assets/CTTtools.ico' (Get-LdIconUrl -Icon 'assets/CTTtools.ico')
    Assert-Equal 'https://example.com/i.png' (Get-LdIconUrl -Icon 'https://example.com/i.png')
    Assert-True ($null -eq (Get-LdIconUrl -Icon '')) 'empty icon should give $null'
}

Test-It 'ConvertTo-LdToolList merges tools.json with the folder listing' {
    $toolsJson = '[{"file":"Office.ps1","name":"Office","description":"Office stuff","icon":"office.com"},{"file":"Gone.ps1","name":"Gone","description":"x"}]'
    $listing = @(
        [pscustomobject]@{ name = 'Office.ps1';   type = 'file' },
        [pscustomobject]@{ name = 'New Tool.ps1'; type = 'file' },
        [pscustomobject]@{ name = 'readme.md';    type = 'file' },
        [pscustomobject]@{ name = 'Old';          type = 'dir' }
    )
    $tools = ConvertTo-LdToolList -ToolsJson $toolsJson -Listing $listing
    Assert-Equal @('Office', 'New Tool') ($tools | ForEach-Object Name)
    Assert-Equal 'Run New Tool.ps1' $tools[1].Description
    Assert-Equal 'https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/scripts/New%20Tool.ps1' $tools[1].Url
    Assert-Equal 'office.com' $tools[0].Icon

    $noListing = ConvertTo-LdToolList -ToolsJson $toolsJson -Listing $null
    Assert-Equal @('Office', 'Gone') ($noListing | ForEach-Object Name)

    $badJson = ConvertTo-LdToolList -ToolsJson 'nope' -Listing $listing
    Assert-Equal @('New Tool', 'Office') ($badJson | ForEach-Object Name) 'listing-only tools are sorted by file name'
}

Test-It 'ConvertFrom-LdWingetExport handles empty/garbage' {
    Assert-Equal 0 (ConvertFrom-LdWingetExport -Json '').Count
    Assert-Equal 0 (ConvertFrom-LdWingetExport -Json 'not json').Count
    $set = ConvertFrom-LdWingetExport -Json '{"Sources":[{"Packages":[{"PackageIdentifier":"Mozilla.Firefox"},{"PackageIdentifier":"7zip.7zip"}]},{"Packages":[{"PackageIdentifier":"9NKSQGP7F2NH"}]}]}'
    Assert-Equal 3 $set.Count
    Assert-True ($set.Contains('mozilla.firefox')) 'lookup should ignore case'
}

Test-It 'Get-LdInstallResult maps winget exit codes' {
    $cases = @(
        @(0,           'Installed',        ''),
        @(-1978334967, 'Installed',        'Restart needed to finish'),    # 0x8A150109
        @(-1978334965, 'Installed',        'Restart needed to finish'),    # 0x8A15010B
        @(-1978335135, 'AlreadyInstalled', ''),                            # 0x8A150061
        @(-1978334963, 'AlreadyInstalled', ''),                            # 0x8A15010D
        @(-1978335189, 'AlreadyInstalled', ''),                            # 0x8A15002B
        @(-1978334966, 'Failed',           'Restart the PC, then retry'),  # 0x8A15010A
        @(-1978335212, 'Failed',           'Not found in winget'),         # 0x8A150014
        @(-1978334969, 'Failed',           'No internet connection'),      # 0x8A150107
        @(-1978335216, 'Failed',           'winget error 0x8A150010'),
        @(5,           'Failed',           'winget error 0x00000005')
    )
    foreach ($c in $cases) {
        $r = Get-LdInstallResult -ExitCode $c[0]
        Assert-Equal $c[1] $r.Status "for exit code $($c[0])"
        Assert-Equal $c[2] $r.Note "for exit code $($c[0])"
    }
}

Test-It 'Get-LdSummary groups names by status' {
    $results = @{
        'C' = @{ Name = 'Gamma'; Status = 'Failed' }
        'A' = @{ Name = 'Alpha'; Status = 'Installed' }
        'B' = @{ Name = 'Beta';  Status = 'AlreadyInstalled' }
        'D' = @{ Name = 'Delta'; Status = 'Installed' }
    }
    $s = Get-LdSummary -Results $results
    Assert-Equal @('Alpha', 'Delta') $s.Installed
    Assert-Equal @('Beta') $s.Already
    Assert-Equal @('Gamma') $s.Failed
}

# ---------------- Task 2: startup ----------------

Test-It 'Get-LdLaunchPlan picks how to start' {
    $cases = @(
        # IsAdmin, SelfPath,        Edition,   Practice, expected
        @($false, 'C:\x\LD.ps1', 'Desktop', $true,  'Run'),
        @($false, '',            'Desktop', $true,  'Run'),
        @($true,  'C:\x\LD.ps1', 'Desktop', $false, 'Run'),
        @($true,  '',            'Desktop', $false, 'Run'),
        @($false, 'C:\x\LD.ps1', 'Desktop', $false, 'ElevateFile'),
        @($false, '',            'Desktop', $false, 'DownloadThenElevate'),
        @($false, 'C:\x\LD.ps1', 'Core',    $true,  'RelaunchFile'),
        @($true,  'C:\x\LD.ps1', 'Core',    $false, 'ElevateFile'),
        @($true,  '',            'Core',    $false, 'DownloadThenElevate')
    )
    foreach ($c in $cases) {
        $plan = Get-LdLaunchPlan -IsAdmin $c[0] -SelfPath $c[1] -Edition $c[2] -Practice $c[3]
        Assert-Equal $c[4] $plan "for admin=$($c[0]) path='$($c[1])' edition=$($c[2]) practice=$($c[3])"
    }
}

Test-It 'Get-LdText returns null fast on refused connection' {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $text = Get-LdText -Url 'http://127.0.0.1:9/nothing'
    Assert-True ($null -eq $text) 'refused connection should give $null'
    Assert-True ($watch.Elapsed.TotalSeconds -lt 10) "took $($watch.Elapsed.TotalSeconds) s"
}

Test-It 'Get-LdText prefers local file' {
    $tmp = Join-Path $env:TEMP "ld-test-$PID.json"
    [IO.File]::WriteAllText($tmp, 'abc')
    try { Assert-Equal 'abc' (Get-LdText -Url 'http://127.0.0.1:9/nothing' -LocalPath $tmp) }
    finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
}

Test-It 'Write-LdLog appends timestamped lines to the log file' {
    $log = Join-Path $env:TEMP "ld-test-$PID.log"
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    Initialize-LdSync -LogFile $log
    Write-LdLog 'first line'
    Write-LdLog 'second line'
    $lines = @(Get-Content -LiteralPath $log)
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    Assert-Equal 2 $lines.Count
    Assert-True ($lines[1] -match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d  second line$') "unexpected line: $($lines[1])"
}

# ---------------- Task 3: window helpers ----------------

Test-It 'Get-LdVisibleIds filters by category, or by search across all categories' {
    $c = ConvertTo-LdCatalog -Json $CatalogJson
    Assert-Equal @('VideoLAN.VLC') (Get-LdVisibleIds -Catalog $c -Category 'Media' -Search '')
    Assert-Equal @('Microsoft.PowerShell') (Get-LdVisibleIds -Catalog $c -Category 'Media' -Search 'POWER')
    Assert-Equal 3 @(Get-LdVisibleIds -Catalog $c -Category 'All' -Search '').Count
    Assert-Equal @('VideoLAN.VLC') (Get-LdVisibleIds -Catalog $c -Category 'Media' -Search '   ')
    Assert-Equal 0 @(Get-LdVisibleIds -Catalog $c -Category 'All' -Search 'zzz').Count
}

Test-It 'Test-LdImageFile rejects text file' {
    $bad = Join-Path $env:TEMP "ld-test-$PID-bad.png"
    [IO.File]::WriteAllText($bad, '<html><body>not an image</body></html>')
    Assert-True (-not (Test-LdImageFile -Path $bad)) 'html should not count as an image'
    Assert-True (-not (Test-Path -LiteralPath $bad)) 'a bad image file should be deleted'

    $good = Join-Path $env:TEMP "ld-test-$PID-good.png"
    [IO.File]::WriteAllBytes($good, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='))
    try { Assert-True (Test-LdImageFile -Path $good) 'a real PNG should pass' }
    finally { Remove-Item -LiteralPath $good -ErrorAction SilentlyContinue }
}

# ---------------- Task 4: install engine ----------------

function New-FakeApp([string]$Name) { [pscustomobject]@{ Name = $Name; Id = "Fake.$Name"; Category = 'Other'; Icon = ''; Source = '' } }

function Get-FinalStatuses {
    $events = @()
    $evt = $null
    while ($LdSync.Events.TryDequeue([ref]$evt)) { $events += $evt }
    @{
        Final = @($events | Where-Object { $_.Type -eq 'AppStatus' -and $_.Data.Status -ne 'Installing' })
        Done  = @($events | Where-Object { $_.Type -eq 'EngineDone' })
        Last  = $events[-1]
    }
}

Test-It 'Invoke-LdInstallQueue practice: third app fails once, then retry succeeds' {
    Initialize-LdSync -LogFile ''
    foreach ($n in 'One', 'Two', 'Three') { $LdSync.Pending.Enqueue((New-FakeApp $n)) }
    Invoke-LdInstallQueue -Practice $true -PracticeDelayMs 10
    $r = Get-FinalStatuses
    Assert-Equal @('Installed', 'Installed', 'Failed') ($r.Final | ForEach-Object { $_.Data.Status })
    Assert-Equal 'Simulated failure' $r.Final[2].Data.Note
    Assert-Equal 'Fake.Three' $r.Final[2].Data.Id
    Assert-Equal 'EngineDone' $r.Last.Type
    Assert-True (-not $r.Last.Data.Stopped) 'a full run is not "stopped"'

    $LdSync.Pending.Enqueue((New-FakeApp 'Three'))
    Invoke-LdInstallQueue -Practice $true -PracticeDelayMs 10
    $r = Get-FinalStatuses
    Assert-Equal @('Installed') ($r.Final | ForEach-Object { $_.Data.Status })
}

Test-It 'Invoke-LdInstallQueue stops after the current app when asked' {
    Initialize-LdSync -LogFile ''
    $LdSync.Pending.Enqueue((New-FakeApp 'One'))
    $LdSync.Pending.Enqueue((New-FakeApp 'Two'))
    $LdSync.StopAfterCurrent = $true
    Invoke-LdInstallQueue -Practice $true -PracticeDelayMs 10
    $r = Get-FinalStatuses
    Assert-Equal 1 $r.Final.Count
    Assert-True $r.Last.Data.Stopped 'EngineDone should say it stopped early'
    Assert-Equal 1 $LdSync.Pending.Count
}

Test-It 'Test-LdNoiseLine drops winget progress output' {
    $block = [string][char]0x2588
    $shade = [string][char]0x2592
    foreach ($noise in @('', '   ', '  - ', '\', '  |', "  $($block * 10)$($shade * 5)  1.2 MB / 20.5 MB", '  42%')) {
        Assert-True (Test-LdNoiseLine -Line $noise) "should be noise: [$noise]"
    }
    foreach ($keep in @('Successfully installed', 'Found Spotify [Spotify.Spotify] Version 1.2.3', 'Installer failed with exit code: 1603')) {
        Assert-True (-not (Test-LdNoiseLine -Line $keep)) "should be kept: [$keep]"
    }
}

# ---------------- Task 5: desktop shortcut ----------------

Test-It 'Get-LdShortcutTarget uses the Public Desktop when someone else elevated' {
    $same = Get-LdShortcutTarget -ConsoleUser 'PC\beau' -CurrentUser 'PC\beau'
    Assert-Equal ([Environment]::GetFolderPath('Desktop')) $same.Desktop
    Assert-True (-not $same.Public) 'same user should use their own desktop'
    $unknown = Get-LdShortcutTarget -ConsoleUser '' -CurrentUser 'PC\beau'
    Assert-True (-not $unknown.Public) 'unknown console user (e.g. remote desktop) should use their own desktop'

    $other = Get-LdShortcutTarget -ConsoleUser 'PC\kid' -CurrentUser 'PC\admin'
    Assert-Equal (Join-Path $env:PUBLIC 'Desktop') $other.Desktop
    Assert-Equal (Join-Path $env:ProgramData 'LaunchDeck') $other.DataDir
    Assert-True $other.Public 'a different console user should get the Public Desktop'
}

Test-It 'New-LdDesktopShortcut creates a shortcut that runs the launcher' {
    $root = Join-Path $env:TEMP "ld-test-$PID-shortcut"
    $desktop = Join-Path $root 'Desktop'
    $data = Join-Path $root 'Data'
    New-Item -ItemType Directory -Force -Path $desktop, $data | Out-Null
    try {
        $lnkPath = New-LdDesktopShortcut -Desktop $desktop -DataDir $data
        Assert-Equal (Join-Path $desktop 'LaunchDeck.lnk') $lnkPath
        Assert-True (Test-Path -LiteralPath $lnkPath) 'shortcut file should exist'
        $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
        Assert-True ($lnk.TargetPath -like '*\WindowsPowerShell\v1.0\powershell.exe') "target was $($lnk.TargetPath)"
        Assert-True ($lnk.Arguments -like "*-WindowStyle Hidden -File `"$data\Launcher.ps1`"*") "arguments were $($lnk.Arguments)"
        $launcher = Get-Content -Raw -LiteralPath (Join-Path $data 'Launcher.ps1')
        Assert-True ($launcher.Contains('https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/LaunchDeck.ps1')) 'launcher should download LaunchDeck.ps1'
        Assert-True ($launcher.Contains('$env:LOCALAPPDATA')) 'launcher should cache in the running user''s profile'
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($launcher, [ref]$null, [ref]$errors)
        Assert-Equal 0 $errors.Count 'launcher should be valid PowerShell'
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------- summary ----------------
Write-Host ''
Write-Host "$script:Passed passed, $script:Failed failed"
if ($script:Failed -gt 0) { exit 1 } else { exit 0 }
