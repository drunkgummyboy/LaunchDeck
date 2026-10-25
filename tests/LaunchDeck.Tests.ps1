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

# ---------------- summary ----------------
Write-Host ''
Write-Host "$script:Passed passed, $script:Failed failed"
if ($script:Failed -gt 0) { exit 1 } else { exit 0 }
