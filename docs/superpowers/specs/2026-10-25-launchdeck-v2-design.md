# LaunchDeck v2 — Design

- **Date:** 2026-10-25
- **Owner:** drunkgummyboy
- **Repo:** github.com/drunkgummyboy/LaunchDeck (work happens on `main`)
- **Mockup:** [2026-10-25-launchdeck-v2-mockup.html](2026-10-25-launchdeck-v2-mockup.html). Layout **B (sidebar)** was chosen; option A is not wanted.

## What LaunchDeck is, and why v2

LaunchDeck is a single PowerShell script that sets up a Windows PC through a window. You tick apps from a list and it installs them with winget. A side panel runs helper scripts that live in the repo's `scripts/` folder. The owner uses it on fresh Windows installs and on existing PCs, their own and family PCs.

v1 works on the owner's PC, but it fails in exactly the situations it exists for:

- **No winget → crash.** In `Test-Winget`, `return$false` (missing space) is a command-not-found error. So on a PC without winget, the step that should install winget crashes first.
- **Desktop shortcut → silent crash.** The shortcut runs LaunchDeck from the web (`irm | iex`). Then `$PSCommandPath` is empty, `Split-Path` throws on line 8, and the window is hidden, so nothing at all appears.
- **"upgrade all" tool → 404.** Spaces in file names are turned into `\%20` instead of `%20`.
- The window freezes ("Not Responding") during each install. Startup is slow: icons download one at a time, and the installed check runs `winget list` once per app. The summary gives counts but not which apps failed.
- Adding a tool's description or icon means editing LaunchDeck.ps1 itself.

v2 fixes all of this and gives LaunchDeck a modern, data-driven window.

## Goals

1. Works on a stock Windows 10 (1809+) or 11 PC with only the built-in Windows PowerShell 5.1.
2. Starts three ways: the desktop shortcut, a one-line command on a fresh PC, or running the file directly.
3. A sidebar-layout window with search, presets, categories, and detection of already-installed apps.
4. Installs that keep the window responsive, show per-app status, can retry failures, can stop cleanly, and end with a summary that names apps.
5. Apps, categories, presets and tool descriptions live in data files in the repo, not in the script.
6. A button in the window that creates a LaunchDeck shortcut on the desktop.
7. Light or dark, following the Windows setting.
8. A practice mode that runs the whole flow without installing anything.

## Non-goals

- Uninstalling apps, or updating single apps. The "Upgrade all" tool already covers updates.
- Installing several apps at the same time.
- Editing the app list from inside the window. You edit `apps.json` instead.
- Remembering the last selection between runs. Presets cover that need.
- Package sources other than winget.

## Anti-goals (failures even if everything "works")

- **Failing silently.** Every startup, download or install failure must end in a message the owner can read.
- **A frozen window.** Nothing slow runs on the window's thread.
- **Editing LaunchDeck.ps1 to add an app, category, preset or tool.**
- **Breaking the live shortcut.** Every LaunchDeck shortcut runs the newest `LaunchDeck.ps1` from GitHub `main`. So nothing is pushed until the owner has tried v2 on their PC and approved it.

## Constraints

- **Windows PowerShell 5.1 only.** No PowerShell 7 and no modules from the PowerShell Gallery. WPF (`PresentationFramework`) and WinForms are available.
- **Single file.** `LaunchDeck.ps1` must work when piped through `irm <raw url> | iex`. No dot-sourced helper files.
- **Admin rights are required** for machine-wide winget installs and for installing winget itself.
- **Windows Defender has flagged shortcuts that contain `irm … | iex` inline.** The existing launcher script works around this with a local launcher file, and v2 shortcuts must do the same.
- **The GitHub API allows 60 unauthenticated requests per hour per IP.** Use `raw.githubusercontent.com` for files. Use the API only to list the `scripts/` folder, and treat that call as optional.
- **The project folder is inside Google Drive.** Keep generated or cache files out of the repo folder.

## Decided with the owner

### Main window (mockup option B)

- **Top bar:** a search box that filters cards as you type, then preset buttons: the owner's presets plus the built-in "Everything" and "None".
- **Left:** a category menu with a count per category, with "All" first.
- **Middle:**
  - App cards with an icon and a name. Clicking a card ticks or unticks it.
  - Already-installed apps are greyed out with a green "Installed" tag and can't be ticked.
  - A line above the cards reads "N of M selected · K already installed", next to Select all / Select none.
- **Right:** "Tools from GitHub", one entry per script with an icon, a name and a one-line description. Clicking an entry runs the script.
- **Bottom:**
  - Winget status, plus a Close button.
  - "Install N apps", where N updates live and the button is disabled at 0.
  - The desktop-shortcut button.
- **Theme:** follows the Windows light/dark setting.

### Installing

- Apps install one at a time and silently. The window stays responsive.
- Each app shows one status: Waiting, Installing, Installed, Already installed, or Failed with a reason.
- Each failed app gets a Retry button. "Stop after this app" ends the run cleanly after the current install.
- "Restart required to finish" counts as installed, with a note.
- On a PC without winget, LaunchDeck installs winget first.
- The final summary lists installed, already-present and failed apps by name. A log file is written, and an "Open log" button opens it.

### Starting

- The desktop shortcut, the one-line command, or running the file directly all work.
- LaunchDeck asks for admin rights once. When started from the shortcut, no console window stays behind the app.
- Tools open in their own PowerShell window, as in v1.

### Desktop shortcut button (owner request)

- A button in the window creates a LaunchDeck shortcut on the desktop, with the LaunchDeck icon.
- The shortcut always runs the latest LaunchDeck from GitHub.

### Data, not code

- The app list, categories and presets live in `apps.json`.
- Tool names, descriptions and icons live in `tools.json`.
- Both files sit in the repo root.

## My calls (the owner can override any of these)

1. **The window uses WPF, not WinForms.** WPF makes the rounded, modern look and dark mode realistic in PowerShell 5.1. The window is defined in XAML inside the script.
2. **The data files load from GitHub.** `apps.json` and `tools.json` are fetched from raw GitHub `main`. If a copy sits next to the script, that copy wins, which is handy for testing. If neither can be read, show an error message and stop; never open an empty window silently.
3. **Select all / Select none act only on the category being viewed.** In "All", they act on everything. Installed apps are never ticked.
4. **Presets:**
   - "My PC" is every app.
   - "Family laptop" is Firefox, 7-Zip, Google Drive, VLC, Spotify, WhatsApp, File Converter and Stirling PDF.
   - Clicking a preset replaces the current selection. It does not add to it.
5. **Categories and their order:**
   - Essentials: Firefox, 7-Zip, PowerToys, Google Drive, Windows Terminal, PowerShell 7
   - Media: VLC, Spotify, Paint.NET, FileBot, File Converter
   - Chat: Discord, WhatsApp
   - 3D printing: Bambu Studio, F3D, STL-Thumb
   - Developer: Node.js, Python, Phoenix Code
   - Documents: Stirling PDF
6. **What's ticked when the window opens:** the first preset ("My PC"), minus installed apps.
7. **The shortcut button** sits at the bottom left of the footer, labelled "Add to desktop". When a LaunchDeck shortcut already exists, it reads "On desktop ✓", and clicking it again rebuilds the shortcut, for example after a broken icon.
8. **"download LaunchDeck to dekstop from git.ps1" is retired.** The button replaces it. On a fresh PC: run the one-line command, then click "Add to desktop".
9. **Practice mode** is a `-Practice` switch.
   - It does everything except calling `winget install`: fake progress with short random delays, and one simulated failure so Retry can be tested.
   - The title bar shows "Practice mode".
   - The installed-apps check still runs for real, since it changes nothing.
10. **Fixes in the app list.** Checked on 2026-10-25 with `winget show --id <id> --exact`. Three of today's IDs fail, because `--exact` is case-sensitive or the app moved:
    - `Google.googleDrive` → `Google.GoogleDrive`
    - `dotPDN.paintdotnet` → `dotPDN.PaintDotNet`
    - `WhatsApp.WhatsApp` no longer exists in winget's own source. WhatsApp is now Microsoft Store only: `9NKSQGP7F2NH`, source `msstore`.
    - Trim the trailing space in `Microsoft.PowerShell `.
    - Fix the icon sites: Phoenix Code → `phcode.dev`, Stirling PDF → `stirlingpdf.com`, STL-Thumb → `github.com`.
    - Show PowerShell as "PowerShell 7".
11. **Tools:**
    - `tools.json` gives the name, description and icon per script file.
    - Any `.ps1` in `scripts/` that is missing from `tools.json` still shows up, with its file name and the description "Run <file>", which keeps v1's "drop a script in the folder" behaviour. If the folder listing fails (rate limit or offline), only the `tools.json` entries show.
    - `scripts/Old/` and non-`.ps1` files are ignored.
    - Download links come from GitHub's own `download_url`, or are properly URL-encoded, which fixes the "upgrade all" 404.
12. **Starting tool descriptions** *(guesses, easy to edit in `tools.json`)*:

    | Tool | Description |
    |---|---|
    | WinUtil | Adds a Chris Titus WinUtil shortcut to the desktop |
    | Office | Remove, download or activate Office |
    | Set PC name | Rename the PC and its boot menu entry |
    | Shortcuts | Desktop shortcuts for torrents, Downloads and AirGrabber |
    | Upgrade all | Update every installed app with winget |
13. **Where files go on the PC:**
    - `%LOCALAPPDATA%\LaunchDeck\` holds the cached script copy, the launcher, icons and downloaded tool scripts.
    - Logs go to `%ProgramData%\LaunchDeck\logs\LaunchDeck_yyyyMMdd_HHmmss.log`.
14. **Closing the window during an install** asks for confirmation first. If the owner confirms, LaunchDeck finishes the current app and then closes. It never kills winget mid-install.
15. **Search** looks through every category. Typing switches the view to "All" and shows only the matches. Clearing the box restores the previous view.
16. **Winget IDs match case-insensitively inside LaunchDeck:** presets, installed detection and the selection. They're passed to winget exactly as written in `apps.json`, because `--exact` is case-sensitive.
17. **A short `README.md`** in the repo explains the one-line command, the desktop button, and how to add an app or tool.
18. **Git:** commits use the owner's GitHub no-reply address (`9091724+drunkgummyboy@users.noreply.github.com`), so their personal email never appears publicly. Nothing is pushed without the owner's OK.

## Data formats

`apps.json`:

```json
{
  "categories": ["Essentials", "Media", "Chat", "3D printing", "Developer", "Documents"],
  "presets": [
    { "name": "My PC",         "apps": "*" },
    { "name": "Family laptop", "apps": ["Mozilla.Firefox", "7zip.7zip", "Google.GoogleDrive", "VideoLAN.VLC",
                                         "Spotify.Spotify", "9NKSQGP7F2NH", "AdrienAllard.FileConverter",
                                         "StirlingTools.StirlingPDF"] }
  ],
  "apps": [
    { "name": "Firefox",  "id": "Mozilla.Firefox", "category": "Essentials", "icon": "firefox.com" },
    { "name": "WhatsApp", "id": "9NKSQGP7F2NH",    "category": "Chat",       "icon": "whatsapp.com", "source": "msstore" }
  ]
}
```

- `icon` is either a domain (fetched as a favicon) or a full `https://` image URL.
- `source` is optional (`winget` or `msstore`) and is passed to winget as `--source`.
- An app whose category isn't listed in `categories` goes under "Other", which appears last.
- If `apps.json` is the old v1 format (a bare array with `Name`/`Id`/`Domain`), read it with every app under "Other" and no presets other than "Everything" and "None".

`tools.json`:

```json
[
  { "file": "WinUtill.ps1", "name": "WinUtil", "description": "Adds a Chris Titus WinUtil shortcut to the desktop", "icon": "christitus.com" },
  { "file": "Shortcuts.ps1", "name": "Shortcuts", "description": "Desktop shortcuts for torrents, Downloads and AirGrabber", "icon": "assets/MoveTorrentFiles.ico" },
  { "file": "upgrade all.ps1", "name": "Upgrade all", "description": "Update every installed app with winget" }
]
```

- `icon` is a domain, a full URL, or a path inside `scripts/`.
- When `icon` is missing, the tool shows a plain glyph.

## How it works (sketch for the builder)

1. **Startup and elevation**
   - Not admin, started from a file: relaunch itself elevated with `-File`, passing the same switches and `-WindowStyle Hidden`.
   - Not admin, started via `iex` (no file path): download `LaunchDeck.ps1` from raw GitHub to `%LOCALAPPDATA%\LaunchDeck\LaunchDeck.ps1`, then relaunch that copy elevated. Never hide the terminal the owner typed the command into.
   - Any startup error shows a message box.
2. **Loading**
   - Open the window right away, with a "Loading…" state.
   - Fetch `apps.json` and `tools.json`, check winget, and read the installed apps, all off the UI thread.
   - Icons load in the background into a cache. A card shows a letter placeholder until its icon arrives, and a corrupt cache file is deleted rather than kept.
3. **Installed apps**
   - Read them in one pass, for example with `winget export -o <temp.json> --accept-source-agreements`, matching `PackageIdentifier` case-insensitively.
   - If winget is missing, every app counts as not installed.
4. **Winget on a fresh PC**
   - First try re-registering App Installer: `Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe`. This fixes the common case where winget isn't ready yet at first logon.
   - If that fails, download and install App Installer and its dependencies from Microsoft's official sources, then refresh `PATH`.
   - Show this as its own row in the install list ("Setting up winget").
5. **Install engine**
   - A background runspace works through the queue. The UI reads its progress from a synchronized hashtable or queue on a `DispatcherTimer`.
   - Run `winget install --id <id> --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity`, plus `--source <source>` when the app has one.
   - Output goes to the log, and the "Show details" panel shows it live.
   - Map exit codes to statuses: success, already installed, reboot required (counts as installed), anything else failed. Show winget's message as the reason.
6. **Tools:** download the script to `%LOCALAPPDATA%\LaunchDeck\scripts\`, then run `powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File <file>`. It inherits admin rights.
7. **The shortcut button**
   - Write `%LOCALAPPDATA%\LaunchDeck\Launcher.ps1`. It downloads the latest `LaunchDeck.ps1` to the local cache, falls back to the cached copy when offline, and runs it with `-File`.
   - Download `scripts/assets/LaunchDeck.ico` to the same folder.
   - Create `LaunchDeck.lnk` on `[Environment]::GetFolderPath('Desktop')`, pointing at `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<Launcher.ps1>"`.
8. **The one-line command**, shown in the README:
   `irm https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/LaunchDeck.ps1 | iex`

## Left to the builder

- XAML structure and styling, staying close to the mockup.
- The exact background-work pattern, as long as the UI thread never blocks.
- The exact winget exit codes for "already installed" and "reboot required", checked against winget's documented return codes. Also which flags the installed winget supports (it's v1.29 on the owner's PC).
- The details of the winget bootstrap download on current Windows versions.
- **Edge case:** on a family PC, a standard user may elevate with a different admin account. Then "Desktop" and the theme setting belong to the admin account. Detect this and put the shortcut on the Public Desktop, or tell the user where it went.
- Timeouts for every network call (about 10 s), so a dead connection never hangs the window.

## How we'll know it works

1. The script parses with no errors.
2. **Practice mode:** the whole flow works, including retry, "Stop after this app", the summary and "Open log".
3. **A real run** installing one small app that isn't installed yet. Check the per-app status, the summary and the log.
4. **Start paths:**
   - Running the file directly.
   - `Get-Content LaunchDeck.ps1 -Raw | iex` from a non-admin terminal, which simulates the one-line command.
   - The desktop shortcut made by the new button.
5. **Tools:** every entry downloads and opens the right script, including "upgrade all".
6. **App list:** every winget ID in `apps.json` resolves (`winget show --id <id> --exact`).
7. **Light and dark:** both themes look right.
8. **Only after the owner says OK:** commit and push to `main`, then test the one-line command against GitHub for real.
