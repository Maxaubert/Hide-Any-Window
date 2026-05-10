# Hide Any Window — Phase A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single AutoHotkey v2 script that fully hides the active window (invisible + off taskbar + off Alt-Tab) on `Win+H`, and restores the most recently hidden window on `Win+Shift+H`. Validate whether running elevated (admin) is sufficient to hide Windows Magnifier.

**Architecture:** Single `.ahk` file run as administrator. Global LIFO stack of `{hwnd, originalExStyle}` records. Hide flow flips `WS_EX_APPWINDOW`/`WS_EX_TOOLWINDOW` extended-style bits then calls `WinHide`; restore reverses both. Hide failure on UIAccess windows (e.g., Magnifier) is detected by re-querying `IsWindowVisible` after `WinHide` and not pushing to the stack if the call had no effect.

**Tech Stack:** AutoHotkey v2.0+, Windows 10/11, git for version control. No external libraries.

**Note on testing:** This script's job is to manipulate real OS windows. There is no realistic way to unit-test that — a fake "window" object would test the test harness, not the script. So "tests" in this plan are concrete manual verification procedures with explicit pass/fail criteria. Each task that touches behavior includes such a procedure. The Phase A verdict (does admin suffice for Magnifier?) is delivered by the Task 6 validation matrix.

---

## File Structure

- `hide-any-window.ahk` — the entire script (script header, hotkey bindings, `HideActiveWindow`, `RestoreLastWindow`, helpers, the global stack).
- `README.md` — install + run instructions, hotkeys, known limitations.
- `.gitignore` — exclude `hide-failures.log` (created at runtime).
- `hide-failures.log` — created at runtime when admin is insufficient to hide a window. Not committed.

Single-file script is appropriate here — Phase A is small enough that splitting modules would be premature.

---

## Task 1: Project scaffolding

**Files:**
- Create: `README.md`
- Create: `.gitignore`
- Create: `hide-any-window.ahk`
- Init: git repo at project root

- [ ] **Step 1: Initialize the git repo**

Run from `C:\Users\Admin\Documents\Claude\Github\Hide-Any-Window`:

```powershell
git init
git branch -M main
```

Expected: `Initialized empty Git repository in ...`. `git status` shows "On branch main, No commits yet."

- [ ] **Step 2: Create `.gitignore`**

```gitignore
# Runtime log produced when admin privilege is insufficient to hide a window
hide-failures.log

# AHK build artifacts (only relevant in later phases that compile to .exe)
*.exe
*.bin
```

- [ ] **Step 3: Create `README.md`**

```markdown
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
```

- [ ] **Step 4: Create the script skeleton**

`hide-any-window.ahk`:

```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Force

; ---------------------------------------------------------------------------
; Hide Any Window — Phase A
; Hotkeys:
;   Win+H        Hide the active window
;   Win+Shift+H  Restore the most recently hidden window (LIFO)
; ---------------------------------------------------------------------------

; Stack of hidden windows. Each entry: { hwnd: <UInt>, exStyle: <UInt>, title: <String> }
HiddenStack := []

; Bindings — implementations added in later tasks.
#h::HideActiveWindow()
#+h::RestoreLastWindow()

HideActiveWindow() {
    ; Implemented in Task 2.
}

RestoreLastWindow() {
    ; Implemented in Task 3.
}
```

- [ ] **Step 5: Verify the skeleton runs without errors**

Double-click `hide-any-window.ahk`. Expected: a green "H" AHK icon appears in the system tray. Pressing `Win+H` does nothing visible (function body is empty). Right-click the tray icon → Exit to stop.

If the script fails to launch with a syntax error, fix it before continuing.

- [ ] **Step 6: Commit**

```powershell
git add .gitignore README.md hide-any-window.ahk
git commit -m "scaffold: repo, gitignore, README, AHK script skeleton"
```

---

## Task 2: Implement `HideActiveWindow` (without stack yet)

**Files:**
- Modify: `hide-any-window.ahk` — replace the empty `HideActiveWindow()` body.

The aim is to hide the active window so it disappears from the screen, the taskbar, and Alt-Tab. We won't push to the stack yet (Task 3 adds that). Restoring is not yet possible — to recover Notepad in this task's verification, we kill it from Task Manager.

- [ ] **Step 1: Add Win32 extended-style constants near the top of the file**

Insert just below `HiddenStack := []`:

```autohotkey
; Win32 GetWindowLong / SetWindowLong index for extended style.
GWL_EXSTYLE := -20

; Extended-style bits relevant to taskbar/Alt-Tab presence.
WS_EX_APPWINDOW  := 0x00040000  ; Force a top-level window onto the taskbar.
WS_EX_TOOLWINDOW := 0x00000080  ; Tool window — does not appear in taskbar or Alt-Tab.
```

- [ ] **Step 2: Implement `HideActiveWindow()`**

Replace the empty body with:

```autohotkey
HideActiveWindow() {
    global GWL_EXSTYLE, WS_EX_APPWINDOW, WS_EX_TOOLWINDOW

    hwnd := WinExist("A")
    if (!hwnd)
        return

    title := WinGetTitle("ahk_id " hwnd)
    exStyle := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")

    ; Clear WS_EX_APPWINDOW, set WS_EX_TOOLWINDOW so the window leaves the taskbar/Alt-Tab.
    newExStyle := (exStyle & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW
    DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", newExStyle)

    WinHide("ahk_id " hwnd)
}
```

- [ ] **Step 3: Manual verification — Notepad**

1. Save the script. Right-click → Run as administrator. (Confirm UAC.)
2. Open Notepad. Type a few characters so the window has identifiable content.
3. With Notepad focused, press `Win+H`.
4. Expected, all of:
   - Notepad window disappears from the screen.
   - Notepad is gone from the taskbar.
   - Press Alt-Tab — Notepad is not in the switcher.
5. Open Task Manager → Details tab → find `notepad.exe`. It should still be running.
6. End the `notepad.exe` process to clean up (Task 3 adds the proper restore).

If any sub-bullet of step 4 fails, debug before continuing. Likely culprits: AHK not running elevated; misspelled style constants; `hwnd` was 0 because no window was foreground.

- [ ] **Step 4: Commit**

```powershell
git add hide-any-window.ahk
git commit -m "feat: hide active window via WinHide + WS_EX_TOOLWINDOW"
```

---

## Task 3: Add the hidden-window stack and `RestoreLastWindow`

**Files:**
- Modify: `hide-any-window.ahk`

- [ ] **Step 1: Push to the stack at the end of `HideActiveWindow`**

Add as the last line inside `HideActiveWindow()` (after `WinHide(...)`):

```autohotkey
    HiddenStack.Push({ hwnd: hwnd, exStyle: exStyle, title: title })
```

(Note: storing the *original* `exStyle`, not `newExStyle` — restore needs to put the window back the way it was.)

`HideActiveWindow` now reads in full:

```autohotkey
HideActiveWindow() {
    global GWL_EXSTYLE, WS_EX_APPWINDOW, WS_EX_TOOLWINDOW, HiddenStack

    hwnd := WinExist("A")
    if (!hwnd)
        return

    title := WinGetTitle("ahk_id " hwnd)
    exStyle := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")

    newExStyle := (exStyle & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW
    DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", newExStyle)

    WinHide("ahk_id " hwnd)
    HiddenStack.Push({ hwnd: hwnd, exStyle: exStyle, title: title })
}
```

- [ ] **Step 2: Implement `RestoreLastWindow()`**

Replace the empty body with:

```autohotkey
RestoreLastWindow() {
    global GWL_EXSTYLE, HiddenStack

    if (HiddenStack.Length = 0)
        return

    entry := HiddenStack.Pop()

    ; Restore the original extended style.
    DllCall("SetWindowLongPtr", "Ptr", entry.hwnd, "Int", GWL_EXSTYLE, "Ptr", entry.exStyle)

    WinShow("ahk_id " entry.hwnd)
    WinActivate("ahk_id " entry.hwnd)
}
```

- [ ] **Step 3: Manual verification — single hide/restore on Notepad**

1. Reload the script (right-click tray icon → Reload, or exit and re-launch as admin).
2. Open Notepad. Focus it. Press `Win+H`.
3. Expected: Notepad disappears from screen + taskbar + Alt-Tab.
4. Press `Win+Shift+H`.
5. Expected: Notepad reappears on screen, on the taskbar, and is the active window. The window's title bar text matches what it was before hiding.

- [ ] **Step 4: Manual verification — multiple windows, LIFO order**

1. Open Notepad and rename via Save As to `A.txt`. Open another Notepad as `B.txt`. Open a third as `C.txt`.
2. Focus A → `Win+H`. Focus B → `Win+H`. Focus C → `Win+H`. All three should be gone from screen/taskbar/Alt-Tab.
3. Press `Win+Shift+H` once. Expected: C reappears (most recently hidden).
4. Press `Win+Shift+H` again. Expected: B reappears.
5. Press `Win+Shift+H` again. Expected: A reappears.
6. Press `Win+Shift+H` once more. Expected: nothing happens (stack is empty), no error tooltip, no crash.

- [ ] **Step 5: Commit**

```powershell
git add hide-any-window.ahk
git commit -m "feat: hidden-window stack and LIFO restore"
```

---

## Task 4: Detect hide failure (UIAccess windows) and warn the user

**Files:**
- Modify: `hide-any-window.ahk`

The pivotal Phase A behaviour: when the script lacks the privilege to hide a window (Magnifier is the expected case), `WinHide` returns silently. We must detect the no-op and (a) not push the entry to the stack, (b) tell the user, (c) log it for evidence.

- [ ] **Step 1: Add a logging helper near the top of the script (just below the constants)**

```autohotkey
LogHideFailure(hwnd, title) {
    cls := WinGetClass("ahk_id " hwnd)
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    line := timestamp " | hwnd=" hwnd " | class=" cls " | title=" title "`r`n"
    FileAppend(line, A_ScriptDir "\hide-failures.log")
}
```

- [ ] **Step 2: Modify `HideActiveWindow` to verify visibility after `WinHide`**

Replace the body of `HideActiveWindow()` with:

```autohotkey
HideActiveWindow() {
    global GWL_EXSTYLE, WS_EX_APPWINDOW, WS_EX_TOOLWINDOW, HiddenStack

    hwnd := WinExist("A")
    if (!hwnd)
        return

    title := WinGetTitle("ahk_id " hwnd)
    exStyle := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")

    newExStyle := (exStyle & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW
    DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", newExStyle)

    WinHide("ahk_id " hwnd)

    ; Verify the window actually went invisible. UIAccess windows (e.g. Magnifier)
    ; will silently ignore WinHide unless our script has equal or higher privilege.
    stillVisible := DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
    if (stillVisible) {
        ; Roll back the style change so we don't leave the window in a half-modified state.
        DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", exStyle)
        ToolTip("Couldn't hide " title " — UIAccess required. Phase B needed.")
        SetTimer(() => ToolTip(), -3000)
        LogHideFailure(hwnd, title)
        return
    }

    HiddenStack.Push({ hwnd: hwnd, exStyle: exStyle, title: title })
}
```

- [ ] **Step 3: Manual verification — failure path with a non-elevated script run**

(We deliberately run the script *without* admin so we can trigger the failure path on a known-protected target. After this verification we go back to running elevated.)

1. Exit the running script.
2. Double-click `hide-any-window.ahk` (no "Run as administrator").
3. Open Task Manager (which is elevated).
4. Focus Task Manager. Press `Win+H`.
5. Expected:
   - Task Manager stays visible.
   - A tray tooltip appears: "Couldn't hide Task Manager — UIAccess required. Phase B needed." It disappears after ~3 seconds.
   - `hide-failures.log` exists in the script directory and contains a line with the current timestamp, an `hwnd=`, `class=TaskManagerWindow` (or similar), and `title=Task Manager`.
6. Exit the script. Re-launch as administrator for subsequent tasks.

- [ ] **Step 4: Manual verification — success path is unaffected**

1. (Running as admin again.) Open Notepad. Press `Win+H` → Notepad hides cleanly. `Win+Shift+H` restores it. No tooltip, no log entry added.
2. Confirm `hide-failures.log` did NOT gain a new line for the Notepad hide.

- [ ] **Step 5: Commit**

```powershell
git add hide-any-window.ahk
git commit -m "feat: detect hide failure (UIAccess), tooltip + log, roll back style"
```

---

## Task 5: Skip dead HWNDs during restore

**Files:**
- Modify: `hide-any-window.ahk`

If the user closes the underlying app (or it crashes) while hidden, its HWND becomes invalid. `RestoreLastWindow` should not try to operate on a dead HWND — it should silently pop and try the next entry.

- [ ] **Step 1: Update `RestoreLastWindow` to loop**

Replace the body of `RestoreLastWindow()` with:

```autohotkey
RestoreLastWindow() {
    global GWL_EXSTYLE, HiddenStack

    while (HiddenStack.Length > 0) {
        entry := HiddenStack.Pop()

        ; Skip dead HWNDs (window was destroyed while hidden).
        if (!WinExist("ahk_id " entry.hwnd))
            continue

        DllCall("SetWindowLongPtr", "Ptr", entry.hwnd, "Int", GWL_EXSTYLE, "Ptr", entry.exStyle)
        WinShow("ahk_id " entry.hwnd)
        WinActivate("ahk_id " entry.hwnd)
        return
    }
    ; Stack drained without finding a live window — silently do nothing.
}
```

- [ ] **Step 2: Manual verification — closing a hidden window does not break restore**

1. Reload the script.
2. Open Notepad twice — call them N1 and N2.
3. Hide N1 (`Win+H`). Hide N2 (`Win+H`). Both gone.
4. Open Task Manager → Details → end the `notepad.exe` process belonging to N2. (You can identify it by PID; if unsure, end whichever was opened second.)
5. Press `Win+Shift+H`.
6. Expected: nothing flashes, no error, and N1 reappears (the loop popped the dead N2, then popped and restored N1).
7. Press `Win+Shift+H` again. Expected: nothing happens (stack empty).

- [ ] **Step 3: Commit**

```powershell
git add hide-any-window.ahk
git commit -m "feat: skip dead HWNDs during restore"
```

---

## Task 6: Phase A validation matrix (the actual question this project answers)

**Files:**
- Modify: `README.md` — append a "Phase A validation results" section.

This task isn't code — it's the experiment. We run a fixed test matrix and record results. The Magnifier rows determine whether Phase A is the final solution or whether we proceed to Phase B.

Run the script as administrator before each test. Reload the script (or re-launch elevated) between tests so the stack starts empty.

- [ ] **Step 1: Run the matrix and record results**

For each target below, record: did it disappear from screen + taskbar + Alt-Tab on `Win+H`? Did it reappear correctly on `Win+Shift+H`? Did `hide-failures.log` get a line?

| # | Target | How to launch | Expected hide | Expected restore |
|---|---|---|---|---|
| 1 | Notepad | Start menu → Notepad | Vanishes everywhere | Reappears, focused |
| 2 | Calculator (UWP) | Start menu → Calculator | Vanishes everywhere | Reappears, focused |
| 3 | Task Manager | Ctrl+Shift+Esc | Vanishes everywhere | Reappears, focused |
| 4a | Magnifier — Lens mode | Run `magnify`, switch to Lens via Ctrl+Alt+L | Lens vanishes, magnification ceases | Lens reappears |
| 4b | Magnifier — Full-screen mode | Run `magnify`, Ctrl+Alt+F | Full-screen overlay vanishes | Overlay reappears |

- [ ] **Step 2: Append the results to `README.md`**

Add this section at the end of `README.md`, filled in with what actually happened:

```markdown
## Phase A validation results

Tested on Windows 11 Pro (version `winver`), AutoHotkey v2.x, script run as administrator.

| Target | Hide | Restore | Notes |
|---|---|---|---|
| Notepad | ✅ / ❌ | ✅ / ❌ | |
| Calculator (UWP) | ✅ / ❌ | ✅ / ❌ | |
| Task Manager | ✅ / ❌ | ✅ / ❌ | |
| Magnifier — Lens | ✅ / ❌ | ✅ / ❌ | |
| Magnifier — Full-screen | ✅ / ❌ | ✅ / ❌ | |

**Verdict:**
- If both Magnifier rows are ✅ → Phase A is sufficient. Phase B is unnecessary.
- If either Magnifier row is ❌ → admin is not enough; proceed to Phase B
  (UIAccess manifest + signed `.exe`). The `hide-failures.log` from this run
  is the evidence.
```

- [ ] **Step 3: Commit**

```powershell
git add README.md
git commit -m "docs: phase A validation matrix and results"
```

---

## Self-review summary

- **Spec coverage:** Architecture (Task 1, 2), components 1–4 (Tasks 1–3), Win32 style flips (Task 2), data flow hide/restore (Tasks 2, 3), error handling for hide failure + tooltip + log (Task 4), error handling for dead HWND (Task 5), test plan (Task 2 step 3, Task 3 steps 3–4, Task 5 step 2, full matrix Task 6). Tray default exit option is the AHK default and needs no code (Task 1 verification confirms tray icon appears). Out-of-scope items remain out of scope. ✅
- **Placeholders:** None — every step has explicit code or commands. ✅
- **Type/name consistency:** `HiddenStack` is the same array everywhere; entries always have fields `hwnd`, `exStyle`, `title`; `GWL_EXSTYLE`, `WS_EX_APPWINDOW`, `WS_EX_TOOLWINDOW` declared once and referenced via `global` in both functions. ✅
