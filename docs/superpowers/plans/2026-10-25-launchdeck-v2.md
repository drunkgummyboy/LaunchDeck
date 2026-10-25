# LaunchDeck v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `LaunchDeck.ps1` as a single-file WPF app with a sidebar layout, data-driven apps/tools, a non-blocking install engine, a practice mode and a desktop-shortcut button.

**Architecture:** One script file, organised in sections:
- Pure helper functions (`Verb-LdNoun`), unit-tested by dot-sourcing the script.
- Startup and elevation.
- Background work: a runspace pool that gets every `*-Ld*` function. Workers post events to a synchronized `ConcurrentQueue`.
- The WPF window: XAML, plus a `DispatcherTimer` that drains the event queue.

Data lives in `apps.json` and `tools.json` in the repo root.

**Tech Stack:** Windows PowerShell 5.1, WPF (PresentationFramework), winget CLI, and a plain-PowerShell test harness (no Pester dependency).

**Spec:** `docs/superpowers/specs/2026-10-25-launchdeck-v2-design.md`

## Global Constraints

- Runs on Windows PowerShell 5.1 (`PSEdition` = `Desktop`), stock Windows 10 1809+ / 11, with no gallery modules.
- `LaunchDeck.ps1` stays a single file and must work through `irm <raw url> | iex`. Nothing at script top level may change the caller's session (no top-level `$ErrorActionPreference`).
- Raw base: `https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/`. The API is used only for `https://api.github.com/repos/drunkgummyboy/LaunchDeck/contents/scripts?ref=main`.
- Every network call has a ≤ 10 s timeout, and every failure ends in a readable message.
- The UI thread never runs winget, downloads or file scans.
- Cache folder `%LOCALAPPDATA%\LaunchDeck\`. Logs go to `%ProgramData%\LaunchDeck\logs\LaunchDeck_yyyyMMdd_HHmmss.log`.
- winget install arguments: `install --id <id> --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity [--source <source>]`.
- Nothing is pushed to GitHub in this plan.

## Review Focus

1. **GitHub unreachable at startup.** Show a message box naming what failed, never an empty window. → Task 2 test `Get-LdText returns null fast on refused connection`.
2. **winget missing or export fails.** All apps count as not installed and the footer says winget will be installed first. → Task 1 test `ConvertFrom-LdWingetExport handles empty/garbage`.
3. **Corrupt or HTML "icon" downloads.** The file is deleted and the letter placeholder stays. → Task 3 test `Test-LdImageFile rejects text file`.
4. **Tool file names with spaces or `#`.** The URL is percent-encoded per segment. → Task 1 test `Get-LdRawUrl encodes spaces`.
5. **The user declines the UAC prompt, or closes mid-install.** A message, then a clean exit or deferred close. → Task 2 test `Get-LdLaunchPlan` cases. The UAC decline is checked by hand at handoff.

---

### Task 1: Test harness, data model helpers, new data files

**Files:**
- Create: `tests/LaunchDeck.Tests.ps1`, `apps.json` (rewrite), `tools.json`
- Modify: `LaunchDeck.ps1`, rewritten from scratch. In this task: the param block, constants, pure helpers, and the dot-source guard at the bottom (`if ($MyInvocation.InvocationName -eq '.') { return }`).

**Interfaces (produces):**
- `ConvertTo-LdCatalog -Json <string>` returns `[pscustomobject]@{ Categories=[string[]]; Presets=[object[]]; Apps=[object[]] }`.
  - Each app has `Name, Id, Category, Icon, Source`.
  - Each preset has `Name, All [bool], Ids [string[]]`.
  - The v1 bare-array format maps to the `Other` category with no presets.
  - Ids are trimmed.
  - An unknown category becomes `Other`, which is appended last only when it's used.
- `Resolve-LdPreset -Catalog <obj> -Name <string>` returns `[string[]]`: the catalog's exact-case Ids, matched case-insensitively. Built-ins: `Everything` → all apps, `None` → empty.
- `Get-LdRawUrl -Path <string>` returns `[string]`, each `/` segment escaped with `[uri]::EscapeDataString`.
- `Get-LdIconUrl -Icon <string>` returns `[string]` or `$null`:
  - `http(s)://…` is returned as-is.
  - A value containing `/`, or ending in `.ico`/`.png`, becomes `Get-LdRawUrl "scripts/$Icon"`.
  - Otherwise the result is `https://www.google.com/s2/favicons?domain=<Icon>&sz=64`.
- `ConvertTo-LdToolList -ToolsJson <string> -Listing <object[]|$null>` returns `[object[]]` of `Name, File, Description, Icon, Url`.
  - Order: `tools.json` order first, then unlisted `*.ps1` from the listing, sorted by name, each with `Description = "Run <file>"`.
  - When a listing is given, `tools.json` entries whose file isn't in it are dropped.
  - `Url = Get-LdRawUrl "scripts/<file>"`.
- `ConvertFrom-LdWingetExport -Json <string>` returns `HashSet[string]` (OrdinalIgnoreCase) of every `Sources[].Packages[].PackageIdentifier`. Empty or invalid input gives an empty set.
- `Get-LdInstallResult -ExitCode <int>` returns `@{ Status = 'Installed'|'AlreadyInstalled'|'Failed'; Note = <string> }`:
  - `0` → Installed.
  - `0x8A150109` and `0x8A15010B` → Installed, Note `Restart needed to finish`.
  - `0x8A150061`, `0x8A15010D` and `0x8A15002B` → AlreadyInstalled.
  - `0x8A15010A` → Failed `Restart the PC, then retry`.
  - `0x8A150014` → Failed `Not found in winget`.
  - `0x8A150107` → Failed `No internet connection`.
  - Anything else → Failed `winget error 0x{X8}`.
- `Get-LdSummary -Results <hashtable id→@{Name;Status}>` returns `@{ Installed=[string[]]; Already=[string[]]; Failed=[string[]] }`, holding names.

- [ ] **Step 1: Write the harness and the failing tests.** `tests/LaunchDeck.Tests.ps1` dot-sources `..\LaunchDeck.ps1` and defines `Test-It <name> <scriptblock>`, `Assert-Equal <exp> <act>` and `Assert-True <cond>`. It prints `PASS`/`FAIL` lines plus a total, and exits `1` on any failure. Tests:
  - `ConvertTo-LdCatalog v2`: an inline 3-app JSON → `Categories[-1] -eq 'Other'` only if used; the Id `'Microsoft.PowerShell '` → `'Microsoft.PowerShell'`.
  - `ConvertTo-LdCatalog v1`: `[{"Name":"VLC","Id":"VideoLAN.VLC","Domain":"videolan.org"}]` → `Apps[0].Category -eq 'Other'`, `Apps[0].Icon -eq 'videolan.org'`.
  - `Resolve-LdPreset`: `'google.googledrive'` in a preset → returns `'Google.GoogleDrive'`. `Everything` → the count of all apps. `None` → 0.
  - `Get-LdRawUrl encodes spaces`: `'scripts/upgrade all.ps1'` → `…/main/scripts/upgrade%20all.ps1`.
  - `Get-LdIconUrl`: `'firefox.com'` → the favicon URL; `'assets/CTTtools.ico'` → `…/main/scripts/assets/CTTtools.ico`; `''` → `$null`.
  - `ConvertTo-LdToolList`: the listing has `Office.ps1`, `New Tool.ps1` and `readme.md`, and `tools.json` names `Office.ps1` and `Gone.ps1` → names `Office`, `New Tool`. The second tool's Description is `Run New Tool.ps1`.
  - `ConvertFrom-LdWingetExport handles empty/garbage`: `''` → Count 0; `'not json'` → Count 0; a sample with 2 packages → Contains (case-insensitive).
  - `Get-LdInstallResult`: one assertion per code listed above.
  - `Get-LdSummary`: 3 results → the correct name lists.
- [ ] **Step 2: Run** `powershell.exe -NoProfile -File tests\LaunchDeck.Tests.ps1`. Expected: FAIL, because the functions aren't defined yet.
- [ ] **Step 3: Implement the helpers** in `LaunchDeck.ps1` with the signatures above.
- [ ] **Step 4: Rewrite `apps.json`** in the v2 format from the spec. Apply the ID fixes: `Google.GoogleDrive`, `dotPDN.PaintDotNet`, WhatsApp `9NKSQGP7F2NH` with source `msstore`, `Microsoft.PowerShell` trimmed and named "PowerShell 7". Apply the icon fixes, the spec's categories and order, and the presets. **Write `tools.json`** with the five spec descriptions. Icons: WinUtil `assets/CTTtools.ico`, Office `office.com`, Shortcuts `assets/MoveTorrentFiles.ico`, Set PC name and Upgrade all with none.
- [ ] **Step 5: Run the tests.** Expected: all PASS. Also run `winget show --id <id> --exact` for every app (with `--source` when set). Expected: all ok.
- [ ] **Step 6: Commit** with the message `LaunchDeck v2: data helpers, tests, new apps.json/tools.json`.

### Task 2: Startup, elevation, loading

**Interfaces:**
- Consumes the Task 1 helpers.
- Produces:
  - `Get-LdLaunchPlan -IsAdmin <bool> -SelfPath <string> -Edition <string> -Practice <bool>` returns `'Run'|'ElevateFile'|'DownloadThenElevate'`, under these rules:
    - Practice mode in Desktop edition → `Run` (it never needs admin).
    - Admin and Desktop edition → `Run`.
    - Otherwise, a SelfPath → `ElevateFile`.
    - Otherwise → `DownloadThenElevate`.
    - Core edition → never `Run`: elevate or relaunch through `powershell.exe`.
  - `Get-LdText -Url <string> [-LocalPath <string>]` returns `[string]` or `$null`. The local file wins when it exists. Uses `Invoke-WebRequest -UseBasicParsing -TimeoutSec 10` and decodes the bytes as UTF-8.
  - `Start-LaunchDeck [-Practice]` is the entry point called at the bottom of the script.
  - `Show-LdError -Message <string>` shows a WPF message box and writes to the log.
  - `Write-LdLog -Message <string>` is thread-safe, locking on `$LdSync.LogLock`.

- [ ] **Step 1: Write the failing tests.**
  - `Get-LdLaunchPlan`: all 6 combinations from the rules above.
  - `Get-LdText returns null fast on refused connection`: `http://127.0.0.1:9/x` → `$null` in under 10 s.
  - `Get-LdText prefers local file`: a temp file with `abc` → `'abc'`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `Start-LaunchDeck` sets `$ErrorActionPreference='Stop'` and TLS 1.2 inside the function.
  - It acts on the plan:
    - `ElevateFile`: `Start-Process powershell.exe -Verb RunAs` with `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<path>"` plus `-Practice` when set. If that throws (UAC declined), call `Show-LdError 'LaunchDeck needs admin rights to install apps.'`.
    - `DownloadThenElevate`: download `LaunchDeck.ps1` to `%LOCALAPPDATA%\LaunchDeck\LaunchDeck.ps1`, then elevate that file.
  - The script's own path comes from `$PSCommandPath`, captured at script top into `$script:LdSelfPath`. It's empty under `iex`.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** with `LaunchDeck v2: startup and elevation`.

### Task 3: Window, theme, background loader, icons, tools panel

**Interfaces:**
- Produces:
  - `New-LdWorkerPool` creates `$script:LdPool`. Its `InitialSessionState` includes every `*-Ld*` function and the variable `LdSync`.
  - `Start-LdWorker -ScriptBlock <sb> -ArgumentList <object[]>` returns the PowerShell handle, kept in `$script:LdWorkers`.
  - `Send-LdEvent -Type <string> -Data <object>`, used in workers.
  - Event types:
    - `Loaded`, with data `@{ Catalog; Tools; Installed; Winget = @{ Present; Version } }`
    - `LoadFailed`, with a message
    - `Icon`, with `@{ Key; Path }`
    - `ToolReady`, with a path
    - `ToolFailed`, with a message
  - `Get-LdVisibleIds -Catalog -Category <string> -Search <string>` returns `[string[]]`. A non-empty search ignores the category. Matching is a case-insensitive substring on Name. `All` returns every app.
  - `Test-LdImageFile -Path` returns `[bool]`. It loads the file with `BitmapDecoder`, and on failure deletes the file and returns `$false`.
  - `Get-LdThemeIsDark` returns `[bool]`, based on `HKCU:\…\Themes\Personalize\AppsUseLightTheme -eq 0`.

- [ ] **Step 1: Write the failing tests.**
  - `Get-LdVisibleIds`: the category filter; search across categories; `All`.
  - `Test-LdImageFile rejects text file`: a temp `.png` containing `<html>` → `$false`, and the file is gone. A real 1×1 PNG (base64 in the test) → `$true`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement the XAML window** to match mockup B and the spec's "Main window" section:
  - Theme brushes are chosen by `Get-LdThemeIsDark`.
  - Cards are `ToggleButton`s with a template: a 28 px icon over a letter placeholder, a name, and an `Installed` badge. Installed cards are disabled and unticked.
  - "All" sections have headers. Search switches to "All" and restores the previous category when cleared.
  - Select all / none act on visible, enabled cards only.
  - The counter text reads `{n} of {total} selected · {k} already installed`.
  - The install button reads `Install {n} apps` and is disabled at 0.
  - The title gets a ` — Practice mode` suffix when practicing.
- [ ] **Step 4: Implement loading.**
  - The `Loaded` handler starts a worker that runs, in order:
    - `Get-LdText` for apps.json and tools.json, where the local copy next to the script wins.
    - The API listing.
    - `Get-Command winget` and `winget --version`.
    - `winget export -o <temp> --accept-source-agreements --disable-interactivity`, then `ConvertFrom-LdWingetExport`.
  - The worker then sends `Loaded`.
  - A second worker downloads icons into `%LOCALAPPDATA%\LaunchDeck\icons\<safe-key>.img`. Each passes through `Test-LdImageFile` and is announced with `Icon`.
  - Tool click: a worker downloads to `%LOCALAPPDATA%\LaunchDeck\scripts\<file>`, then the UI runs `powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "<path>"`.
- [ ] **Step 5: Run the tests.** Expected: PASS. Then launch with `powershell.exe -NoProfile -File LaunchDeck.ps1 -Practice` and screenshot the window. Expected: the sidebar layout, real icons, already-installed badges, and the tools panel filled in.
- [ ] **Step 6: Commit** with `LaunchDeck v2: main window`.

### Task 4: Install engine, winget bootstrap, summary

**Interfaces:**
- Consumes: `Get-LdInstallResult`, `Send-LdEvent`, `Write-LdLog`.
- Produces:
  - `Invoke-LdInstallQueue -Practice <bool>`, run in a worker. It reads `$LdSync.Pending` (`ConcurrentQueue` of app objects) until it's empty or `$LdSync.StopAfterCurrent`. It sends:
    - `AppStatus` with `@{ Id; Status='Installing'|'Installed'|'AlreadyInstalled'|'Failed'; Note }`
    - `AppOutput` with `@{ Id; Line }`
    - `EngineDone`
  - In practice mode it sleeps a random 1–3 s per app. The third app processed fails once with Note `Simulated failure`, and its retry succeeds.
  - `Install-LdWinget` returns `[bool]`:
    1. `Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe`.
    2. Otherwise, take the latest `microsoft/winget-cli` release assets (`*.msixbundle` and `DesktopAppInstaller_Dependencies.zip`) and install the x64 dependencies, then the bundle.
    3. Refresh `PATH`.
  - The UI shows this as a "Setting up winget" row.

- [ ] **Step 1: Write the failing test.** `Invoke-LdInstallQueue practice`: queue 3 fake apps, call the function synchronously, then drain `$LdSync.Events`. Expected: 3 final `AppStatus` events (statuses Installed, Installed, Failed with `Simulated failure`) followed by `EngineDone`. Re-queue the failed app and run again → Installed. Set `StopAfterCurrent` with 2 queued → only 1 processed.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement the engine.**
  - The real path runs winget through `System.Diagnostics.Process`, with stdout and stderr redirected (UTF-8). It logs each non-progress line and maps the exit code with `Get-LdInstallResult`.
  - The install view sits in the same window: an overall bar ("Installing {i} of {n}"), per-app rows (icon, name, status, a mini indeterminate bar while installing, and Retry for failures), a "Show details" expander, "Open log", and "Stop after this app".
  - When it's done, a summary line shows the names, with "Back to list" (which re-runs the installed check) and "Close".
  - Closing mid-install asks a Yes/No question. Yes means stop after the current app, then close.
- [ ] **Step 4: Run the tests.** Expected: PASS. Then run the GUI in practice mode with 4 apps. Expected: a responsive window, one failure, Retry works, and the summary lists the names.
- [ ] **Step 5: Commit** with `LaunchDeck v2: install engine`.

### Task 5: Desktop shortcut button, README, retire old script

**Interfaces:**
- Produces:
  - `New-LdDesktopShortcut [-Desktop <string>]` returns the `.lnk` path.
    - It writes `%LOCALAPPDATA%\LaunchDeck\Launcher.ps1`. The launcher downloads `LaunchDeck.ps1` to `LaunchDeck.ps1.new`, moves it into place, falls back to the cached copy, shows a message box when there's neither, then runs `& $script`.
    - It downloads `scripts/assets/LaunchDeck.ico`.
    - It creates `LaunchDeck.lnk` targeting `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` with arguments `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<Launcher.ps1>"` and that icon.
  - `Get-LdShortcutDesktop` returns `[string]`: `[Environment]::GetFolderPath('Desktop')`, or `$env:PUBLIC\Desktop` when the console user (`Win32_ComputerSystem.UserName`) differs from the current user.

- [ ] **Step 1: Write the failing test.** `New-LdDesktopShortcut -Desktop <tempdir>` → the `.lnk` exists. Reading it back with `WScript.Shell`, `Arguments` contains `-File` and `Launcher.ps1`. The launcher file contains the raw `LaunchDeck.ps1` URL.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement it**, plus the footer button: "Add to desktop", which reads "On desktop ✓" when `LaunchDeck.lnk` exists, and clicking rebuilds it. Write `README.md`: the one-line command, the desktop button, and how to add an app or tool. `git rm "download LaunchDeck to dekstop from git.ps1"`.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** with `LaunchDeck v2: desktop shortcut button, README`.

### Task 6: Full verification

- [ ] Parse check: zero errors from `[Parser]::ParseFile`. The test harness: all PASS.
- [ ] Practice-mode GUI run in dark and in light (temporarily set `AppsUseLightTheme`, then restore it): screenshot both.
- [ ] Start paths:
  - `powershell.exe -File LaunchDeck.ps1 -Practice`.
  - `Get-Content LaunchDeck.ps1 -Raw | iex` in a non-admin shell. Expected: the plan is `DownloadThenElevate`. Verify by calling `Get-LdLaunchPlan` only; real elevation is a handoff check.
- [ ] Tools: each tool's URL downloads with HTTP 200, including "upgrade all".
- [ ] Hand off to the owner: a real elevated run and a UAC prompt, which they click.
