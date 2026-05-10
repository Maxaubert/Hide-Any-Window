#Requires AutoHotkey v2.0
#SingleInstance Force
DetectHiddenWindows true

#Include lib\JSON.ahk
#Include log.ahk
#Include config.ahk
#Include registry.ahk
#Include hider.ahk

; --- Bootstrap (Task 7: with live hook, no watcher yet) ---
ServiceLog("INFO", "service starting (Task 7 build — startup scan + live hook)")
CurrentConfig := LoadConfig()
StartupScan(CurrentConfig)
RegisterWindowHook()
ServiceLog("INFO", "service idle — " HiddenEntries.Length " windows hidden, hook active")

; ---------------------------------------------------------------------------
; Win32 event constants and globals
; ---------------------------------------------------------------------------

EVENT_OBJECT_SHOW := 0x8002
WINEVENT_OUTOFCONTEXT := 0x0000
OBJID_WINDOW := 0

global hWinEventHook := 0
global EventCallbackPtr := 0
global CurrentConfig := ""   ; latest cfg, kept in sync by the config watcher (Task 8)

; ---------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------

; Returns lowercase basename of the executable that owns hwnd, e.g. "magnify.exe".
; Returns "" on failure.
GetExeBasenameForHwnd(hwnd) {
    pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
    if (pid = 0)
        return ""

    ; PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    hProc := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr")
    if (hProc = 0)
        return ""

    bufSize := 1024
    buf := Buffer(bufSize * 2, 0)
    sizeRef := bufSize
    ok := DllCall("QueryFullProcessImageNameW", "Ptr", hProc, "UInt", 0, "Ptr", buf, "UInt*", &sizeRef)
    DllCall("CloseHandle", "Ptr", hProc)

    if (!ok)
        return ""
    fullPath := StrGet(buf, sizeRef, "UTF-16")
    SplitPath(fullPath, &basename)
    return StrLower(basename)
}

; FindEnabledRuleForHwnd(cfg, hwnd) -> Map (the matching rule) | ""
FindEnabledRuleForHwnd(cfg, hwnd) {
    exe := GetExeBasenameForHwnd(hwnd)
    if (exe = "")
        return ""
    for rule in cfg["rules"] {
        if (rule.Has("enabled") && rule["enabled"]
            && rule.Has("exe") && StrLower(rule["exe"]) = exe)
            return rule
    }
    return ""
}

; Iterates every visible top-level window, hides any that match an enabled rule.
StartupScan(cfg) {
    DetectHiddenWindows false  ; we want only visible windows for the scan
    ids := WinGetList()
    DetectHiddenWindows true   ; restore script-wide setting
    for hwnd in ids {
        rule := FindEnabledRuleForHwnd(cfg, hwnd)
        if (rule = "")
            continue
        title := WinGetTitle("ahk_id " hwnd)
        result := TryHideWindow(hwnd)
        if (result["ok"]) {
            RegistryAdd(hwnd, result["exStyle"], rule["id"], title)
            ServiceLog("INFO", "hid hwnd=" hwnd " ruleId=" rule["id"] " title=" title)
        } else {
            ServiceLog("WARN", "hide failed hwnd=" hwnd " ruleId=" rule["id"] " reason=" result["reason"])
        }
    }
}

; ---------------------------------------------------------------------------
; SetWinEventHook — fires on every new visible window
; ---------------------------------------------------------------------------

; Signature: void(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime)
WinEventCallback(hHook, event, hwnd, idObject, idChild, thread, time) {
    global CurrentConfig, OBJID_WINDOW

    if (idObject != OBJID_WINDOW || idChild != 0)
        return  ; we only care about top-level windows
    if (hwnd = 0)
        return
    if (CurrentConfig = "")
        return

    rule := FindEnabledRuleForHwnd(CurrentConfig, hwnd)
    if (rule = "")
        return

    ; Skip windows we already hid (avoid double-processing).
    for entry in HiddenEntries {
        if entry["hwnd"] = hwnd
            return
    }

    title := WinGetTitle("ahk_id " hwnd)
    result := TryHideWindow(hwnd)
    if (result["ok"]) {
        RegistryAdd(hwnd, result["exStyle"], rule["id"], title)
        ServiceLog("INFO", "hooked-hide hwnd=" hwnd " ruleId=" rule["id"] " title=" title)
    } else {
        ServiceLog("WARN", "hooked-hide failed hwnd=" hwnd " ruleId=" rule["id"] " reason=" result["reason"])
    }
}

RegisterWindowHook() {
    global hWinEventHook, EventCallbackPtr, EVENT_OBJECT_SHOW, WINEVENT_OUTOFCONTEXT
    EventCallbackPtr := CallbackCreate(WinEventCallback, "F", 7)
    hWinEventHook := DllCall("SetWinEventHook"
        , "UInt", EVENT_OBJECT_SHOW
        , "UInt", EVENT_OBJECT_SHOW
        , "Ptr",  0
        , "Ptr",  EventCallbackPtr
        , "UInt", 0
        , "UInt", 0
        , "UInt", WINEVENT_OUTOFCONTEXT
        , "Ptr")
    if (hWinEventHook = 0)
        ServiceLog("ERROR", "SetWinEventHook returned 0 — live hide will not work")
}

UnregisterWindowHook() {
    global hWinEventHook, EventCallbackPtr
    if (hWinEventHook != 0) {
        DllCall("UnhookWinEvent", "Ptr", hWinEventHook)
        hWinEventHook := 0
    }
    if (EventCallbackPtr != 0) {
        CallbackFree(EventCallbackPtr)
        EventCallbackPtr := 0
    }
}
