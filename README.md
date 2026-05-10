# Hide Any Window

A Windows utility that fully hides any configured app's window — invisible on
screen, removed from the taskbar, removed from Alt-Tab — automatically and in
the background.

The motivating use case is hiding windows that resist normal "minimize to
tray" tools, with **Windows Magnifier** as the canonical hard target.

## Architecture

Two cooperating pieces, sharing a single JSON config file:

- **Service** (`service/`) — AutoHotkey v2 script that runs in the background.
  Watches `%APPDATA%\HideAnyWindow\config.json` for changes, hooks
  `EVENT_OBJECT_SHOW` so any matching new window is hidden the moment it
  appears, and uses `ITaskbarList::DeleteTab` to drop the window's taskbar
  button. **Implemented and validated.** See
  `docs/superpowers/specs/2026-05-10-hide-any-window-phase-b-design.md` and
  `docs/superpowers/plans/2026-05-10-hide-any-window-phase-b-service.md`.

- **Manager** (planned) — WinUI 3 / .NET app that lets you add or remove
  rules from a process picker, toggle each rule on/off, and stop or start
  the service. Plan B-2 (separate spec/plan to be written).

## Requirements

- Windows 10 or 11
- [AutoHotkey v2.0+](https://www.autohotkey.com/) — install includes
  `AutoHotkey64_UIA.exe` which is the variant we use.

## Running the service (development)

The service must run with **UIAccess** privileges to hide UIAccess-elevated
windows like Magnifier. AHK ships a UIAccess-signed variant in its install
directory (typically `C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe`),
so no UAC prompt and no compilation needed.

From PowerShell:

```powershell
Start-Process "C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe" `
  -ArgumentList '"C:\path\to\Hide-Any-Window\service\main.ahk"'
```

Or create a shortcut whose target is that command line and pin it to Start.
The service is silent — it logs to `%APPDATA%\HideAnyWindow\service.log`.

For the eventual standalone-binary distribution, the service will be compiled
to a UIAccess-manifested `.exe` (`Ahk2Exe` + manifest + signing) so users
don't need an AHK install. See the design doc.

## Configuration

Until the manager UI ships, edit `%APPDATA%\HideAnyWindow\config.json`
directly. Schema:

```json
{
  "schemaVersion": 1,
  "serviceState": "running",
  "rules": [
    { "id": "magnify-exe", "exe": "magnify.exe", "name": "Magnifier", "enabled": true }
  ]
}
```

| Field | Notes |
|---|---|
| `serviceState` | `"running"` or `"stopped"` — flipping to `"stopped"` restores all hidden windows and pauses auto-hide. |
| `rules[].exe` | Process executable basename, case-insensitive. |
| `rules[].enabled` | `true` actively hides matches; `false` keeps the rule in place but doesn't act. |

Edits are picked up within ~1s by the service's file watcher.

## Validation results — Phase B service

Tested on Windows 11 Pro 10.0.26200, AutoHotkey v2.x, service launched via
`AutoHotkey64_UIA.exe`.

| # | Scenario | Result |
|---|---|---|
| 1 | Service starts with no `config.json` | ✅ Logs "config.json missing — using defaults", idles |
| 2 | Pre-existing Magnifier hides on rule add | ✅ Hidden within 1s of config write |
| 3 | New Magnifier window hides on appearance (hook) | ✅ Multiple Magnifier reopens caught (`hooked-hide` log entries) |
| 7 | Crash recovery from `hidden.json` | ✅ "found 1 orphan hidden windows from a prior run — restoring" |
| 8 | Live config edit picked up by file watcher | ✅ "config.json changed — reapplying" |
| 10 | Single-instance via named mutex | ✅ Validated when AHK auto-restarted on second launch |
| — | Taskbar button removed (`ITaskbarList::DeleteTab`) | ✅ User-confirmed: window invisible AND taskbar entry gone |

Tests 4 (toggle rule off → restore), 5 (`serviceState: stopped` → pause), 6
(resume), and 9 (picker dedupe) require the manager UI or scripted config
manipulation; deferred to Plan B-2 testing.

## Files

```
service/
  main.ahk         entry point: bootstrap, hook, watcher, mutex
  log.ahk          ServiceLog helper
  config.ahk       JSON config loader
  registry.ahk     in-memory hidden-window registry + hidden.json I/O
  hider.ahk        TryHideWindow / RestoreWindowFromEntry + ITaskbarList
  lib/JSON.ahk     vendored thqby JSON library (MIT)
  test/            ad-hoc test scripts for pure-logic modules
docs/superpowers/
  specs/           design docs
  plans/           implementation plans
```
