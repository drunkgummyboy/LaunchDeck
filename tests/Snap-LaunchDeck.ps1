# Renders the LaunchDeck window off-screen (practice mode) and saves a PNG, so the UI can be
# checked without it popping up. Run with:
#   powershell.exe -NoProfile -File tests\Snap-LaunchDeck.ps1 -Out shot.png [-Theme light] [-Action '<code>'] [-Seconds 15]
# -Action runs after loading (e.g. "Set-LdPreset -Name 'None'"); a second shot is taken after it.
param(
    [string]$Out = (Join-Path $env:TEMP 'launchdeck.png'),
    [ValidateSet('dark', 'light')][string]$Theme = 'dark',
    [string]$Action = '',
    [int]$Seconds = 15,
    [int]$ActionSeconds = 8
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\LaunchDeck.ps1')
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

Initialize-LdSync -LogFile (Join-Path $env:TEMP 'launchdeck-snap.log')
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$window = New-LdWindow -Practice -LocalDir $repo -Dark ($Theme -eq 'dark')
$window.WindowStartupLocation = 'Manual'
$window.Left = -20000
$window.Top = 0
$window.ShowActivated = $false
$window.ShowInTaskbar = $false
$window.Show()

function Wait-Dispatcher([double]$Sec) {
    $frame = New-Object Windows.Threading.DispatcherFrame
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds($Sec)
    $timer.Add_Tick({ $timer.Stop(); $frame.Continue = $false }.GetNewClosure())
    $timer.Start()
    [Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Save-Shot([string]$Path) {
    $root = $window.Content
    $root.UpdateLayout()
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$root.ActualWidth, [int]$root.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($root)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $file = [IO.File]::Create($Path)
    try { $encoder.Save($file) } finally { $file.Dispose() }
    Write-Host "Saved $Path"
}

Wait-Dispatcher $Seconds
Save-Shot $Out
if ($Action) {
    & ([scriptblock]::Create($Action))
    Wait-Dispatcher $ActionSeconds
    Save-Shot ([IO.Path]::ChangeExtension($Out, '.after.png'))
}
$script:Ui.CloseWhenDone = $true   # skip the "still installing, close?" question
$window.Close()
Get-Content (Join-Path $env:TEMP 'launchdeck-snap.log') -Tail 8
