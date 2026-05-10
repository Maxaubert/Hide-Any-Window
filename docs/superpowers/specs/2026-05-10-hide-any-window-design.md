# Hide Any Window — Design (Phase A)

## Goal

A small Windows utility that fully hides the active window on a hotkey: invisible on screen, removed from the taskbar, removed from Alt-Tab. The user-facing target is hiding windows that resist normal "minimize to tray" tools — Windows Magnifier in particular — but the script must work on any window the OS lets us touch.

## Phased approach

This spec covers **Phase A only**. Phase A validates whether running the script as administrator is sufficient to hide UIAccess-elevated windows (specifically Magnifier). The result of Phase A determines whether Phase B is needed.

- **Phase A (this spec):** AHK v2 script run elevated. Cheap to build, answers the privilege question.
- **Phase B (deferred, only if A fails on Magnifier):** Compile to `.exe`, embed UIAccess manifest, sign with self-signed certificate trusted locally, install under `Program Files`. Same hide logic, higher privilege wrapper.
- **Phase C (deferred, future polish):** Tray menu listing hidden windows, persistent config, autostart at boot, automatic hide-Magnifier-at-startup.

## Architecture

A single AutoHotkey v2 script (`hide-any-window.ahk`) launched with administrator privileges. No separate processes, no IPC, no config file in Phase A.

## Components

1. **Hidden-window stack** — global array of `{hwnd, originalExStyle}` records in hide order; last item is most recently hidden. Storing the original extended style alongside the HWND lets restore put the window back exactly how it was, even if the user hid it twice in different states.
2. **`HideActiveWindow()`** — gets the foreground HWND, removes `WS_EX_APPWINDOW`, adds `WS_EX_TOOLWINDOW`, calls `WinHide`, verifies the window is no longer visible, then pushes the HWND onto the stack.
3. **`RestoreLastWindow()`** — pops HWNDs off the stack until it finds one that still exists; reverses the extended-style changes, calls `WinShow`, activates the window.
4. **Hotkey bindings**
   - `Win+H` (`#h`) → `HideActiveWindow()`
   - `Win+Shift+H` (`#+h`) → `RestoreLastWindow()`
5. **Default AHK tray icon** — provides only an "Exit" option. No window list in Phase A.

## Why style flips, not just `WinHide`

`WinHide` makes a window invisible but does not reliably remove it from the taskbar or Alt-Tab. The taskbar shows windows with `WS_EX_APPWINDOW` set OR no owner and no `WS_EX_TOOLWINDOW`. Setting `WS_EX_TOOLWINDOW` and clearing `WS_EX_APPWINDOW` before hiding is what removes the window from the switcher and taskbar in addition to the screen.

## Data flow

**Hide:**
1. User presses `Win+H`.
2. Script reads foreground HWND via `WinExist("A")`.
3. Script reads current extended style.
4. Script sets `WS_EX_TOOLWINDOW`, clears `WS_EX_APPWINDOW`.
5. Script calls `WinHide`.
6. Script re-checks visibility via `DllCall("IsWindowVisible", "Ptr", hwnd)`.
7. If invisible: push HWND (and original style) onto stack. If still visible: do not push, show failure tooltip, log to file.

**Restore:**
1. User presses `Win+Shift+H`.
2. Script pops the top entry off the stack.
3. If HWND no longer exists (`!WinExist("ahk_id " hwnd)`), pop the next entry; repeat until live or empty.
4. Restore the original extended style.
5. Call `WinShow`.
6. Activate the window via `WinActivate`.

## Error handling

- **Hide failure** (admin not enough — likely Magnifier): tray tooltip `"Couldn't hide [Title] — UIAccess required. Phase B needed."`. Append window class + title + timestamp to `hide-failures.log` next to the script. Do not push the HWND to the stack.
- **Restore on dead HWND**: silently pop and try the next stack entry. If stack empties, do nothing.
- **Restore failure** (style restore or `WinShow` returns but window stays invisible): show tooltip `"Restore failed for [Title]"`; leave the entry off the stack so the user can retry by other means or kill the script.

## Testing plan

Manual test, in order. Each test should be run twice in succession (hide → restore → hide → restore) to confirm both directions are repeatable.

1. **Notepad** — baseline. Validates the script logic itself.
2. **Calculator (UWP)** — validates UWP/WinUI window handling.
3. **Task Manager** — validates admin-vs-admin (Task Manager runs elevated).
4. **Windows Magnifier** — the validation that decides Phase A's verdict.
   - Test in Lens mode and Full-screen mode separately.
   - ✅ Hides cleanly → Phase A is the final solution.
   - ❌ Doesn't hide → tooltip and log fire as designed; we have evidence to proceed to Phase B.

## Out of scope for Phase A

- Persistence across script restart
- Autostart at boot
- Automatically hiding Magnifier on launch
- Tray menu listing hidden windows
- Config file or settings UI
- Restoring a specific window (only LIFO)
- Restoring all hidden windows at once
- UIAccess manifest, code signing, compiled `.exe` distribution

These are deferred to Phase B/C and are not needed to answer the question Phase A is built to answer.
