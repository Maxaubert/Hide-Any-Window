# Hide Any Window — Phase B Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve the Phase A AHK script into a config-driven background service that auto-hides any window matching its rule list. Event-driven (zero meaningful polling). The manager (Plan B-2, to be written separately) will arrive after this plan ships and is validated.

**Architecture:** Single elevated AHK v2 process. Reads `%APPDATA%\HideAnyWindow\config.json` for rules, watches the file for live edits via cheap mtime polling, hooks `EVENT_OBJECT_SHOW` so any matching new window is hidden the moment it appears. Holds a named mutex for liveness signaling. Persists hidden-window state to `hidden.json` for crash recovery. Hotkeys are gone — the service has no UI.

**Tech Stack:** AutoHotkey v2.0+, vendored `JSON.ahk` (single-file by thqby), plain Win32 via `DllCall` (`SetWinEventHook`, `CreateMutex`, `EnumWindows`, `GetWindowThreadProcessId`, `QueryFullProcessImageName`).

**Note on testing:** Same realism as Phase A — there is no good way to unit-test live window manipulation, so each behavior task ends in a manual verification procedure with explicit pass/fail criteria. Pure-logic tasks (JSON, registry serialization) include small inline AHK assert scripts that exit with a non-zero code on failure.

---

## File Structure

All new files live under a new top-level `service/` directory. The Phase A script stays in place during development as a reference and fallback; it's removed in the final task once Phase B is validated.

| Path | Responsibility |
|---|---|
| `service/main.ahk` | Entry point. Bootstraps log, config, registry, hider, hooks, mutex, watcher. Owns lifecycle. |
| `service/log.ahk` | `ServiceLog(level, msg)` — append-only log to `%APPDATA%\HideAnyWindow\service.log` with timestamp + level. |
| `service/config.ahk` | `LoadConfig()` — read `config.json`, return parsed map with sane defaults; handles missing/malformed gracefully (logs and returns default). Exposes `GetConfigPath()`, `GetAppDataDir()`. |
| `service/registry.ahk` | In-memory hidden-window registry (`HiddenEntries` array of `{hwnd, exStyle, ruleId, title}`). `RegistryAdd`, `RegistryRemoveByRuleId`, `RegistryRemoveByHwnd`, `RegistryClear`, plus `LoadHiddenJson` / `SaveHiddenJson` for atomic persistence. |
| `service/hider.ahk` | Pure window operations refactored from Phase A. `TryHideWindow(hwnd) -> {ok, exStyle?, reason?}` and `RestoreWindowFromEntry(entry) -> ok`. Knows nothing about config or registry. |
| `service/lib/JSON.ahk` | Vendored — JSON parser/serializer (thqby's library). Not modified. |
| `hide-any-window.ahk` (existing) | Phase A script. Kept until Task 11. |

---

## Task 1: Service directory scaffolding + JSON dependency

**Files:**
- Create: `service/main.ahk`, `service/log.ahk`, `service/config.ahk`, `service/registry.ahk`, `service/hider.ahk`
- Create: `service/lib/JSON.ahk` (vendored)
- Modify: `.gitignore` — add `service/test/` for ad-hoc test outputs

- [ ] **Step 1: Make the directory layout**

```powershell
mkdir service\lib
mkdir service\test
```

- [ ] **Step 2: Vendor `JSON.ahk`**

Download `JSON.ahk` from https://raw.githubusercontent.com/thqby/ahk2_lib/master/JSON.ahk and save it to `service/lib/JSON.ahk`. (Or copy the file from any local AHK v2 install that has it.) This is a single self-contained file, ~300 lines, no further dependencies. License is MIT (the repo is permissive).

If the URL is unreachable, alternative: use the version included in newer AHK v2 distributions at `<AHK install>/Lib/JSON.ahk`.

Verify:

```powershell
Get-Content service\lib\JSON.ahk -TotalCount 5
```

Expected: lines like `class JSON { ... }`. If you see a 404 HTML page, you fetched the wrong URL.

- [ ] **Step 3: Add the stub files**

`service/main.ahk`:

```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Force
DetectHiddenWindows true

#Include lib\JSON.ahk
#Include log.ahk
#Include config.ahk
#Include registry.ahk
#Include hider.ahk

; Bootstrapping happens in later tasks.
```

`service/log.ahk`:

```autohotkey
; Log helper — implemented in Task 2.
```

`service/config.ahk`:

```autohotkey
; Config reader — implemented in Task 3.
```

`service/registry.ahk`:

```autohotkey
; Hidden-window registry — implemented in Task 4.
```

`service/hider.ahk`:

```autohotkey
; Window hide/restore primitives — implemented in Task 5.
```

- [ ] **Step 4: Verify the script launches**

Double-click `service/main.ahk` (no admin needed yet — we're just verifying it parses). A green AHK tray icon should appear, no error dialog. Right-click the tray icon → Exit.

If you get a parse error, the most likely cause is a typo in the include path or `JSON.ahk` not being where it's expected.

- [ ] **Step 5: Update `.gitignore`**

Append:

```gitignore
# Ad-hoc service test outputs
service/test/output/
```

- [ ] **Step 6: Commit**

```powershell
git add service/ .gitignore
git commit -m "scaffold: service directory, stub modules, vendored JSON.ahk"
```

---

## Task 2: Implement `log.ahk`

**Files:**
- Modify: `service/log.ahk`
- Test: `service/test/test_log.ahk`

- [ ] **Step 1: Implement the log helper**

Replace the contents of `service/log.ahk` with:

```autohotkey
; ServiceLog(level, msg)
;   level: "INFO" | "WARN" | "ERROR"
;   msg:   string
; Appends one line to %APPDATA%\HideAnyWindow\service.log.
; Creates the directory if needed.

GetAppDataDir() {
    dir := A_AppData "\HideAnyWindow"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

ServiceLog(level, msg) {
    line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " level " | " msg "`r`n"
    FileAppend(line, GetAppDataDir() "\service.log")
}
```

- [ ] **Step 2: Write the test script**

Create `service/test/test_log.ahk`:

```autohotkey
#Requires AutoHotkey v2.0
#Include ..\log.ahk

; Clean slate
logFile := GetAppDataDir() "\service.log"
if FileExist(logFile)
    FileDelete(logFile)

ServiceLog("INFO", "test message 1")
ServiceLog("WARN", "test message 2")
ServiceLog("ERROR", "test message 3")

contents := FileRead(logFile)
assertCount := 0
if InStr(contents, "INFO | test message 1")
    assertCount += 1
if InStr(contents, "WARN | test message 2")
    assertCount += 1
if InStr(contents, "ERROR | test message 3")
    assertCount += 1

if assertCount = 3 {
    MsgBox "log.ahk test PASSED"
    ExitApp 0
} else {
    MsgBox "log.ahk test FAILED — only " assertCount "/3 assertions held`n`nFile contents:`n" contents
    ExitApp 1
}
```

- [ ] **Step 3: Run the test**

Double-click `service/test/test_log.ahk`. Expected: `MsgBox` "log.ahk test PASSED". Click OK to dismiss. The script exits.

If it fails, the message box shows which assertions failed and the actual file contents — debug from there.

- [ ] **Step 4: Commit**

```powershell
git add service/log.ahk service/test/test_log.ahk
git commit -m "feat(service): log helper with timestamp + level"
```

---

## Task 3: Implement `config.ahk`

**Files:**
- Modify: `service/config.ahk`
- Test: `service/test/test_config.ahk`

The config loader must handle three input states: file missing (return defaults), file malformed (log + return defaults), file valid (parse and return).

- [ ] **Step 1: Implement `LoadConfig`**

Replace contents of `service/config.ahk` with:

```autohotkey
; Default config used when file is missing or unreadable.
GetDefaultConfig() {
    return Map(
        "schemaVersion", 1,
        "serviceState", "running",
        "rules", []
    )
}

GetConfigPath() {
    return GetAppDataDir() "\config.json"
}

; LoadConfig() -> Map
; Returns parsed config or default. Logs malformed reads.
LoadConfig() {
    path := GetConfigPath()
    if !FileExist(path) {
        ServiceLog("INFO", "config.json missing — using defaults")
        return GetDefaultConfig()
    }
    try {
        text := FileRead(path, "UTF-8")
        cfg := JSON.parse(text)   ; non-strict, returns Map
        if !cfg.Has("rules") || !(cfg["rules"] is Array) {
            ServiceLog("WARN", "config.json missing 'rules' array — using defaults")
            return GetDefaultConfig()
        }
        if !cfg.Has("serviceState")
            cfg["serviceState"] := "running"
        if !cfg.Has("schemaVersion")
            cfg["schemaVersion"] := 1
        return cfg
    } catch as e {
        ServiceLog("ERROR", "config.json parse failed: " e.Message)
        return GetDefaultConfig()
    }
}
```

Note: `JSON.parse(text)` returns AHK Maps for objects and Arrays for arrays by default (the lib's `as_map` parameter defaults to `true`).

- [ ] **Step 2: Write the test script**

Create `service/test/test_config.ahk`:

```autohotkey
#Requires AutoHotkey v2.0
#Include ..\lib\JSON.ahk
#Include ..\log.ahk
#Include ..\config.ahk

results := []
testDir := GetAppDataDir()
configPath := GetConfigPath()

; --- Test 1: missing file -> defaults ---
if FileExist(configPath)
    FileDelete(configPath)
cfg := LoadConfig()
results.Push(cfg["serviceState"] = "running" && cfg["rules"].Length = 0
    ? "PASS: missing file -> defaults"
    : "FAIL: missing file -> defaults (got " cfg["serviceState"] ", " cfg["rules"].Length " rules)")

; --- Test 2: malformed file -> defaults ---
FileAppend("not json {{{", configPath)
cfg := LoadConfig()
results.Push(cfg["rules"].Length = 0
    ? "PASS: malformed file -> defaults"
    : "FAIL: malformed file -> defaults")
FileDelete(configPath)

; --- Test 3: valid file -> parsed ---
sample := '{"schemaVersion":1,"serviceState":"stopped","rules":[{"id":"magnify-exe","exe":"magnify.exe","name":"Magnifier","enabled":true}]}'
FileAppend(sample, configPath)
cfg := LoadConfig()
ok := cfg["serviceState"] = "stopped"
    && cfg["rules"].Length = 1
    && cfg["rules"][1]["exe"] = "magnify.exe"
    && cfg["rules"][1]["enabled"] = true
results.Push(ok ? "PASS: valid file -> parsed" : "FAIL: valid file -> parsed")
FileDelete(configPath)

allPass := true
report := ""
for r in results {
    report .= r "`n"
    if InStr(r, "FAIL")
        allPass := false
}

if allPass {
    MsgBox "config.ahk tests PASSED`n`n" report
    ExitApp 0
} else {
    MsgBox "config.ahk tests FAILED`n`n" report
    ExitApp 1
}
```

- [ ] **Step 3: Run the test**

Double-click `service/test/test_config.ahk`. Expected: PASSED message box.

- [ ] **Step 4: Commit**

```powershell
git add service/config.ahk service/test/test_config.ahk
git commit -m "feat(service): config loader with defaults + malformed-input handling"
```

---

## Task 4: Implement `registry.ahk`

**Files:**
- Modify: `service/registry.ahk`
- Test: `service/test/test_registry.ahk`

In-memory plus persistent (`hidden.json`) — both must stay in sync. Atomic writes.

- [ ] **Step 1: Implement the registry**

Replace contents of `service/registry.ahk` with:

```autohotkey
; Global in-memory state. Each entry: Map("hwnd", UInt, "exStyle", UInt, "ruleId", String, "title", String)
global HiddenEntries := []

GetHiddenJsonPath() {
    return GetAppDataDir() "\hidden.json"
}

RegistryAdd(hwnd, exStyle, ruleId, title) {
    global HiddenEntries
    HiddenEntries.Push(Map("hwnd", hwnd, "exStyle", exStyle, "ruleId", ruleId, "title", title))
    SaveHiddenJson()
}

RegistryRemoveByHwnd(hwnd) {
    global HiddenEntries
    i := HiddenEntries.Length
    while (i >= 1) {
        if HiddenEntries[i]["hwnd"] = hwnd {
            HiddenEntries.RemoveAt(i)
        }
        i -= 1
    }
    SaveHiddenJson()
}

; Returns array of removed entries (so caller can restore them).
RegistryRemoveByRuleId(ruleId) {
    global HiddenEntries
    removed := []
    keep := []
    for entry in HiddenEntries {
        if entry["ruleId"] = ruleId
            removed.Push(entry)
        else
            keep.Push(entry)
    }
    HiddenEntries := keep
    SaveHiddenJson()
    return removed
}

; Returns array of all entries and clears the registry. Caller restores them.
RegistryDrain() {
    global HiddenEntries
    drained := HiddenEntries
    HiddenEntries := []
    SaveHiddenJson()
    return drained
}

SaveHiddenJson() {
    global HiddenEntries
    path := GetHiddenJsonPath()
    tmp := path ".tmp"
    text := JSON.stringify(Map("entries", HiddenEntries))
    if FileExist(tmp)
        FileDelete(tmp)
    FileAppend(text, tmp, "UTF-8")
    if FileExist(path)
        FileDelete(path)
    FileMove(tmp, path)
}

; Returns array of entries from disk. Does NOT populate HiddenEntries — caller decides.
LoadHiddenJson() {
    path := GetHiddenJsonPath()
    if !FileExist(path)
        return []
    try {
        text := FileRead(path, "UTF-8")
        data := JSON.parse(text)
        return data.Has("entries") ? data["entries"] : []
    } catch as e {
        ServiceLog("WARN", "hidden.json parse failed: " e.Message)
        return []
    }
}
```

- [ ] **Step 2: Write the test script**

Create `service/test/test_registry.ahk`:

```autohotkey
#Requires AutoHotkey v2.0
#Include ..\lib\JSON.ahk
#Include ..\log.ahk
#Include ..\config.ahk
#Include ..\registry.ahk

if FileExist(GetHiddenJsonPath())
    FileDelete(GetHiddenJsonPath())

results := []

RegistryAdd(111, 0x40000, "magnify-exe", "Magnifier")
RegistryAdd(222, 0x40000, "discord-exe", "Discord")
RegistryAdd(333, 0x40080, "magnify-exe", "Magnifier #2")
results.Push(HiddenEntries.Length = 3 ? "PASS: add 3" : "FAIL: add 3")

removed := RegistryRemoveByRuleId("magnify-exe")
results.Push(removed.Length = 2 && HiddenEntries.Length = 1 && HiddenEntries[1]["hwnd"] = 222
    ? "PASS: remove by ruleId returns 2 and keeps 1"
    : "FAIL: remove by ruleId")

; Confirm hidden.json round-trip
loaded := LoadHiddenJson()
results.Push(loaded.Length = 1 && loaded[1]["hwnd"] = 222
    ? "PASS: hidden.json round-trip"
    : "FAIL: hidden.json round-trip (got " loaded.Length " entries)")

drained := RegistryDrain()
results.Push(drained.Length = 1 && HiddenEntries.Length = 0
    ? "PASS: drain"
    : "FAIL: drain")

allPass := true
report := ""
for r in results {
    report .= r "`n"
    if InStr(r, "FAIL")
        allPass := false
}

MsgBox (allPass ? "registry.ahk PASSED" : "registry.ahk FAILED") "`n`n" report
ExitApp(allPass ? 0 : 1)
```

- [ ] **Step 3: Run the test**

Double-click. Expected: PASSED.

- [ ] **Step 4: Commit**

```powershell
git add service/registry.ahk service/test/test_registry.ahk
git commit -m "feat(service): hidden-window registry with hidden.json persistence"
```

---

## Task 5: Refactor `hider.ahk` from Phase A

**Files:**
- Modify: `service/hider.ahk`

Take the Phase A hide/restore body and split it into pure functions that don't touch the registry or config — those are the caller's job.

- [ ] **Step 1: Implement hider primitives**

Replace contents of `service/hider.ahk` with:

```autohotkey
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
```

- [ ] **Step 2: No automated test for this task**

These functions act on real windows and were validated end-to-end in Phase A. The next task wires them up; we'll verify by manual end-to-end test there.

- [ ] **Step 3: Commit**

```powershell
git add service/hider.ahk
git commit -m "feat(service): pure window-hide/restore primitives"
```

---

## Task 6: Wire `main.ahk` for one-shot config-driven hide

**Files:**
- Modify: `service/main.ahk`

This task delivers the first runnable version of the service: read config, find matching windows that already exist, hide them. No event hook yet, no file watcher yet, no mutex yet. Just config → hide.

- [ ] **Step 1: Add the process-resolution helper to `main.ahk`**

We need to map a window HWND → owning process exe basename. Append to `service/main.ahk`:

```autohotkey
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
```

- [ ] **Step 2: Add the matching helper**

```autohotkey
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
```

- [ ] **Step 3: Add the startup scan**

```autohotkey
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
```

- [ ] **Step 4: Add the bootstrap**

After the includes at the top of `main.ahk`, add:

```autohotkey
; --- Bootstrap (Task 6: one-shot only) ---
ServiceLog("INFO", "service starting (Task 6 build — one-shot scan)")
cfg := LoadConfig()
StartupScan(cfg)
ServiceLog("INFO", "service idle — " HiddenEntries.Length " windows hidden")
; Script stays alive because of the AHK message loop.
```

- [ ] **Step 5: Manual verification — Magnifier**

1. Create `%APPDATA%\HideAnyWindow\config.json` in Notepad with:

   ```json
   {
     "schemaVersion": 1,
     "serviceState": "running",
     "rules": [
       { "id": "magnify-exe", "exe": "magnify.exe", "name": "Magnifier", "enabled": true }
     ]
   }
   ```

2. Open Magnifier. Confirm it's visible.
3. Right-click `service/main.ahk` → Run as administrator. Approve UAC.
4. Expected: Magnifier vanishes from screen + taskbar + Alt-Tab within ~1s.
5. Tail the log: `Get-Content "$env:APPDATA\HideAnyWindow\service.log" -Tail 5` — should show `INFO` lines for service start, hide, and idle count.
6. Right-click tray → Exit. The Magnifier window stays hidden (the service did not restore on exit yet — Task 10 adds that).
7. Kill `magnify.exe` via Task Manager to clean up.

- [ ] **Step 6: Commit**

```powershell
git add service/main.ahk
git commit -m "feat(service): one-shot config-driven startup scan"
```

---

## Task 7: Add `SetWinEventHook` for live window detection

**Files:**
- Modify: `service/main.ahk`

After this task, opening Magnifier *while the service is running* should auto-hide it within milliseconds.

- [ ] **Step 1: Add the hook globals**

Append to `service/main.ahk`:

```autohotkey
; Win32 event constants
EVENT_OBJECT_SHOW := 0x8002
WINEVENT_OUTOFCONTEXT := 0x0000
OBJID_WINDOW := 0

global hWinEventHook := 0
global EventCallbackPtr := 0
global CurrentConfig := ""   ; latest cfg, kept in sync by the config watcher (Task 8)
```

- [ ] **Step 2: Add the event callback**

```autohotkey
; SetWinEventHook callback. Runs on every shown window.
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
```

- [ ] **Step 3: Add the registration helpers**

```autohotkey
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
```

- [ ] **Step 4: Update the bootstrap to register the hook and keep `CurrentConfig` in sync**

Replace the existing bootstrap block at the top of `main.ahk` with:

```autohotkey
; --- Bootstrap (Task 7: with live hook, no watcher yet) ---
ServiceLog("INFO", "service starting (Task 7 build — startup scan + live hook)")
CurrentConfig := LoadConfig()
StartupScan(CurrentConfig)
RegisterWindowHook()
ServiceLog("INFO", "service idle — " HiddenEntries.Length " windows hidden, hook active")
```

- [ ] **Step 5: Manual verification — live hook**

1. Make sure `config.json` still has the Magnifier rule from Task 6.
2. Right-click `service/main.ahk` → Run as administrator.
3. Confirm the log shows "service idle ... hook active".
4. Open Magnifier (if not running, start it now).
5. Expected: it disappears within ~100ms of becoming visible. Log entry: `hooked-hide hwnd=...`.
6. Open Magnifier a second time. Same thing — instant hide.
7. Right-click tray → Exit (Task 10 will add proper cleanup).

- [ ] **Step 6: Commit**

```powershell
git add service/main.ahk
git commit -m "feat(service): SetWinEventHook for live auto-hide of new windows"
```

---

## Task 8: Add config file watcher (mtime polling)

**Files:**
- Modify: `service/main.ahk`

Spec called for `ReadDirectoryChangesW`. In AHK this is fiddly (overlapped I/O is awkward with `DllCall`). We use mtime polling at 1 Hz instead — `FileGetTime` is a single GetFileAttributesEx syscall, microseconds of cost, indistinguishable from "zero polling" for practical purposes.

- [ ] **Step 1: Add the watcher state and apply-config function**

Append to `service/main.ahk`:

```autohotkey
global LastConfigMTime := ""

; Compares old config's enabled-rule set against new and reconciles registry + windows.
; Caller has already updated CurrentConfig.
ApplyNewConfig(oldCfg, newCfg) {
    ; Build sets of enabled rule IDs
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
            StartupScan(newCfg)   ; cheap; double-check in callee skips already-hidden via FindEnabledRuleForHwnd + dedupe
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
```

Note: the dedupe in `WinEventCallback` (Step 2 of Task 7) prevents the StartupScan from re-hiding windows we already have in the registry, so calling StartupScan again is safe.

Wait — `StartupScan` doesn't have the dedupe. Let me also add a dedupe check inside StartupScan so re-runs are idempotent.

- [ ] **Step 2: Make `StartupScan` idempotent**

Replace the `StartupScan` body in `main.ahk` so it skips windows already in the registry:

```autohotkey
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
```

- [ ] **Step 3: Start the watcher timer in the bootstrap**

Update the bootstrap block at the top of `main.ahk` to:

```autohotkey
; --- Bootstrap (Task 8: with file watcher) ---
ServiceLog("INFO", "service starting (Task 8 build — startup scan + live hook + config watcher)")
CurrentConfig := LoadConfig()
LastConfigMTime := FileExist(GetConfigPath()) ? FileGetTime(GetConfigPath(), "M") : ""
StartupScan(CurrentConfig)
RegisterWindowHook()
SetTimer(CheckConfigForChanges, 1000)
ServiceLog("INFO", "service idle — " HiddenEntries.Length " windows hidden, hook + watcher active")
```

- [ ] **Step 4: Manual verification — live config edits**

1. Right-click `service/main.ahk` → Run as administrator.
2. Open Notepad to `%APPDATA%\HideAnyWindow\config.json`.
3. Open Magnifier — should auto-hide (verifies hook still works).
4. In Notepad, change Magnifier's `"enabled": true` to `"enabled": false`. Save.
5. Within 1–2s, Magnifier should reappear. Log entry: `restored hwnd=... ruleId=magnify-exe (rule disabled/removed)`.
6. Flip back to `"enabled": true`, save. Magnifier vanishes again within 1–2s.
7. Add a second rule for `"notepad.exe"`. Save. The currently-open Notepad (the one editing config.json) should NOT vanish — wait actually it would, since notepad.exe is the exe. **For this test use a different editor (e.g., VSCode) to edit `config.json`** — or be willing to lose Notepad mid-edit.
8. Stop the service via the tray.

- [ ] **Step 5: Commit**

```powershell
git add service/main.ahk
git commit -m "feat(service): config file watcher with apply-on-change reconciliation"
```

---

## Task 9: Named mutex for liveness signaling

**Files:**
- Modify: `service/main.ahk`

The Manager (Plan B-2) will check this mutex to know if the service is running.

- [ ] **Step 1: Add mutex helpers**

Append to `service/main.ahk`:

```autohotkey
global hServiceMutex := 0

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
```

- [ ] **Step 2: Acquire on startup**

Update the bootstrap block — `AcquireServiceMutex()` must be the first thing, before any other I/O:

```autohotkey
; --- Bootstrap (Task 9: with mutex) ---
AcquireServiceMutex()  ; exits early if another instance is running
ServiceLog("INFO", "service starting (Task 9 build — with named mutex)")
CurrentConfig := LoadConfig()
LastConfigMTime := FileExist(GetConfigPath()) ? FileGetTime(GetConfigPath(), "M") : ""
StartupScan(CurrentConfig)
RegisterWindowHook()
SetTimer(CheckConfigForChanges, 1000)
ServiceLog("INFO", "service idle — " HiddenEntries.Length " windows hidden, hook + watcher active")
```

- [ ] **Step 3: Manual verification — single instance**

1. Run `service/main.ahk` as administrator.
2. Run `service/main.ahk` as administrator again (second time).
3. Expected: the second instance silently exits. Log file shows `ERROR | another service instance is already running — exiting`.
4. The first instance is still in the tray and still functional (open Magnifier to confirm hook still works).
5. Stop both via the tray.

- [ ] **Step 4: Manual verification — mutex visible to outside processes**

```powershell
# Use Sysinternals handle.exe if available, OR a quick PowerShell mutex check
[System.Threading.Mutex]::OpenExisting("HideAnyWindow_Service_Running")
```

With the service running, expected: PowerShell returns a Mutex object (no exception). With the service stopped: throws `WaitHandleCannotBeOpenedException`. This proves the manager (which uses .NET) will be able to detect the service.

- [ ] **Step 5: Commit**

```powershell
git add service/main.ahk
git commit -m "feat(service): named mutex for liveness signaling"
```

---

## Task 10: serviceState pause/resume + graceful shutdown + crash recovery

**Files:**
- Modify: `service/main.ahk`

This is the last behavior task. Three things bundled because they're all about lifecycle:
- Reading `serviceState: "stopped"` and pausing (restoring everything)
- Restoring everything on tray exit
- Restoring orphan hidden windows from `hidden.json` at startup

- [ ] **Step 1: Add the paused flag and pause/resume helpers**

Append to `service/main.ahk`:

```autohotkey
global Paused := false

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
```

- [ ] **Step 2: Make the event callback respect `Paused`**

Modify the start of `WinEventCallback`:

```autohotkey
WinEventCallback(hHook, event, hwnd, idObject, idChild, thread, time) {
    global CurrentConfig, OBJID_WINDOW, Paused

    if Paused
        return
    if (idObject != OBJID_WINDOW || idChild != 0)
        return
    ; ... rest of function unchanged ...
```

- [ ] **Step 3: Make `ApplyNewConfig` honor `serviceState`**

Replace the body of `ApplyNewConfig` with:

```autohotkey
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

    ; Diff old vs new enabled rules
    oldEnabled := Map(), newEnabled := Map()
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
                ServiceLog("INFO", "restored hwnd=" entry["hwnd"] " ruleId=" ruleId " (rule disabled/removed)")
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
```

- [ ] **Step 4: Add crash-recovery on startup**

Add this function in `main.ahk`:

```autohotkey
RecoverOrphanHiddenWindows() {
    orphans := LoadHiddenJson()
    if orphans.Length = 0
        return
    ServiceLog("INFO", "found " orphans.Length " orphan hidden windows from a prior run — restoring")
    for entry in orphans {
        RestoreWindowFromEntry(entry)
    }
    ; Clear the file by writing an empty registry.
    SaveHiddenJson()
}
```

- [ ] **Step 5: Add the exit handler**

```autohotkey
OnServiceExit(*) {
    ServiceLog("INFO", "service shutting down — restoring all hidden windows")
    drained := RegistryDrain()
    for entry in drained
        RestoreWindowFromEntry(entry)
    UnregisterWindowHook()
    ReleaseServiceMutex()
}

OnExit(OnServiceExit)
```

- [ ] **Step 6: Wire startup with crash recovery and pause-on-startup**

Replace the bootstrap block one more time. Final form:

```autohotkey
; --- Bootstrap (Task 10: full lifecycle) ---
AcquireServiceMutex()
ServiceLog("INFO", "service starting (Task 10 build — full lifecycle)")
RecoverOrphanHiddenWindows()  ; restore anything left hidden by a previous crashed run
CurrentConfig := LoadConfig()
LastConfigMTime := FileExist(GetConfigPath()) ? FileGetTime(GetConfigPath(), "M") : ""
RegisterWindowHook()
SetTimer(CheckConfigForChanges, 1000)
if CurrentConfig.Has("serviceState") && CurrentConfig["serviceState"] = "stopped" {
    Paused := true
    ServiceLog("INFO", "service idle — paused per config")
} else {
    StartupScan(CurrentConfig)
    ServiceLog("INFO", "service idle — " HiddenEntries.Length " windows hidden")
}
```

- [ ] **Step 7: Manual verification — pause via config**

1. Run service as admin. Open Magnifier → it hides.
2. Edit `config.json`, set `"serviceState": "stopped"`. Save.
3. Within 1–2s: Magnifier reappears, log shows "service pausing".
4. Open Magnifier again — it stays visible (hook is paused).
5. Edit `config.json`, set `"serviceState": "running"`. Save.
6. Magnifier vanishes again within 1–2s.

- [ ] **Step 8: Manual verification — graceful exit restores**

1. Service running, Magnifier hidden.
2. Right-click tray → Exit.
3. Expected: Magnifier reappears immediately. Log shows "shutting down — restoring all hidden windows". `hidden.json` ends up empty (`{"entries":[]}`).

- [ ] **Step 9: Manual verification — crash recovery**

1. Run service as admin. Open Magnifier → it hides.
2. Open Task Manager → Details → end the AutoHotkey process.
3. Expected: Magnifier stays hidden. `hidden.json` still has its entry.
4. Run service as admin again.
5. Expected: log shows "found 1 orphan hidden windows ... restoring". Magnifier reappears briefly. Then, because the rule is still enabled, the startup scan immediately re-hides it. Net effect: Magnifier is hidden, but it was first restored from the orphan state.

- [ ] **Step 10: Commit**

```powershell
git add service/main.ahk
git commit -m "feat(service): pause/resume, graceful shutdown, crash recovery"
```

---

## Task 11: End-to-end validation matrix + retire Phase A script

**Files:**
- Modify: `README.md` — append the Phase B service results
- Delete: `hide-any-window.ahk` (Phase A script — no longer needed)

- [ ] **Step 1: Run the matrix**

Run each scenario from the spec's "Testing plan" section that doesn't require the manager. Record outcomes.

| # | Scenario | Pass / Fail | Notes |
|---|---|---|---|
| 1 | Service starts with no config.json | | |
| 2 | Add Magnifier rule via direct config edit, Magnifier already running | | |
| 3 | Open Magnifier while rule is enabled (hook test) | | |
| 4 | Toggle rule's `enabled` to false in config | | |
| 5 | Set `serviceState: "stopped"` in config | | |
| 6 | Set `serviceState: "running"` in config | | |
| 7 | Kill service via Task Manager mid-hide; restart service | | |
| 8 | Edit `config.json` while service runs | | |

Items 9 and 10 from the spec involve the manager — defer to Plan B-2.

- [ ] **Step 2: Append results to `README.md`**

Add this section at the end of `README.md`:

```markdown
## Phase B service — validation results

Tested on Windows 11 Pro, AutoHotkey v2.x, service run as administrator.

| # | Scenario | Result | Notes |
|---|---|---|---|
| 1 | Empty config / no config.json | _pending_ | |
| 2 | Pre-existing window matches new rule | _pending_ | |
| 3 | New window appears, rule already enabled (hook) | _pending_ | |
| 4 | Toggle rule off | _pending_ | |
| 5 | serviceState → stopped | _pending_ | |
| 6 | serviceState → running | _pending_ | |
| 7 | Crash recovery from hidden.json | _pending_ | |
| 8 | Live config edit | _pending_ | |

Replace `_pending_` with ✅ / ❌ as you run each test. If any fail, do NOT delete the Phase A script (Step 3) — debug first.
```

- [ ] **Step 3: Retire the Phase A script (only if all matrix rows pass)**

Once the table above is all ✅:

```powershell
git rm hide-any-window.ahk
```

Update `README.md`'s "Hotkeys" section (which still describes Phase A) to point at the service instead. Replace the existing section with:

```markdown
## How it works

The service is a background AutoHotkey process. It reads `%APPDATA%\HideAnyWindow\config.json` to know which apps to auto-hide, and watches the file for live changes. There are no hotkeys — configuration is via the JSON file (or, after Plan B-2 ships, the WinUI 3 manager app).

To run the service: right-click `service/main.ahk` → **Run as administrator**.
```

- [ ] **Step 4: Commit**

If you got to deleting the Phase A script:

```powershell
git add README.md service/
git commit -m "docs(service): phase B service validation matrix; retire phase A script"
```

If you didn't (some rows failed):

```powershell
git add README.md
git commit -m "docs(service): phase B service validation results (with known issues)"
```

---

## Self-review summary

**1. Spec coverage:**

- Architecture (two processes, JSON + mutex): Tasks 1–10 build the service half; manager half is Plan B-2.
- Service components: Startup scan (Task 6, 8 idempotency), event hook (Task 7), config watcher (Task 8 — uses mtime polling instead of `ReadDirectoryChangesW`; documented as deliberate trade-off), hidden-window registry (Task 4), status mutex (Task 9), stop handling (Task 10), graceful shutdown (Task 10), crash recovery (Task 10), logging (Task 2). ✅
- Config schema: implemented in Task 3 (loader) and exercised end-to-end via direct JSON editing in Tasks 6, 8, 10. ✅
- `hidden.json` schema: Task 4. ✅
- Data flows for hide / toggle off / stop / start / process gone: Tasks 6, 7, 8, 10 cover all of them at the service side. Manager-launching-with-UAC and mutex-based liveness are Plan B-2's responsibility. ✅
- Error handling: malformed config (Task 3), hide failure (Tasks 5, 6 logging), missing config (Task 3 default), single-instance via mutex (Task 9), crash recovery (Task 10). ✅
- Out of scope items remain out of scope. ✅

**2. Placeholders:** searched — no "TBD"/"TODO"/"add appropriate"/"similar to" patterns. The README results table has `_pending_` placeholders for the *user* to fill in during validation, which is intentional, not a plan failure.

**3. Type/name consistency:** `HiddenEntries` (global), entry shape (`Map("hwnd", "exStyle", "ruleId", "title")`), function names (`TryHideWindow`, `RestoreWindowFromEntry`, `RegistryAdd`, `RegistryRemoveByRuleId`, `RegistryDrain`, `LoadConfig`, `GetConfigPath`, `LoadHiddenJson`, `SaveHiddenJson`, `StartupScan`, `WinEventCallback`, `ApplyNewConfig`, `CheckConfigForChanges`, `AcquireServiceMutex`, `ReleaseServiceMutex`, `PauseService`, `ResumeService`, `RecoverOrphanHiddenWindows`, `OnServiceExit`) — all referenced consistently across tasks. ✅

**4. Spec drift to call out:** `ReadDirectoryChangesW` (spec) was replaced by `FileGetTime`-based mtime polling at 1 Hz (plan). Reason: `ReadDirectoryChangesW` requires overlapped I/O, which is awkward in AHK; mtime polling at 1 Hz costs microseconds per second (a single `GetFileAttributesEx`) and meets the spec's "indistinguishable from zero" goal. If the spec drift matters to you, swap to a `FindFirstChangeNotification`-based watcher in a future iteration. Behavior to the user is identical.
