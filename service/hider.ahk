; Win32 constants for window styles.
GWL_EXSTYLE := -20
WS_EX_APPWINDOW  := 0x00040000
WS_EX_TOOLWINDOW := 0x00000080

; TryHideWindow(hwnd) -> Map("ok", bool, "exStyle", UInt-when-ok, "reason", String-when-not-ok)
;   On success, hides the window and returns the original exStyle so caller can record it.
;   On failure (e.g. UIAccess restriction), rolls back the style change.
TryHideWindow(hwnd) {
    global GWL_EXSTYLE, WS_EX_APPWINDOW, WS_EX_TOOLWINDOW

    if !WinExist("ahk_id " hwnd)
        return Map("ok", false, "reason", "window-does-not-exist")

    exStyle := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
    newExStyle := (exStyle & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW
    DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", newExStyle)

    WinHide("ahk_id " hwnd)

    stillVisible := DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
    if (stillVisible) {
        DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", exStyle)
        return Map("ok", false, "reason", "uiaccess-or-elevated-target")
    }
    return Map("ok", true, "exStyle", exStyle)
}

; RestoreWindowFromEntry(entry) -> bool
;   entry: Map("hwnd", UInt, "exStyle", UInt, ...)
;   Returns true if the window still existed and was restored.
RestoreWindowFromEntry(entry) {
    global GWL_EXSTYLE
    hwnd := entry["hwnd"]
    if !WinExist("ahk_id " hwnd)
        return false
    DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", entry["exStyle"])
    WinShow("ahk_id " hwnd)
    return true
}
