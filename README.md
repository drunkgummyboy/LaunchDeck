# LaunchDeck

Set up a Windows PC in a few clicks: tick the apps you want, install them with winget, and run
helper scripts from this repo.

## Start it

On any Windows 10/11 PC, open PowerShell and type:

```powershell
irm is.gd/launchdeck | iex
```

`is.gd/launchdeck` is a short link to `LaunchDeck.ps1` on GitHub. If it ever stops working, use the full address:

```powershell
irm https://raw.githubusercontent.com/drunkgummyboy/LaunchDeck/main/LaunchDeck.ps1 | iex
```

LaunchDeck asks for admin rights once, then opens. Click **Add to desktop** (bottom left) to get a
desktop shortcut that always starts the newest version from GitHub.

To try it without installing anything, run it from a copy of this repo in **practice mode**:

```powershell
powershell -ExecutionPolicy Bypass -File LaunchDeck.ps1 -Practice
```

## Add an app

Add a line to `"apps"` in [apps.json](apps.json):

```json
{ "name": "VLC", "id": "VideoLAN.VLC", "category": "Media", "icon": "videolan.org" }
```

- `id` is the winget ID with the exact capital letters. Check it with `winget show --id <id> --exact`.
- `icon` is the app's website. LaunchDeck shows that site's icon.
- For Microsoft Store apps, add `"source": "msstore"`.
- Categories appear in the order of the `"categories"` list. Presets list the IDs they tick, and `"*"` means every app.

## Add a tool

Put the `.ps1` file in [scripts/](scripts). It shows up on the right automatically. For a nicer name,
a description or an icon, add a line to [tools.json](tools.json):

```json
{ "file": "upgrade all.ps1", "name": "Upgrade all", "description": "Update every installed app with winget" }
```

## Logs and tests

- Every run writes a log to `C:\ProgramData\LaunchDeck\logs` (practice mode: `%TEMP%\LaunchDeck`).
  The **Open log** button opens it.
- Tests: `powershell -NoProfile -File tests\LaunchDeck.Tests.ps1`
- Screenshot of the window without showing it: `powershell -NoProfile -File tests\Snap-LaunchDeck.ps1`
