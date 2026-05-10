#Requires AutoHotkey v2.0
#SingleInstance Force
DetectHiddenWindows true

#Include lib\JSON.ahk
#Include log.ahk
#Include config.ahk
#Include registry.ahk
#Include hider.ahk

; --- Bootstrap (Task 6: one-shot only) ---
ServiceLog("INFO", "service starting (Task 6 build — one-shot scan)")
cfg := LoadConfig()
StartupScan(cfg)
ServiceLog("INFO", "service idle — " HiddenEntries.Length " windows hidden")
; Script stays alive because of the AHK message loop.

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
