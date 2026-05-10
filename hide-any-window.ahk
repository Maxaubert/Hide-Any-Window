#Requires AutoHotkey v2.0
#SingleInstance Force

; Required so WinExist/WinActivate can find windows AFTER we have hidden them
; with WinHide. Without this, RestoreLastWindow's WinExist check returns 0 for
; every hidden entry and the restore loop silently drains the stack.
DetectHiddenWindows true

; ---------------------------------------------------------------------------
; Hide Any Window — Phase A
; Hotkeys:
;   Win+H        Hide the active window
;   Win+Shift+H  Restore the most recently hidden window (LIFO)
; ---------------------------------------------------------------------------

; Stack of hidden windows. Each entry: { hwnd: <UInt>, exStyle: <UInt>, title: <String> }
HiddenStack := []

; Win32 GetWindowLong / SetWindowLong index for extended style.
GWL_EXSTYLE := -20

; Extended-style bits relevant to taskbar/Alt-Tab presence.
WS_EX_APPWINDOW  := 0x00040000  ; Force a top-level window onto the taskbar.
WS_EX_TOOLWINDOW := 0x00000080  ; Tool window — does not appear in taskbar or Alt-Tab.

LogHideFailure(hwnd, title) {
    cls := WinGetClass("ahk_id " hwnd)
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    line := timestamp " | hwnd=" hwnd " | class=" cls " | title=" title "`r`n"
    FileAppend(line, A_ScriptDir "\hide-failures.log")
}

; Bindings — implementations added in later tasks.
#h::HideActiveWindow()
#+h::RestoreLastWindow()

HideActiveWindow() {
    global GWL_EXSTYLE, WS_EX_APPWINDOW, WS_EX_TOOLWINDOW, HiddenStack

    hwnd := WinExist("A")
    if (!hwnd)
        return

    title := WinGetTitle("ahk_id " hwnd)
    exStyle := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")

    ; Clear WS_EX_APPWINDOW, set WS_EX_TOOLWINDOW so the window leaves the taskbar/Alt-Tab.
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
