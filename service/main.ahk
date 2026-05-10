#Requires AutoHotkey v2.0
#SingleInstance Force
DetectHiddenWindows true

#Include lib\JSON.ahk
#Include log.ahk
#Include config.ahk
#Include registry.ahk
#Include hider.ahk

; --- Bootstrap (Task 8: with file watcher) ---
ServiceLog("INFO", "service starting (Task 8 build — startup scan + live hook + config watcher)")
CurrentConfig := LoadConfig()
LastConfigMTime := FileExist(GetConfigPath()) ? FileGetTime(GetConfigPath(), "M") : ""
StartupScan(CurrentConfig)
RegisterWindowHook()
SetTimer(CheckConfigForChanges, 1000)
ServiceLog("INFO", "service idle — " HiddenEntries.Length " windows hidden, hook + watcher active")

; ---------------------------------------------------------------------------
; Win32 event constants and globals
; ---------------------------------------------------------------------------

EVENT_OBJECT_SHOW := 0x8002
WINEVENT_OUTOFCONTEXT := 0x0000
OBJID_WINDOW := 0

global hWinEventHook := 0
global EventCallbackPtr := 0
global CurrentConfig := ""
global LastConfigMTime := ""

; ---------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------

GetExeBasenameForHwnd(hwnd) {
    pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
    if (pid = 0)
        return ""

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

; Idempotent: skips windows already in HiddenEntries.
StartupScan(cfg) {
    DetectHiddenWindows false
    ids := WinGetList()
    DetectHiddenWindows true
    for hwnd in ids {
        ; Skip windows we've already hidden.
        already := false
        for entry in HiddenEntries {
            if entry["hwnd"] = hwnd {
                already := true
                break
            }
        }
        if already
            continue
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
; SetWinEventHook
; ---------------------------------------------------------------------------

WinEventCallback(hHook, event, hwnd, idObject, idChild, thread, time) {
    global CurrentConfig, OBJID_WINDOW

    if (idObject != OBJID_WINDOW || idChild != 0)
        return
    if (hwnd = 0)
        return
    if (CurrentConfig = "")
        return

    rule := FindEnabledRuleForHwnd(CurrentConfig, hwnd)
    if (rule = "")
        return

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

; ---------------------------------------------------------------------------
; Config watcher (mtime polling at 1 Hz — cost ~microseconds)
; ---------------------------------------------------------------------------

; Compares old config's enabled-rule set against new and reconciles registry + windows.
ApplyNewConfig(oldCfg, newCfg) {
    oldEnabled := Map(), newEnabled := Map()
    if oldCfg != "" {
        for rule in oldCfg["rules"]
            if rule.Has("enabled") && rule["enabled"]
                oldEnabled[rule["id"]] := true
    }
    for rule in newCfg["rules"]
        if rule.Has("enabled") && rule["enabled"]
            newEnabled[rule["id"]] := true

    ; Restore windows whose rule was disabled or removed.
    for ruleId in oldEnabled {
        if !newEnabled.Has(ruleId) {
            removed := RegistryRemoveByRuleId(ruleId)
            for entry in removed {
                RestoreWindowFromEntry(entry)
                ServiceLog("INFO", "restored hwnd=" entry["hwnd"] " ruleId=" ruleId " (rule disabled/removed)")
            }
        }
    }

    ; For newly-enabled rules, run a targeted scan to catch already-open windows.
    for ruleId in newEnabled {
        if !oldEnabled.Has(ruleId) {
            StartupScan(newCfg)
            break  ; one scan covers all rules anyway
        }
    }
}

CheckConfigForChanges() {
    global CurrentConfig, LastConfigMTime
    path := GetConfigPath()
    if !FileExist(path) {
        if CurrentConfig != "" && CurrentConfig["rules"].Length > 0 {
            oldCfg := CurrentConfig
            CurrentConfig := GetDefaultConfig()
            LastConfigMTime := ""
            ApplyNewConfig(oldCfg, CurrentConfig)
        }
        return
    }
    mtime := FileGetTime(path, "M")
    if (mtime = LastConfigMTime)
        return
    LastConfigMTime := mtime
    oldCfg := CurrentConfig
    CurrentConfig := LoadConfig()
    ServiceLog("INFO", "config.json changed — reapplying")
    ApplyNewConfig(oldCfg, CurrentConfig)
}
