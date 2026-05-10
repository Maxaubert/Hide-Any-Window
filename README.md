# Hide Any Window

A small AutoHotkey v2 script that fully hides the active window on a hotkey:
invisible on screen, removed from the taskbar, removed from Alt-Tab.

The motivating use case is hiding windows that resist normal "minimize to tray"
tools — Windows Magnifier in particular.

## Status

Phase A: validates whether running the script as administrator is sufficient
to hide UIAccess-elevated windows like Magnifier. If admin is not enough, see
`docs/superpowers/specs/2026-05-10-hide-any-window-design.md` for the planned
Phase B (UIAccess manifest + signed `.exe`).

## Hotkeys

- `Win+H` — hide the active window
- `Win+Shift+H` — restore the most recently hidden window (LIFO)

## Requirements

- Windows 10 or 11
- [AutoHotkey v2.0+](https://www.autohotkey.com/)

## Running

Right-click `hide-any-window.ahk` → **Run as administrator**.

Without admin privileges, the script will run but will fail to hide many
elevated windows. A tray tooltip will appear in that case and the failure
will be logged to `hide-failures.log`.

## Known limitation (Phase A)

Hidden windows are unreachable while hidden — they're off the taskbar and
off Alt-Tab. Restoration is LIFO via `Win+Shift+H` only. If the script
exits while windows are hidden, those windows remain in their hidden state
until you log out or reopen the script and find them via another means.
