; Win32 constants for window styles.
GWL_EXSTYLE := -20
WS_EX_APPWINDOW  := 0x00040000
WS_EX_TOOLWINDOW := 0x00000080

; ITaskbarList COM pointer — initialized lazily on first use, kept for the
; life of the process. WinHide does not always trigger the shell to drop
; an existing taskbar button — particularly for UIAccess windows like
; Magnifier where shell-hook notifications from the elevated UIAccess
; window don't reliably reach the user's non-elevated taskbar. We call
; ITaskbarList::DeleteTab explicitly to force the removal.
global TaskbarListPtr := 0

InitTaskbarList() {
    global TaskbarListPtr
    if TaskbarListPtr
        return TaskbarListPtr

    ; STA init — shell COM objects require apartment-threaded mode.
    ; S_FALSE (1) is returned if COM is already initialized in this mode;
    ; both S_OK and S_FALSE are fine for our purposes.
    DllCall("ole32\CoInitializeEx", "Ptr", 0, "UInt", 0x2)

    ; CLSID_TaskbarList, IID_ITaskbarList
    clsid := Buffer(16)
    iid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "WStr", "{56FDF344-FD6D-11D0-958A-006097C9A090}", "Ptr", clsid)
    DllCall("ole32\CLSIDFromString", "WStr", "{56FDF342-FD6D-11D0-958A-006097C9A090}", "Ptr", iid)

    ptr := 0
    ; CLSCTX_INPROC_SERVER = 1
    hr := DllCall("ole32\CoCreateInstance", "Ptr", clsid, "Ptr", 0, "UInt", 1, "Ptr", iid, "Ptr*", &ptr)
    if (hr != 0 || ptr = 0) {
        ServiceLog("WARN", "CoCreateInstance(ITaskbarList) failed hr=" . Format("0x{:X}", hr))
        return 0
    }

    ; ITaskbarList::HrInit (vtable index 3) — required before AddTab/DeleteTab.
    ComCall(3, ptr)
    TaskbarListPtr := ptr
    return ptr
}

TaskbarRemove(hwnd) {
    ptr := InitTaskbarList()
    if !ptr
        return
    ; ITaskbarList::DeleteTab (vtable index 5)
    try ComCall(5, ptr, "Ptr", hwnd)
}

TaskbarAdd(hwnd) {
    ptr := InitTaskbarList()
    if !ptr
        return
    ; ITaskbarList::AddTab (vtable index 4)
    try ComCall(4, ptr, "Ptr", hwnd)
}

; TryHideWindow(hwnd) -> Map("ok", bool, "exStyle", UInt-when-ok, "reason", String-when-not-ok)
TryHideWindow(hwnd) {
    global GWL_EXSTYLE, WS_EX_APPWINDOW, WS_EX_TOOLWINDOW

    if !WinExist("ahk_id " . hwnd)
        return Map("ok", false, "reason", "window-does-not-exist")

    exStyle := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
    newExStyle := (exStyle & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW
    DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", newExStyle)

    WinHide("ahk_id " . hwnd)

    ; Forcibly drop the taskbar button. WS_EX_TOOLWINDOW alone doesn't
    ; cause the shell to remove an existing button; this does.
    TaskbarRemove(hwnd)

    stillVisible := DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
    if (stillVisible) {
        DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", exStyle)
        TaskbarAdd(hwnd)
        return Map("ok", false, "reason", "uiaccess-or-elevated-target")
    }
    return Map("ok", true, "exStyle", exStyle)
}

; RestoreWindowFromEntry(entry) -> bool
RestoreWindowFromEntry(entry) {
    global GWL_EXSTYLE
    hwnd := entry["hwnd"]
    if !WinExist("ahk_id " . hwnd)
        return false
    DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", entry["exStyle"])
    WinShow("ahk_id " . hwnd)
    TaskbarAdd(hwnd)  ; re-create the taskbar button
    return true
}
