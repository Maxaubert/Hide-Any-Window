---
name: ahk-service
description: Use when editing or debugging the AutoHotkey v2 service in service/ (window hiding/restoring, the SetWinEventHook callback, the liveness mutex, config polling, or hidden.json crash recovery). Carries the AHK-v2-specific conventions and lifecycle this code depends on.
---

# Hide Any Window — the AHK v2 service

The service is a compiled AutoHotkey v2 script that hides windows of configured apps and
restores them on demand. Entry point: `service\main.ahk`.

## File map

| File | Role |
|---|---|
| `main.ahk` | Bootstrap, liveness mutex, `SetWinEventHook` + callback, startup scan, 1 Hz config-mtime watcher, pause/resume, orphan recovery, shutdown restore. |
| `hider.ahk` | `TryHideWindow` / `RestoreWindowFromEntry`; lazy `ITaskbarList` COM; taskbar tab add/remove; ex-style toggling. |
| `config.ahk` | `GetDefaultConfig`, `GetConfigPath`, `LoadConfig` (parse + validate + default fallback). |
| `registry.ahk` | In-memory `HiddenEntries` + `hidden.json` persistence (add / remove / drain / load). |
| `log.ahk` | Append timestamped lines to `service.log`. |
| `lib\JSON.ahk` | Vendored thqby/HotKeyIt JSON parser (v1.0.8). |

## How hiding works

1. `SetWinEventHook(EVENT_OBJECT_SHOW)` fires when any window shows.
2. The callback resolves the window's process exe, matches it against enabled rules,
   skips the self-hide denylist (`hideanywindowmanager.exe`), then `TryHideWindow`.
3. `TryHideWindow` saves the original ex-style, switches `WS_EX_APPWINDOW`→`WS_EX_TOOLWINDOW`,
   `WinHide`s, and removes the taskbar tab via `ITaskbarList::DeleteTab`.
4. The hidden window + its original ex-style are recorded in `hidden.json` so a crashed
   service can restore them on next start (`RecoverOrphanHiddenWindows`).

On graceful exit (`OnExit`), the hook is removed BEFORE windows are restored — restoring
first would re-fire `EVENT_OBJECT_SHOW` and immediately re-hide them.

## AHK v2 conventions used here — keep them

- `#Warn All, Off` at the top of `main.ahk` is deliberate: it silences false-positive
  "LocalSameAsGlobal" warnings for legitimate cross-file function calls. Don't turn it back on.
- `config.ahk` / `registry.ahk` INLINE the `A_AppData . "\HideAnyWindow\..."` path instead of
  calling a shared helper, for the same warning-avoidance reason.
- Handles (`hwnd`, ex-style) round-trip through JSON as integers; compare with care.

## Contracts shared with the C# manager (don't drift)

- Mutex name: `HideAnyWindow_Service_Running`.
- Config: `%APPDATA%\HideAnyWindow\config.json`, camelCase keys
  (`schemaVersion`, `serviceState`, `rules[]` where each rule has `id`, `exe`, `enabled`).
- The manager polls liveness via the mutex and writes config; the service polls config mtime.

## Testing

`service\test\test_*.ahk` are standalone scripts: `MsgBox` the result, `ExitApp 0/1`. Run:

    & "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" service\test\test_config.ahk

They are interactive and run against the real `%APPDATA%\HideAnyWindow` files — there is no
sandbox yet. The riskiest code (`main.ahk` callback, `hider.ahk`) has no tests. See
`docs/AUDIT-2026-05.md` for the recommended non-interactive, sandboxed test approach and
the open service bugs (mutex/`#SingleInstance` interaction, callback try/catch, DESTROY
pruning, atomic `hidden.json` write).
