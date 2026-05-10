#Requires AutoHotkey v2.0
#SingleInstance Force
DetectHiddenWindows true

#Include lib\JSON.ahk
#Include log.ahk
#Include config.ahk
#Include registry.ahk
#Include hider.ahk

; ==========================================================================
; Constants and globals — MUST be assigned before the bootstrap below.
; AHK v2 hoists function definitions but NOT script-level := assignments,
; so anything the bootstrap reads has to be initialized first in source order.
; ==========================================================================

; Win32 event constants
EVENT_OBJECT_SHOW := 0x8002
WINEVENT_OUTOFCONTEXT := 0x0000
OBJID_WINDOW := 0

global hWinEventHook := 0
global EventCallbackPtr := 0
global CurrentConfig := ""
global LastConfigMTime := ""
global hServiceMutex := 0
global Paused := false

; ==========================================================================
; Bootstrap
; ==========================================================================

AcquireServiceMutex()
ServiceLog("INFO", "service starting (full lifecycle)")
RecoverOrphanHiddenWindows()
CurrentConfig := LoadConfig()
LastConfigMTime := FileExist(GetConfigPath()) ? FileGetTime(GetConfigPath(), "M") : ""
RegisterWindowHook()
SetTimer(CheckConfigForChanges, 1000)
if CurrentConfig.Has("serviceState") && CurrentConfig["serviceState"] = "stopped" {
    Paused := true
    ServiceLog("INFO", "service idle — paused per config")
} else {
    StartupScan(CurrentConfig)
    ServiceLog("INFO", "service idle — " . HiddenEntries.Length . " windows hidden")
}
OnExit(OnServiceExit)

; ==========================================================================
; Helpers
; ==========================================================================

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

StartupScan(cfg) {
    DetectHiddenWindows false
    ids := WinGetList()
    DetectHiddenWindows true
    for hwnd in ids {
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
        title := WinGetTitle("ahk_id " . hwnd)
        result := TryHideWindow(hwnd)
        if (result["ok"]) {
            RegistryAdd(hwnd, result["exStyle"], rule["id"], title)
            ServiceLog("INFO", "hid hwnd=" . hwnd . " ruleId=" . rule["id"] . " title=" . title)
        } else {
            ServiceLog("WARN", "hide failed hwnd=" . hwnd . " ruleId=" . rule["id"] . " reason=" . result["reason"])
        }
    }
}

; ==========================================================================
; Named mutex
; ==========================================================================

AcquireServiceMutex() {
    global hServiceMutex
    ; CreateMutexW(NULL, FALSE, "HideAnyWindow_Service_Running")
    hServiceMutex := DllCall("CreateMutexW", "Ptr", 0, "Int", false, "Str", "HideAnyWindow_Service_Running", "Ptr")
    ; ERROR_ALREADY_EXISTS = 183 — another instance already holds it.
    if (A_LastError = 183) {
        ServiceLog("ERROR", "another service instance is already running — exiting")
        DllCall("CloseHandle", "Ptr", hServiceMutex)
        ExitApp 0
    }
    ServiceLog("INFO", "service mutex acquired")
}

ReleaseServiceMutex() {
    global hServiceMutex
    if (hServiceMutex != 0) {
        DllCall("CloseHandle", "Ptr", hServiceMutex)
        hServiceMutex := 0
    }
}

; ==========================================================================
; Pause/resume + crash recovery + shutdown
; ==========================================================================

PauseService() {
    global Paused, CurrentConfig
    if Paused
        return
    Paused := true
    ServiceLog("INFO", "service pausing — restoring all hidden windows")
    drained := RegistryDrain()
    for entry in drained {
        RestoreWindowFromEntry(entry)
    }
}

ResumeService() {
    global Paused, CurrentConfig
    if !Paused
        return
    Paused := false
    ServiceLog("INFO", "service resuming — re-running startup scan")
    StartupScan(CurrentConfig)
}

RecoverOrphanHiddenWindows() {
    orphans := LoadHiddenJson()
    if orphans.Length = 0
        return
    ServiceLog("INFO", "found " . orphans.Length . " orphan hidden windows from a prior run — restoring")
    for entry in orphans {
        RestoreWindowFromEntry(entry)
    }
    SaveHiddenJson()  ; persist the now-empty registry
}

OnServiceExit(*) {
    ServiceLog("INFO", "service shutting down — restoring all hidden windows")
    drained := RegistryDrain()
    for entry in drained
        RestoreWindowFromEntry(entry)
    UnregisterWindowHook()
    ReleaseServiceMutex()
}

; ==========================================================================
; SetWinEventHook
; ==========================================================================

WinEventCallback(hHook, event, hwnd, idObject, idChild, thread, time) {
    global CurrentConfig, OBJID_WINDOW, Paused

    if Paused
        return
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

    title := WinGetTitle("ahk_id " . hwnd)
    result := TryHideWindow(hwnd)
    if (result["ok"]) {
        RegistryAdd(hwnd, result["exStyle"], rule["id"], title)
        ServiceLog("INFO", "hooked-hide hwnd=" . hwnd . " ruleId=" . rule["id"] . " title=" . title)
    } else {
        ServiceLog("WARN", "hooked-hide failed hwnd=" . hwnd . " ruleId=" . rule["id"] . " reason=" . result["reason"])
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

; ==========================================================================
; Config watcher (mtime polling at 1 Hz — cost ~microseconds)
; ==========================================================================

ApplyNewConfig(oldCfg, newCfg) {
    global Paused

    newWantsStopped := newCfg.Has("serviceState") && newCfg["serviceState"] = "stopped"
    if newWantsStopped {
        PauseService()
        return
    }
    if Paused {
        ResumeService()
        return
    }

    oldEnabled := Map()
    newEnabled := Map()
    if oldCfg != "" {
        for rule in oldCfg["rules"]
            if rule.Has("enabled") && rule["enabled"]
                oldEnabled[rule["id"]] := true
    }
    for rule in newCfg["rules"]
        if rule.Has("enabled") && rule["enabled"]
            newEnabled[rule["id"]] := true

    for ruleId in oldEnabled {
        if !newEnabled.Has(ruleId) {
            removed := RegistryRemoveByRuleId(ruleId)
            for entry in removed {
                RestoreWindowFromEntry(entry)
                ServiceLog("INFO", "restored hwnd=" . entry["hwnd"] . " ruleId=" . ruleId . " (rule disabled/removed)")
            }
        }
    }

    for ruleId in newEnabled {
        if !oldEnabled.Has(ruleId) {
            StartupScan(newCfg)
            break
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
